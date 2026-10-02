-- Separate the physical return workflow from financial refund processing.
USE `shupick_v2`;

CREATE TABLE `refunds` (
  `refund_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `refund_number` VARCHAR(32) NOT NULL,
  `payment_id` BIGINT UNSIGNED NOT NULL,
  `return_request_id` BIGINT UNSIGNED DEFAULT NULL,
  `refund_type` VARCHAR(20) NOT NULL,
  `refund_status` VARCHAR(20) NOT NULL DEFAULT 'REQUESTED',
  `refund_amount` INT UNSIGNED NOT NULL,
  `idempotency_key` VARCHAR(100) NOT NULL,
  `provider_refund_key` VARCHAR(100) DEFAULT NULL,
  `failure_code` VARCHAR(50) DEFAULT NULL,
  `failure_message` VARCHAR(255) DEFAULT NULL,
  `retry_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processing_at` DATETIME DEFAULT NULL,
  `completed_at` DATETIME DEFAULT NULL,
  `failed_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`refund_id`),
  UNIQUE KEY `uq_refunds_number` (`refund_number`),
  UNIQUE KEY `uq_refunds_idempotency` (`idempotency_key`),
  UNIQUE KEY `uq_refunds_provider_key` (`provider_refund_key`),
  KEY `idx_refunds_payment_status` (`payment_id`, `refund_status`),
  KEY `idx_refunds_return_request` (`return_request_id`),
  CONSTRAINT `fk_refunds_payment`
    FOREIGN KEY (`payment_id`) REFERENCES `payments` (`payment_id`),
  CONSTRAINT `fk_refunds_return_request`
    FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`),
  CONSTRAINT `chk_refunds_type`
    CHECK (`refund_type` IN ('ORDER_CANCEL','RETURN','MANUAL_ADJUSTMENT')),
  CONSTRAINT `chk_refunds_status`
    CHECK (`refund_status` IN ('REQUESTED','PROCESSING','SUCCEEDED','FAILED','CANCELED')),
  CONSTRAINT `chk_refunds_amount` CHECK (`refund_amount` > 0),
  CONSTRAINT `chk_refunds_retry_count` CHECK (`retry_count` >= 0),
  CONSTRAINT `chk_refunds_completed_at`
    CHECK (`refund_status` <> 'SUCCEEDED' OR `completed_at` IS NOT NULL),
  CONSTRAINT `chk_refunds_failed_at`
    CHECK (`refund_status` <> 'FAILED' OR `failed_at` IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- A refund can cover only some quantities or lines from the original payment.
CREATE TABLE `refund_items` (
  `refund_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `refund_id` BIGINT UNSIGNED NOT NULL,
  `order_item_id` BIGINT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `refund_amount` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`refund_item_id`),
  UNIQUE KEY `uq_refund_items_order_item` (`refund_id`, `order_item_id`),
  KEY `idx_refund_items_order_item` (`order_item_id`),
  CONSTRAINT `fk_refund_items_refund`
    FOREIGN KEY (`refund_id`) REFERENCES `refunds` (`refund_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_refund_items_order_item`
    FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`order_item_id`),
  CONSTRAINT `chk_refund_items_quantity` CHECK (`quantity` > 0),
  CONSTRAINT `chk_refund_items_amount` CHECK (`refund_amount` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Preserve any legacy refund result before removing duplicated refund columns.
INSERT INTO `refunds`
  (`refund_number`, `payment_id`, `return_request_id`, `refund_type`,
   `refund_status`, `refund_amount`, `idempotency_key`, `requested_at`, `completed_at`)
SELECT
  CONCAT('RF-LEGACY-', rr.`return_request_id`),
  (
    SELECT p.`payment_id`
    FROM `payments` p
    WHERE p.`order_id` = rr.`order_id`
    ORDER BY (p.`payment_status` IN ('PAID','PARTIALLY_REFUNDED','REFUNDED')) DESC,
             p.`payment_id` DESC
    LIMIT 1
  ),
  rr.`return_request_id`,
  'RETURN',
  CASE WHEN rr.`refunded_at` IS NULL THEN 'REQUESTED' ELSE 'SUCCEEDED' END,
  rr.`refund_amount`,
  CONCAT('legacy-return-', rr.`return_request_id`),
  rr.`requested_at`,
  rr.`refunded_at`
FROM `return_requests` rr
WHERE rr.`refund_amount` > 0
  AND EXISTS (
    SELECT 1 FROM `payments` p WHERE p.`order_id` = rr.`order_id`
  );

-- Return requests now describe only intake, inspection, and physical return completion.
UPDATE `return_requests`
SET `request_status` = 'COMPLETED'
WHERE `request_status` = 'REFUNDED';

ALTER TABLE `return_requests` DROP CHECK `chk_returns_status`;
ALTER TABLE `return_requests`
  DROP COLUMN `refund_amount`,
  DROP COLUMN `refunded_at`,
  ADD CONSTRAINT `chk_returns_status`
    CHECK (`request_status` IN (
      'REQUESTED','APPROVED','REJECTED','COLLECTING',
      'INSPECTING','RETURNED','COMPLETED','CANCELED'
    ));

-- Payment status is a summary; refund attempts and timestamps remain in refunds.
ALTER TABLE `payments` DROP CHECK `chk_payments_status`;
ALTER TABLE `payments`
  DROP COLUMN `refunded_at`,
  ADD CONSTRAINT `chk_payments_status`
    CHECK (`payment_status` IN (
      'PENDING','PAID','FAILED','CANCELED','PARTIALLY_REFUNDED','REFUNDED'
    ));
