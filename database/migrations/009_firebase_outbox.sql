-- Transactional outbox for reliable MySQL-to-Firebase projections.
USE `shupick_v2`;

CREATE TABLE `outbox_events` (
  `outbox_event_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `aggregate_type` VARCHAR(30) NOT NULL,
  `aggregate_id` BIGINT UNSIGNED NOT NULL,
  `event_type` VARCHAR(50) NOT NULL,
  `payload` JSON NOT NULL,
  `event_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `idempotency_key` VARCHAR(150) NOT NULL,
  `attempt_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `next_attempt_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processing_started_at` DATETIME DEFAULT NULL,
  `published_at` DATETIME DEFAULT NULL,
  `last_error` VARCHAR(500) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`outbox_event_id`),
  UNIQUE KEY `uq_outbox_events_idempotency` (`idempotency_key`),
  KEY `idx_outbox_events_delivery` (`event_status`, `next_attempt_at`, `outbox_event_id`),
  KEY `idx_outbox_events_aggregate` (`aggregate_type`, `aggregate_id`, `outbox_event_id`),
  CONSTRAINT `chk_outbox_events_aggregate_type`
    CHECK (`aggregate_type` IN ('ORDER','FULFILLMENT','PICKUP','INVENTORY')),
  CONSTRAINT `chk_outbox_events_status`
    CHECK (`event_status` IN ('PENDING','PROCESSING','PUBLISHED','FAILED')),
  CONSTRAINT `chk_outbox_events_attempt_count` CHECK (`attempt_count` >= 0),
  CONSTRAINT `chk_outbox_events_published_at`
    CHECK (`event_status` <> 'PUBLISHED' OR `published_at` IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Seed current snapshots so Firebase can be rebuilt from the MySQL source of truth.
INSERT INTO `outbox_events`
  (`aggregate_type`, `aggregate_id`, `event_type`, `payload`, `idempotency_key`)
SELECT
  'ORDER', o.`order_id`, 'ORDER_STATUS_SNAPSHOT',
  JSON_OBJECT(
    'orderId', o.`order_id`, 'customerId', o.`customer_id`,
    'status', o.`order_status`, 'orderedAt', o.`ordered_at`
  ),
  CONCAT('outbox-bootstrap-order-', o.`order_id`)
FROM `orders` o;

INSERT INTO `outbox_events`
  (`aggregate_type`, `aggregate_id`, `event_type`, `payload`, `idempotency_key`)
SELECT
  'FULFILLMENT', f.`fulfillment_id`, 'FULFILLMENT_STATUS_SNAPSHOT',
  JSON_OBJECT(
    'fulfillmentId', f.`fulfillment_id`, 'orderId', f.`order_id`,
    'branchId', f.`destination_branch_id`, 'status', f.`fulfillment_status`
  ),
  CONCAT('outbox-bootstrap-fulfillment-', f.`fulfillment_id`)
FROM `fulfillments` f;

INSERT INTO `outbox_events`
  (`aggregate_type`, `aggregate_id`, `event_type`, `payload`, `idempotency_key`)
SELECT
  'PICKUP', p.`pickup_id`, 'PICKUP_STATUS_SNAPSHOT',
  JSON_OBJECT(
    'pickupId', p.`pickup_id`, 'orderId', p.`order_id`,
    'branchId', p.`branch_id`, 'status', p.`pickup_status`
  ),
  CONCAT('outbox-bootstrap-pickup-', p.`pickup_id`)
FROM `pickups` p;

INSERT INTO `outbox_events`
  (`aggregate_type`, `aggregate_id`, `event_type`, `payload`, `idempotency_key`)
SELECT
  'INVENTORY', hi.`product_variant_id`, 'INVENTORY_STATUS_SNAPSHOT',
  JSON_OBJECT(
    'productVariantId', hi.`product_variant_id`,
    'onHandQuantity', hi.`on_hand_quantity`,
    'reservedQuantity', hi.`reserved_quantity`,
    'defectiveQuantity', hi.`defective_quantity`,
    'availableQuantity', hi.`available_quantity`
  ),
  CONCAT('outbox-bootstrap-inventory-', hi.`product_variant_id`)
FROM `headquarters_inventory` hi;
