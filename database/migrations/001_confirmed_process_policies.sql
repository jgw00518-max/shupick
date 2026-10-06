-- Confirmed Shupick process policies for shupick_v2
-- Run once after shupick_schema_v2.sql and shupick_v2_seed.sql.

USE `shupick_v2`;

-- A district can contain multiple branches, so district_code is indexed but not unique.
ALTER TABLE `branches`
  ADD COLUMN `district_code` VARCHAR(20) NOT NULL DEFAULT 'UNASSIGNED' AFTER `branch_name`;

CREATE INDEX `idx_branches_district_code` ON `branches` (`district_code`);

CREATE TABLE `branch_business_hours` (
  `branch_business_hour_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `day_of_week` TINYINT UNSIGNED NOT NULL COMMENT '1=Monday, 7=Sunday',
  `opens_at` TIME DEFAULT NULL,
  `closes_at` TIME DEFAULT NULL,
  `is_closed` BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (`branch_business_hour_id`),
  UNIQUE KEY `uq_branch_business_hours_day` (`branch_id`, `day_of_week`),
  CONSTRAINT `fk_branch_business_hours_branch`
    FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_branch_business_hours_day`
    CHECK (`day_of_week` BETWEEN 1 AND 7),
  CONSTRAINT `chk_branch_business_hours_time`
    CHECK (
      (`is_closed` = TRUE AND `opens_at` IS NULL AND `closes_at` IS NULL)
      OR
      (`is_closed` = FALSE AND `opens_at` IS NOT NULL AND `closes_at` IS NOT NULL AND `opens_at` < `closes_at`)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Firebase Authentication owns credentials; birth date is needed only for birthday benefits.
ALTER TABLE `customers`
  ADD COLUMN `birth_date` DATE DEFAULT NULL AFTER `phone`;

-- Exchange is out of scope. Retain return/refund states only.
ALTER TABLE `stocks` DROP CHECK `chk_stocks_status`;
ALTER TABLE `stocks`
  ADD CONSTRAINT `chk_stocks_status`
  CHECK (`inventory_status` IN ('AVAILABLE','AWAITING_PICKUP','RETURNED','DEFECTIVE','UNAVAILABLE'));

ALTER TABLE `return_requests` DROP CHECK `chk_returns_type`;
ALTER TABLE `return_requests` DROP CHECK `chk_returns_status`;
ALTER TABLE `return_requests` DROP COLUMN `request_type`;
ALTER TABLE `return_requests`
  ADD CONSTRAINT `chk_returns_status`
  CHECK (`request_status` IN ('REQUESTED','APPROVED','REJECTED','COLLECTING','INSPECTING','REFUNDED','COMPLETED','CANCELED'));

CREATE TABLE `after_sales_inspections` (
  `after_sales_inspection_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `return_request_id` BIGINT UNSIGNED NOT NULL,
  `inspection_stage` VARCHAR(20) NOT NULL,
  `inspected_by_employee_id` BIGINT UNSIGNED NOT NULL,
  `has_wear_marks` BOOLEAN NOT NULL DEFAULT FALSE,
  `has_product_damage` BOOLEAN NOT NULL DEFAULT FALSE,
  `has_customer_fault` BOOLEAN NOT NULL DEFAULT FALSE,
  `components_complete` BOOLEAN NOT NULL DEFAULT TRUE,
  `packaging_intact` BOOLEAN NOT NULL DEFAULT TRUE,
  `has_product_defect` BOOLEAN NOT NULL DEFAULT FALSE,
  `is_wrong_item` BOOLEAN NOT NULL DEFAULT FALSE,
  `inspection_decision` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `inspection_notes` TEXT DEFAULT NULL,
  `inspected_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`after_sales_inspection_id`),
  UNIQUE KEY `uq_after_sales_inspection_stage` (`return_request_id`, `inspection_stage`),
  KEY `idx_after_sales_inspections_employee` (`inspected_by_employee_id`),
  CONSTRAINT `fk_after_sales_inspections_return_request`
    FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_after_sales_inspections_employee`
    FOREIGN KEY (`inspected_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_after_sales_inspections_stage`
    CHECK (`inspection_stage` IN ('BRANCH','HEADQUARTERS')),
  CONSTRAINT `chk_after_sales_inspections_decision`
    CHECK (`inspection_decision` IN ('PENDING','ACCEPTED','REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- A pickup is held for 14 full days after branch arrival, then recalled on the next day.
ALTER TABLE `pickups`
  ADD COLUMN `arrived_at` DATETIME DEFAULT NULL AFTER `pickup_status`,
  ADD COLUMN `pickup_deadline_at` DATETIME DEFAULT NULL AFTER `ready_at`,
  ADD COLUMN `recalled_at` DATETIME DEFAULT NULL AFTER `picked_up_at`;

CREATE TABLE `pickup_reminders` (
  `pickup_reminder_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `pickup_id` BIGINT UNSIGNED NOT NULL,
  `reminder_type` VARCHAR(30) NOT NULL,
  `scheduled_at` DATETIME NOT NULL,
  `sent_at` DATETIME DEFAULT NULL,
  `delivery_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `firebase_notification_id` VARCHAR(128) DEFAULT NULL,
  PRIMARY KEY (`pickup_reminder_id`),
  UNIQUE KEY `uq_pickup_reminders_type` (`pickup_id`, `reminder_type`),
  CONSTRAINT `fk_pickup_reminders_pickup`
    FOREIGN KEY (`pickup_id`) REFERENCES `pickups` (`pickup_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_pickup_reminders_type`
    CHECK (`reminder_type` IN ('ARRIVAL','WEEK_PASSED','PRE_RECALL','RECALL_PROCESSED')),
  CONSTRAINT `chk_pickup_reminders_status`
    CHECK (`delivery_status` IN ('PENDING','SENT','FAILED','CANCELED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Reorder threshold is evaluated per SKU against its initial HQ receipt quantity.
CREATE TABLE `inventory_policies` (
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `initial_stock_quantity` INT UNSIGNED NOT NULL,
  `reorder_threshold_percent` DECIMAL(5,2) NOT NULL DEFAULT 30.00,
  `reorder_quantity` INT UNSIGNED NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_variant_id`),
  CONSTRAINT `fk_inventory_policies_variant`
    FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_inventory_policies_initial_quantity`
    CHECK (`initial_stock_quantity` > 0),
  CONSTRAINT `chk_inventory_policies_threshold`
    CHECK (`reorder_threshold_percent` > 0 AND `reorder_threshold_percent` < 100),
  CONSTRAINT `chk_inventory_policies_reorder_quantity`
    CHECK (`reorder_quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `inventory_policies`
  (`product_variant_id`, `initial_stock_quantity`, `reorder_threshold_percent`, `reorder_quantity`)
SELECT
  v.`product_variant_id`,
  COALESCE(SUM(s.`stock_quantity`), 1),
  30.00,
  GREATEST(COALESCE(SUM(s.`stock_quantity`), 1), 1)
FROM `product_variants` v
LEFT JOIN `stocks` s ON s.`product_variant_id` = v.`product_variant_id`
GROUP BY v.`product_variant_id`;

CREATE TABLE `membership_tiers` (
  `membership_tier_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `tier_code` VARCHAR(20) NOT NULL,
  `tier_name` VARCHAR(50) NOT NULL,
  `minimum_amount` INT UNSIGNED NOT NULL,
  `maximum_amount_exclusive` INT UNSIGNED DEFAULT NULL,
  `sort_order` TINYINT UNSIGNED NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`membership_tier_id`),
  UNIQUE KEY `uq_membership_tiers_code` (`tier_code`),
  UNIQUE KEY `uq_membership_tiers_sort_order` (`sort_order`),
  CONSTRAINT `chk_membership_tiers_range`
    CHECK (`maximum_amount_exclusive` IS NULL OR `maximum_amount_exclusive` > `minimum_amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `membership_tiers`
  (`tier_code`, `tier_name`, `minimum_amount`, `maximum_amount_exclusive`, `sort_order`)
VALUES
  ('BASIC', 'BASIC', 0, 300000, 1),
  ('BRONZE', 'BRONZE', 300000, 600000, 2),
  ('SILVER', 'SILVER', 600000, 1000000, 3),
  ('GOLD', 'GOLD', 1000000, 1500000, 4),
  ('VIP', 'VIP', 1500000, NULL, 5);

CREATE TABLE `membership_assessments` (
  `membership_assessment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `membership_tier_id` BIGINT UNSIGNED NOT NULL,
  `benefit_month` DATE NOT NULL COMMENT 'First day of the month',
  `calculation_started_at` DATE NOT NULL,
  `calculation_ended_at` DATE NOT NULL,
  `confirmed_purchase_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `canceled_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `returned_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `net_purchase_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `assessed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`membership_assessment_id`),
  UNIQUE KEY `uq_membership_assessments_customer_month` (`customer_id`, `benefit_month`),
  KEY `idx_membership_assessments_tier` (`membership_tier_id`),
  CONSTRAINT `fk_membership_assessments_customer`
    FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_membership_assessments_tier`
    FOREIGN KEY (`membership_tier_id`) REFERENCES `membership_tiers` (`membership_tier_id`),
  CONSTRAINT `chk_membership_assessments_month`
    CHECK (DAYOFMONTH(`benefit_month`) = 1),
  CONSTRAINT `chk_membership_assessments_amount`
    CHECK (`net_purchase_amount` + `canceled_amount` + `returned_amount` = `confirmed_purchase_amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `coupon_definitions` (
  `coupon_definition_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `coupon_code` VARCHAR(40) NOT NULL,
  `coupon_name` VARCHAR(100) NOT NULL,
  `discount_type` VARCHAR(20) NOT NULL,
  `discount_value` INT UNSIGNED NOT NULL,
  `minimum_order_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `maximum_discount_amount` INT UNSIGNED DEFAULT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`coupon_definition_id`),
  UNIQUE KEY `uq_coupon_definitions_code` (`coupon_code`),
  CONSTRAINT `chk_coupon_definitions_type`
    CHECK (`discount_type` IN ('PERCENT','FIXED')),
  CONSTRAINT `chk_coupon_definitions_value`
    CHECK (
      (`discount_type` = 'PERCENT' AND `discount_value` BETWEEN 1 AND 100)
      OR (`discount_type` = 'FIXED' AND `discount_value` > 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `coupon_definitions`
  (`coupon_code`, `coupon_name`, `discount_type`, `discount_value`)
VALUES
  ('MEMBERSHIP_5_PERCENT', '멤버십 5% 할인쿠폰', 'PERCENT', 5),
  ('MEMBERSHIP_10_PERCENT', '멤버십 10% 할인쿠폰', 'PERCENT', 10),
  ('MEMBERSHIP_15_PERCENT', '멤버십 15% 할인쿠폰', 'PERCENT', 15);

CREATE TABLE `membership_coupon_rules` (
  `membership_tier_id` BIGINT UNSIGNED NOT NULL,
  `coupon_definition_id` BIGINT UNSIGNED NOT NULL,
  `monthly_quantity` TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (`membership_tier_id`, `coupon_definition_id`),
  CONSTRAINT `fk_membership_coupon_rules_tier`
    FOREIGN KEY (`membership_tier_id`) REFERENCES `membership_tiers` (`membership_tier_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_membership_coupon_rules_coupon`
    FOREIGN KEY (`coupon_definition_id`) REFERENCES `coupon_definitions` (`coupon_definition_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_membership_coupon_rules_quantity`
    CHECK (`monthly_quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `membership_coupon_rules`
  (`membership_tier_id`, `coupon_definition_id`, `monthly_quantity`)
SELECT t.`membership_tier_id`, c.`coupon_definition_id`, rules.`monthly_quantity`
FROM (
  SELECT 'BASIC' AS `tier_code`, 'MEMBERSHIP_5_PERCENT' AS `coupon_code`, 1 AS `monthly_quantity`
  UNION ALL SELECT 'BRONZE', 'MEMBERSHIP_5_PERCENT', 2
  UNION ALL SELECT 'SILVER', 'MEMBERSHIP_5_PERCENT', 2
  UNION ALL SELECT 'SILVER', 'MEMBERSHIP_10_PERCENT', 1
  UNION ALL SELECT 'GOLD', 'MEMBERSHIP_10_PERCENT', 2
  UNION ALL SELECT 'GOLD', 'MEMBERSHIP_15_PERCENT', 1
  UNION ALL SELECT 'VIP', 'MEMBERSHIP_10_PERCENT', 2
  UNION ALL SELECT 'VIP', 'MEMBERSHIP_15_PERCENT', 2
) rules
JOIN `membership_tiers` t ON t.`tier_code` = rules.`tier_code`
JOIN `coupon_definitions` c ON c.`coupon_code` = rules.`coupon_code`;

CREATE TABLE `customer_coupons` (
  `customer_coupon_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `coupon_definition_id` BIGINT UNSIGNED NOT NULL,
  `benefit_month` DATE NOT NULL,
  `issue_sequence` TINYINT UNSIGNED NOT NULL,
  `coupon_status` VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',
  `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME NOT NULL,
  `used_order_id` BIGINT UNSIGNED DEFAULT NULL,
  `used_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`customer_coupon_id`),
  UNIQUE KEY `uq_customer_coupons_monthly_issue`
    (`customer_id`, `coupon_definition_id`, `benefit_month`, `issue_sequence`),
  KEY `idx_customer_coupons_order` (`used_order_id`),
  CONSTRAINT `fk_customer_coupons_customer`
    FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_customer_coupons_definition`
    FOREIGN KEY (`coupon_definition_id`) REFERENCES `coupon_definitions` (`coupon_definition_id`),
  CONSTRAINT `fk_customer_coupons_order`
    FOREIGN KEY (`used_order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_customer_coupons_month`
    CHECK (DAYOFMONTH(`benefit_month`) = 1),
  CONSTRAINT `chk_customer_coupons_status`
    CHECK (`coupon_status` IN ('AVAILABLE','USED','EXPIRED','REVOKED')),
  CONSTRAINT `chk_customer_coupons_expiry`
    CHECK (`expires_at` >= `issued_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `point_wallets` (
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `point_balance` INT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`),
  CONSTRAINT `fk_point_wallets_customer`
    FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `point_wallets` (`customer_id`, `point_balance`)
SELECT `customer_id`, `reward_points` FROM `customers`;

CREATE TABLE `point_transactions` (
  `point_transaction_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `transaction_type` VARCHAR(20) NOT NULL,
  `point_amount` INT NOT NULL,
  `balance_after` INT UNSIGNED NOT NULL,
  `order_id` BIGINT UNSIGNED DEFAULT NULL,
  `review_id` BIGINT UNSIGNED DEFAULT NULL,
  `idempotency_key` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) DEFAULT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_transaction_id`),
  UNIQUE KEY `uq_point_transactions_idempotency` (`idempotency_key`),
  KEY `idx_point_transactions_customer_time` (`customer_id`, `created_at`),
  KEY `idx_point_transactions_order` (`order_id`),
  KEY `idx_point_transactions_review` (`review_id`),
  CONSTRAINT `fk_point_transactions_customer`
    FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_point_transactions_order`
    FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_point_transactions_review`
    FOREIGN KEY (`review_id`) REFERENCES `reviews` (`review_id`),
  CONSTRAINT `chk_point_transactions_type`
    CHECK (`transaction_type` IN ('EARN','USE','EXPIRE','REVOKE','REFUND','ADJUST')),
  CONSTRAINT `chk_point_transactions_amount`
    CHECK (`point_amount` <> 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

ALTER TABLE `customers` DROP COLUMN `reward_points`;

UPDATE `branches`
SET `district_code` = 'SEOUL-SEONGDONG'
WHERE `branch_code` = 'SEL-SD';

INSERT INTO `branch_business_hours`
  (`branch_id`, `day_of_week`, `opens_at`, `closes_at`, `is_closed`)
SELECT b.`branch_id`, days.`day_of_week`,
       CASE WHEN days.`day_of_week` = 7 THEN NULL ELSE '10:30:00' END,
       CASE WHEN days.`day_of_week` = 7 THEN NULL ELSE '20:00:00' END,
       days.`day_of_week` = 7
FROM `branches` b
CROSS JOIN (
  SELECT 1 AS `day_of_week` UNION ALL SELECT 2 UNION ALL SELECT 3
  UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
) days
WHERE b.`branch_code` = 'SEL-SD';
