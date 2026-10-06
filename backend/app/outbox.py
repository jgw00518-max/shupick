"""Transactional outbox storage and Firestore projection publisher."""

import hmac
import json
from datetime import datetime
from typing import Any, Protocol

from fastapi import APIRouter, Header, HTTPException, Query
from firebase_admin import firestore
from pymysql import MySQLError
from pymysql.connections import Connection

from .auth import get_firebase_app
from .config import settings
from .database import mysql_connection


router = APIRouter(prefix="/internal/outbox", tags=["internal"])


class OutboxPublisher(Protocol):
    def publish(self, event: dict[str, Any]) -> None:
        """Publish one claimed event or raise an exception."""


def enqueue_outbox_event(
    connection: Connection,
    *,
    aggregate_type: str,
    aggregate_id: int,
    event_type: str,
    payload: dict[str, Any],
    idempotency_key: str,
) -> None:
    """Insert an event using the caller's existing business transaction."""

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO outbox_events
              (aggregate_type,aggregate_id,event_type,payload,idempotency_key)
            VALUES (%s,%s,%s,%s,%s)
            ON DUPLICATE KEY UPDATE outbox_event_id=outbox_event_id
            """,
            (
                aggregate_type,
                aggregate_id,
                event_type,
                json.dumps(payload, ensure_ascii=False, default=str),
                idempotency_key,
            ),
        )


def retry_delay_seconds(attempt_count: int) -> int:
    """Use capped exponential backoff for transient Firebase failures."""

    return min(30 * (2 ** max(attempt_count - 1, 0)), 3600)


class FirestoreOutboxPublisher:
    """Project MySQL events to current-state Firestore documents."""

    _collections = {
        "ORDER": "orderStatuses",
        "FULFILLMENT": "fulfillmentStatuses",
        "PICKUP": "pickupStatuses",
        "INVENTORY": "inventoryStatuses",
    }

    def publish(self, event: dict[str, Any]) -> None:
        collection = self._collections[str(event["aggregate_type"])]
        client = firestore.client(app=get_firebase_app())
        reference = client.collection(collection).document(str(event["aggregate_id"]))
        transaction = client.transaction()
        payload = event["payload"]
        if isinstance(payload, str):
            payload = json.loads(payload)
        document = {
            **payload,
            "eventType": event["event_type"],
            "lastOutboxEventId": int(event["outbox_event_id"]),
            "syncedAt": firestore.SERVER_TIMESTAMP,
        }
        # 소유권은 이벤트 입력값 대신 MySQL에서 조회하여 읽기 규칙에 사용합니다.
        if event['aggregate_type'] != 'INVENTORY':
            with mysql_connection() as connection:
                with connection.cursor() as cursor:
                    joins = {'ORDER': 'orders o',
                        'FULFILLMENT': 'fulfillments entity JOIN orders o ON o.order_id=entity.order_id',
                        'PICKUP': 'pickups entity JOIN orders o ON o.order_id=entity.order_id'}
                    keys = {'ORDER':'o.order_id','FULFILLMENT':'entity.fulfillment_id','PICKUP':'entity.pickup_id'}
                    cursor.execute(f"SELECT o.order_id,c.firebase_uid FROM {joins[event['aggregate_type']]} JOIN customers c ON c.customer_id=o.customer_id WHERE {keys[event['aggregate_type']]}=%s", (event['aggregate_id'],))
                    owner = cursor.fetchone()
                    if owner is None: raise ValueError('Projection owner not found')
                    document['customerUid'] = owner['firebase_uid']
                    document['orderId'] = owner['order_id']

        @firestore.transactional
        def write_if_newer(current_transaction: Any) -> None:
            snapshot = reference.get(transaction=current_transaction)
            current_id = snapshot.get("lastOutboxEventId") if snapshot.exists else None
            if current_id is None or int(current_id) < int(event["outbox_event_id"]):
                current_transaction.set(reference, document, merge=True)

        write_if_newer(transaction)


def _claim_next_event() -> dict[str, Any] | None:
    with mysql_connection() as connection:
        try:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE outbox_events
                    SET event_status='FAILED',processing_started_at=NULL,
                        next_attempt_at=NOW(),last_error='Processing lease expired'
                    WHERE event_status='PROCESSING'
                      AND processing_started_at < DATE_SUB(NOW(),INTERVAL 5 MINUTE)
                    """
                )
                cursor.execute(
                    """
                    SELECT * FROM outbox_events
                    WHERE event_status IN ('PENDING','FAILED')
                      AND next_attempt_at <= NOW()
                    ORDER BY outbox_event_id
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED
                    """
                )
                event = cursor.fetchone()
                if event is None:
                    connection.commit()
                    return None
                cursor.execute(
                    """
                    UPDATE outbox_events
                    SET event_status='PROCESSING',attempt_count=attempt_count+1,
                        processing_started_at=NOW(),last_error=NULL
                    WHERE outbox_event_id=%s
                    """,
                    (event["outbox_event_id"],),
                )
                event["attempt_count"] = int(event["attempt_count"]) + 1
            connection.commit()
            return event
        except Exception:
            connection.rollback()
            raise


def _mark_published(event_id: int) -> None:
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE outbox_events
                SET event_status='PUBLISHED',published_at=NOW(),processing_started_at=NULL,
                    last_error=NULL
                WHERE outbox_event_id=%s AND event_status='PROCESSING'
                """,
                (event_id,),
            )
        connection.commit()


def _mark_failed(event_id: int, attempt_count: int, error: Exception) -> None:
    delay_seconds = retry_delay_seconds(attempt_count)
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE outbox_events
                SET event_status='FAILED',processing_started_at=NULL,
                    next_attempt_at=DATE_ADD(NOW(),INTERVAL %s SECOND),last_error=%s
                WHERE outbox_event_id=%s AND event_status='PROCESSING'
                """,
                (delay_seconds, str(error)[:500], event_id),
            )
        connection.commit()


def publish_pending_events(limit: int, publisher: OutboxPublisher | None = None) -> dict[str, int]:
    """Claim and publish at most limit events without holding DB locks over network I/O."""

    selected_publisher = publisher or FirestoreOutboxPublisher()
    published = 0
    failed = 0
    for _ in range(limit):
        event = _claim_next_event()
        if event is None:
            break
        try:
            selected_publisher.publish(event)
            _mark_published(int(event["outbox_event_id"]))
            published += 1
        except Exception as error:
            _mark_failed(int(event["outbox_event_id"]), int(event["attempt_count"]), error)
            failed += 1
    return {"published": published, "failed": failed}


def _verify_worker_secret(provided_secret: str | None) -> None:
    if not settings.outbox_worker_secret:
        raise HTTPException(status_code=503, detail="Outbox worker secret is not configured")
    if provided_secret is None or not hmac.compare_digest(provided_secret, settings.outbox_worker_secret):
        raise HTTPException(status_code=401, detail="Invalid outbox worker secret")


@router.post("/publish")
def publish_outbox(
    limit: int = Query(default=50, ge=1, le=500),
    worker_secret: str | None = Header(default=None, alias="X-Outbox-Secret"),
) -> dict[str, int]:
    """Run one protected outbox publishing batch."""

    _verify_worker_secret(worker_secret)
    try:
        return publish_pending_events(limit)
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
