"""Point ledger, one-year expiration lots, and earliest-expiry spending."""

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pymysql import MySQLError
from pymysql.connections import Connection

from .auth import CurrentCustomer, CurrentEmployee, get_current_customer, require_permission
from .database import mysql_connection
from .schemas import (
    PointCreditRequest,
    PointLotResponse,
    PointTransactionResponse,
    PointUseRequest,
    PointWalletResponse,
)


router = APIRouter(prefix="/points", tags=["points"])


def _transaction_response(row: dict[str, Any]) -> PointTransactionResponse:
    return PointTransactionResponse(
        pointTransactionId=int(row["point_transaction_id"]),
        transactionType=str(row["transaction_type"]),
        pointAmount=int(row["point_amount"]),
        balanceAfter=int(row["balance_after"]),
        expiresAt=row["expires_at"],
    )


def _expire_customer_points(connection: Connection, customer_id: int, now: datetime | None = None) -> int:
    """Expire all due lots for one customer while the caller owns the transaction."""

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT point_balance FROM point_wallets WHERE customer_id=%s FOR UPDATE",
            (customer_id,),
        )
        wallet = cursor.fetchone()
        if wallet is None:
            raise HTTPException(status_code=404, detail="Point wallet not found")
        now_value = now or datetime.now()
        cursor.execute(
            """
            SELECT point_lot_id,remaining_amount
            FROM point_lots
            WHERE customer_id=%s AND lot_status='AVAILABLE'
              AND remaining_amount > 0 AND expires_at <= %s
            ORDER BY expires_at,point_lot_id
            FOR UPDATE
            """,
            (customer_id, now_value),
        )
        lots = cursor.fetchall()
        expired = sum(int(lot["remaining_amount"]) for lot in lots)
        if expired == 0:
            return 0
        balance = int(wallet["point_balance"])
        if expired > balance:
            raise HTTPException(status_code=409, detail="Point ledger exceeds wallet balance")
        idempotency_key = f"expire-{customer_id}-{now_value:%Y%m%d%H%M%S%f}"
        cursor.execute(
            """
            INSERT INTO point_transactions
              (customer_id,transaction_type,point_amount,balance_after,idempotency_key,description,created_at)
            VALUES (%s,'EXPIRE',%s,%s,%s,'유효기간 1년 경과',%s)
            """,
            (customer_id, -expired, balance - expired, idempotency_key, now_value),
        )
        transaction_id = int(cursor.lastrowid)
        for lot in lots:
            cursor.execute(
                """
                INSERT INTO point_usage_details (usage_transaction_id,point_lot_id,used_amount)
                VALUES (%s,%s,%s)
                """,
                (transaction_id, lot["point_lot_id"], lot["remaining_amount"]),
            )
            cursor.execute(
                """
                UPDATE point_lots
                SET remaining_amount=0,lot_status='EXPIRED'
                WHERE point_lot_id=%s
                """,
                (lot["point_lot_id"],),
            )
        cursor.execute(
            "UPDATE point_wallets SET point_balance=%s WHERE customer_id=%s",
            (balance - expired, customer_id),
        )
        return expired


