-- Point lots expire exactly one year after each credit and are consumed by earliest expiry first.

CREATE TABLE `point_policies` (
  `point_policy_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `policy_name` VARCHAR(100) NOT NULL,
  `expiration_years` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `use_order` VARCHAR(30) NOT NULL DEFAULT 'EARLIEST_EXPIRY',
  `effective_from` DATETIME NOT NULL,
  `effective_to` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_policy_id`),
  CONSTRAINT `chk_point_policies_expiration`
    CHECK (`expiration_years` > 0),
  CONSTRAINT `chk_point_policies_use_order`
    CHECK (`use_order` = 'EARLIEST_EXPIRY'),
  CONSTRAINT `chk_point_policies_period`
    CHECK (`effective_to` IS NULL OR `effective_to` > `effective_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `point_policies`
  (`policy_name`, `expiration_years`, `use_order`, `effective_from`)
VALUES ('적립일 기준 1년 만료', 1, 'EARLIEST_EXPIRY', '2026-01-01 00:00:00');

CREATE TABLE `point_lots` (
  `point_lot_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `source_transaction_id` BIGINT UNSIGNED NOT NULL,
  `original_amount` INT UNSIGNED NOT NULL,
  `remaining_amount` INT UNSIGNED NOT NULL,
  `lot_status` VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',
  `earned_at` DATETIME NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_lot_id`),
  UNIQUE KEY `uq_point_lots_source_transaction` (`source_transaction_id`),
  KEY `idx_point_lots_customer_expiry`
    (`customer_id`, `lot_status`, `expires_at`, `point_lot_id`),
  CONSTRAINT `fk_point_lots_customer`
    FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_point_lots_source_transaction`
    FOREIGN KEY (`source_transaction_id`) REFERENCES `point_transactions` (`point_transaction_id`),
  CONSTRAINT `chk_point_lots_amounts`
    CHECK (`original_amount` > 0 AND `remaining_amount` <= `original_amount`),
  CONSTRAINT `chk_point_lots_status`
    CHECK (`lot_status` IN ('AVAILABLE','CONSUMED','EXPIRED','REVOKED')),
  CONSTRAINT `chk_point_lots_expiry`
    CHECK (`expires_at` > `earned_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `point_usage_details` (
  `point_usage_detail_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `usage_transaction_id` BIGINT UNSIGNED NOT NULL,
  `point_lot_id` BIGINT UNSIGNED NOT NULL,
  `used_amount` INT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_usage_detail_id`),
  UNIQUE KEY `uq_point_usage_transaction_lot` (`usage_transaction_id`, `point_lot_id`),
  KEY `idx_point_usage_lot` (`point_lot_id`),
  CONSTRAINT `fk_point_usage_transaction`
    FOREIGN KEY (`usage_transaction_id`) REFERENCES `point_transactions` (`point_transaction_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_point_usage_lot`
    FOREIGN KEY (`point_lot_id`) REFERENCES `point_lots` (`point_lot_id`),
  CONSTRAINT `chk_point_usage_amount`
    CHECK (`used_amount` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- The original credit date is unavailable for legacy balances, so wallet.updated_at is the migration baseline.
INSERT INTO `point_transactions`
  (`customer_id`, `transaction_type`, `point_amount`, `balance_after`,
   `idempotency_key`, `description`, `expires_at`, `created_at`)
SELECT pw.`customer_id`, 'ADJUST', pw.`point_balance`, pw.`point_balance`,
       CONCAT('legacy-opening-points-', pw.`customer_id`),
       '기존 포인트 잔액 이관',
       DATE_ADD(pw.`updated_at`, INTERVAL 1 YEAR), pw.`updated_at`
FROM `point_wallets` pw
WHERE pw.`point_balance` > 0
  AND NOT EXISTS (
    SELECT 1 FROM `point_transactions` pt
    WHERE pt.`idempotency_key` = CONCAT('legacy-opening-points-', pw.`customer_id`)
  );

INSERT INTO `point_lots`
  (`customer_id`, `source_transaction_id`, `original_amount`, `remaining_amount`,
   `lot_status`, `earned_at`, `expires_at`)
SELECT pt.`customer_id`, pt.`point_transaction_id`, pt.`point_amount`, pt.`point_amount`,
       'AVAILABLE', pt.`created_at`, pt.`expires_at`
FROM `point_transactions` pt
WHERE pt.`idempotency_key` LIKE 'legacy-opening-points-%'
  AND pt.`point_amount` > 0
  AND pt.`expires_at` IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM `point_lots` pl
    WHERE pl.`source_transaction_id` = pt.`point_transaction_id`
  );

INSERT INTO `permissions` (`permission_code`, `permission_name`)
VALUES ('POINT_MANAGE', '포인트 적립 및 조정');

INSERT INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`role_id`, p.`permission_id`
FROM `roles` r
JOIN `permissions` p ON p.`permission_code` = 'POINT_MANAGE'
WHERE r.`role_code` = 'ADMIN';
