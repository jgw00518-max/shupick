-- Enforce refund/order consistency and record coupon restoration policy/history.
USE `shupick_v2`;

ALTER TABLE `payments`
  ADD UNIQUE KEY `uq_payments_id_order` (`payment_id`, `order_id`);

ALTER TABLE `refunds`
  ADD COLUMN `order_id` BIGINT UNSIGNED DEFAULT NULL AFTER `payment_id`;

UPDATE `refunds` r
JOIN `payments` p ON p.`payment_id` = r.`payment_id`
SET r.`order_id` = p.`order_id`;

ALTER TABLE `refunds`
  MODIFY COLUMN `order_id` BIGINT UNSIGNED NOT NULL,
  ADD UNIQUE KEY `uq_refunds_id_order` (`refund_id`, `order_id`),
  ADD KEY `idx_refunds_order_status` (`order_id`, `refund_status`),
  DROP FOREIGN KEY `fk_refunds_payment`,
  ADD CONSTRAINT `fk_refunds_payment_order`
    FOREIGN KEY (`payment_id`, `order_id`)
    REFERENCES `payments` (`payment_id`, `order_id`);

ALTER TABLE `order_items`
  ADD UNIQUE KEY `uq_order_items_id_order` (`order_item_id`, `order_id`);

ALTER TABLE `refund_items`
  ADD COLUMN `order_id` BIGINT UNSIGNED DEFAULT NULL AFTER `refund_id`;

UPDATE `refund_items` ri
JOIN `order_items` oi ON oi.`order_item_id` = ri.`order_item_id`
SET ri.`order_id` = oi.`order_id`;

ALTER TABLE `refund_items`
  MODIFY COLUMN `order_id` BIGINT UNSIGNED NOT NULL,
  DROP FOREIGN KEY `fk_refund_items_refund`,
  DROP FOREIGN KEY `fk_refund_items_order_item`,
  ADD CONSTRAINT `fk_refund_items_refund_order`
    FOREIGN KEY (`refund_id`, `order_id`)
    REFERENCES `refunds` (`refund_id`, `order_id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_refund_items_order_item_order`
    FOREIGN KEY (`order_item_id`, `order_id`)
    REFERENCES `order_items` (`order_item_id`, `order_id`);

CREATE TABLE `coupon_refund_policies` (
  `coupon_refund_policy_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `policy_name` VARCHAR(100) NOT NULL,
  `effective_from` DATE NOT NULL,
  `effective_to` DATE DEFAULT NULL,
  `restore_on_full_cancel` BOOLEAN NOT NULL DEFAULT TRUE,
  `restore_on_partial_return` BOOLEAN NOT NULL DEFAULT FALSE,
  `require_unexpired_coupon` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`coupon_refund_policy_id`),
  UNIQUE KEY `uq_coupon_refund_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_coupon_refund_policies_period`
    CHECK (`effective_to` IS NULL OR `effective_to` >= `effective_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `coupon_refund_policies`
  (`policy_name`, `effective_from`, `restore_on_full_cancel`,
   `restore_on_partial_return`, `require_unexpired_coupon`)
VALUES
  ('전체 주문 취소 시 유효 쿠폰 복원', '2026-10-02', TRUE, FALSE, TRUE);

CREATE TABLE `coupon_restorations` (
  `coupon_restoration_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_coupon_id` BIGINT UNSIGNED NOT NULL,
  `refund_id` BIGINT UNSIGNED NOT NULL,
  `coupon_refund_policy_id` BIGINT UNSIGNED NOT NULL,
  `previous_status` VARCHAR(20) NOT NULL,
  `restoration_reason` VARCHAR(255) NOT NULL,
  `restored_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`coupon_restoration_id`),
  UNIQUE KEY `uq_coupon_restorations_coupon_refund`
    (`customer_coupon_id`, `refund_id`),
  KEY `idx_coupon_restorations_refund` (`refund_id`),
  KEY `idx_coupon_restorations_policy` (`coupon_refund_policy_id`),
  CONSTRAINT `fk_coupon_restorations_coupon`
    FOREIGN KEY (`customer_coupon_id`)
    REFERENCES `customer_coupons` (`customer_coupon_id`),
  CONSTRAINT `fk_coupon_restorations_refund`
    FOREIGN KEY (`refund_id`) REFERENCES `refunds` (`refund_id`),
  CONSTRAINT `fk_coupon_restorations_policy`
    FOREIGN KEY (`coupon_refund_policy_id`)
    REFERENCES `coupon_refund_policies` (`coupon_refund_policy_id`),
  CONSTRAINT `chk_coupon_restorations_previous_status`
    CHECK (`previous_status` IN ('USED','EXPIRED','REVOKED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