def expire_all_due_points(connection: Connection, now: datetime | None = None) -> int:
    """Expire due lots for every affected customer; intended for a scheduled worker."""

    now_value = now or datetime.now()
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT DISTINCT customer_id
            FROM point_lots
            WHERE lot_status='AVAILABLE' AND remaining_amount > 0 AND expires_at <= %s
            """,
            (now_value,),
        )
        customer_ids = [int(row["customer_id"]) for row in cursor.fetchall()]
    return sum(_expire_customer_points(connection, customer_id, now_value) for customer_id in customer_ids)


@router.get("/wallet", response_model=PointWalletResponse)
def get_wallet(current: CurrentCustomer = Depends(get_current_customer)) -> PointWalletResponse:
    try:
        with mysql_connection() as connection:
            _expire_customer_points(connection, current.customer_id)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT point_balance FROM point_wallets WHERE customer_id=%s",
                    (current.customer_id,),
                )
                wallet = cursor.fetchone()
                cursor.execute(
                    """
                    SELECT remaining_amount,earned_at,expires_at
                    FROM point_lots
                    WHERE customer_id=%s AND lot_status='AVAILABLE' AND remaining_amount > 0
                    ORDER BY expires_at,point_lot_id
                    """,
                    (current.customer_id,),
                )
                lots = cursor.fetchall()
            connection.commit()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    if wallet is None:
        raise HTTPException(status_code=404, detail="Point wallet not found")
    return PointWalletResponse(
        balance=int(wallet["point_balance"]),
        lots=[
            PointLotResponse(
                remainingAmount=int(lot["remaining_amount"]),
                earnedAt=lot["earned_at"],
                expiresAt=lot["expires_at"],
            )
            for lot in lots
        ],
    )


# 신규 적립은 reviews.save_review의 구매 항목별 최초 작성에서만 허용한다.
def credit_points(
    request: PointCreditRequest,
    _: CurrentEmployee = Depends(require_permission("POINT_MANAGE")),
) -> PointTransactionResponse:
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT * FROM point_transactions WHERE idempotency_key=%s",
                    (request.idempotencyKey,),
                )
                existing = cursor.fetchone()
                if existing is not None:
                    if (
                        int(existing["customer_id"]) != request.customerId
                        or str(existing["transaction_type"]) != "EARN"
                        or int(existing["point_amount"]) != request.amount
                    ):
                        raise HTTPException(status_code=409, detail="Idempotency key is already in use")
                    return _transaction_response(existing)
                cursor.execute(
                    "SELECT point_balance FROM point_wallets WHERE customer_id=%s FOR UPDATE",
                    (request.customerId,),
                )
                wallet = cursor.fetchone()
                if wallet is None:
                    raise HTTPException(status_code=404, detail="Point wallet not found")
                balance = int(wallet["point_balance"]) + request.amount
                cursor.execute(
                    """
                    INSERT INTO point_transactions
                      (customer_id,transaction_type,point_amount,balance_after,idempotency_key,
                       description,expires_at,created_at)
                    VALUES (%s,'EARN',%s,%s,%s,%s,DATE_ADD(NOW(),INTERVAL 1 YEAR),NOW())
                    """,
                    (
                        request.customerId,
                        request.amount,
                        balance,
                        request.idempotencyKey,
                        request.description,
                    ),
                )
                transaction_id = int(cursor.lastrowid)
                cursor.execute(
                    """
                    INSERT INTO point_lots
                      (customer_id,source_transaction_id,original_amount,remaining_amount,
                       lot_status,earned_at,expires_at)
                    SELECT customer_id,point_transaction_id,point_amount,point_amount,
                           'AVAILABLE',created_at,expires_at
                    FROM point_transactions WHERE point_transaction_id=%s
                    """,
                    (transaction_id,),
                )
                cursor.execute(
                    "UPDATE point_wallets SET point_balance=%s WHERE customer_id=%s",
                    (balance, request.customerId),
                )
                cursor.execute(
                    "SELECT * FROM point_transactions WHERE point_transaction_id=%s",
                    (transaction_id,),
                )
                row = cursor.fetchone()
            connection.commit()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return _transaction_response(row)


@router.post("/use", response_model=PointTransactionResponse)
def use_points(
    request: PointUseRequest,
    current: CurrentCustomer = Depends(get_current_customer),
) -> PointTransactionResponse:
    try:
        with mysql_connection() as connection:
            _expire_customer_points(connection, current.customer_id)
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT * FROM point_transactions WHERE idempotency_key=%s",
                    (request.idempotencyKey,),
                )
                existing = cursor.fetchone()
                if existing is not None:
                    if int(existing["customer_id"]) != current.customer_id:
                        raise HTTPException(status_code=409, detail="Idempotency key is already in use")
                    return _transaction_response(existing)
                cursor.execute(
                    "SELECT point_balance FROM point_wallets WHERE customer_id=%s FOR UPDATE",
                    (current.customer_id,),
                )
                wallet = cursor.fetchone()
                if wallet is None:
                    raise HTTPException(status_code=404, detail="Point wallet not found")
                balance = int(wallet["point_balance"])
                if balance < request.amount:
                    raise HTTPException(status_code=409, detail="Insufficient points")
                cursor.execute(
                    """
                    SELECT point_lot_id,remaining_amount
                    FROM point_lots
                    WHERE customer_id=%s AND lot_status='AVAILABLE'
                      AND remaining_amount > 0 AND expires_at > NOW()
                    ORDER BY expires_at,point_lot_id
                    FOR UPDATE
                    """,
                    (current.customer_id,),
                )
                lots = cursor.fetchall()
                if sum(int(lot["remaining_amount"]) for lot in lots) < request.amount:
                    raise HTTPException(status_code=409, detail="Spendable point lots do not match wallet balance")
                cursor.execute(
                    """
                    INSERT INTO point_transactions
                      (customer_id,transaction_type,point_amount,balance_after,order_id,
                       idempotency_key,description)
                    VALUES (%s,'USE',%s,%s,%s,%s,'포인트 사용')
                    """,
                    (
                        current.customer_id,
                        -request.amount,
                        balance - request.amount,
                        request.orderId,
                        request.idempotencyKey,
                    ),
                )
                transaction_id = int(cursor.lastrowid)
                remaining_to_use = request.amount
                for lot in lots:
                    if remaining_to_use == 0:
                        break
                    lot_balance = int(lot["remaining_amount"])
                    used = min(lot_balance, remaining_to_use)
                    new_lot_balance = lot_balance - used
                    cursor.execute(
                        """
                        INSERT INTO point_usage_details
                          (usage_transaction_id,point_lot_id,used_amount)
                        VALUES (%s,%s,%s)
                        """,
                        (transaction_id, lot["point_lot_id"], used),
                    )
                    cursor.execute(
                        """
                        UPDATE point_lots
                        SET remaining_amount=%s,lot_status=%s
                        WHERE point_lot_id=%s
                        """,
                        (
                            new_lot_balance,
                            "CONSUMED" if new_lot_balance == 0 else "AVAILABLE",
                            lot["point_lot_id"],
                        ),
                    )
                    remaining_to_use -= used
                cursor.execute(
                    "UPDATE point_wallets SET point_balance=%s WHERE customer_id=%s",
                    (balance - request.amount, current.customer_id),
                )
                cursor.execute(
                    "SELECT * FROM point_transactions WHERE point_transaction_id=%s",
                    (transaction_id,),
                )
                row = cursor.fetchone()
            connection.commit()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return _transaction_response(row)
