-- Confirmed return and pickup-retention policies for shupick_v2

USE `shupick_v2`;

CREATE TABLE `return_policies` (
  `return_policy_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `policy_name` VARCHAR(100) NOT NULL,
  `effective_from` DATE NOT NULL,
  `effective_to` DATE DEFAULT NULL,
  `standard_return_days` TINYINT UNSIGNED NOT NULL DEFAULT 7,
  `requires_unworn` BOOLEAN NOT NULL DEFAULT TRUE,
  `requires_no_customer_damage` BOOLEAN NOT NULL DEFAULT TRUE,
  `requires_components_complete` BOOLEAN NOT NULL DEFAULT TRUE,
  `requires_packaging_intact` BOOLEAN NOT NULL DEFAULT TRUE,
  `allows_defect_exception` BOOLEAN NOT NULL DEFAULT TRUE,
  `allows_wrong_item_exception` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`return_policy_id`),
  UNIQUE KEY `uq_return_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_return_policies_period`
    CHECK (`effective_to` IS NULL OR `effective_to` >= `effective_from`),
  CONSTRAINT `chk_return_policies_days`
    CHECK (`standard_return_days` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `return_policies`
  (`policy_name`, `effective_from`, `standard_return_days`)
VALUES
  ('수령 후 7일 반품 정책', '2026-10-02', 7);

ALTER TABLE `return_requests`
  ADD COLUMN `return_policy_id` BIGINT UNSIGNED DEFAULT NULL AFTER `customer_id`,
  ADD COLUMN `return_reason_code` VARCHAR(30) NOT NULL DEFAULT 'CUSTOMER_CHANGE' AFTER `handled_by_employee_id`,
  ADD COLUMN `return_deadline_at` DATETIME DEFAULT NULL AFTER `return_reason`,
  ADD KEY `idx_return_requests_policy` (`return_policy_id`),
  ADD CONSTRAINT `fk_return_requests_policy`
    FOREIGN KEY (`return_policy_id`) REFERENCES `return_policies` (`return_policy_id`),
  ADD CONSTRAINT `chk_return_requests_reason_code`
    CHECK (`return_reason_code` IN ('CUSTOMER_CHANGE','PRODUCT_DEFECT','WRONG_ITEM','OTHER'));

UPDATE `return_requests`
SET `return_policy_id` = (
  SELECT `return_policy_id`
  FROM `return_policies`
  WHERE `effective_from` = '2026-10-02'
);

CREATE TABLE `pickup_retention_policies` (
  `pickup_retention_policy_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `policy_name` VARCHAR(100) NOT NULL,
  `effective_from` DATE NOT NULL,
  `effective_to` DATE DEFAULT NULL,
  `holding_days` TINYINT UNSIGNED NOT NULL DEFAULT 14,
  `week_reminder_after_days` TINYINT UNSIGNED NOT NULL DEFAULT 7,
  `pre_recall_notice_before_days` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `recall_after_deadline_days` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`pickup_retention_policy_id`),
  UNIQUE KEY `uq_pickup_retention_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_pickup_retention_policies_period`
    CHECK (`effective_to` IS NULL OR `effective_to` >= `effective_from`),
  CONSTRAINT `chk_pickup_retention_policies_days`
    CHECK (
      `holding_days` > 0
      AND `week_reminder_after_days` < `holding_days`
      AND `pre_recall_notice_before_days` < `holding_days`
      AND `recall_after_deadline_days` > 0
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `pickup_retention_policies`
  (`policy_name`, `effective_from`, `holding_days`, `week_reminder_after_days`,
   `pre_recall_notice_before_days`, `recall_after_deadline_days`)
VALUES
  ('대리점 도착 후 14일 보관 정책', '2026-10-02', 14, 7, 0, 1);

ALTER TABLE `pickups`
  ADD COLUMN `pickup_retention_policy_id` BIGINT UNSIGNED DEFAULT NULL AFTER `order_id`,
  ADD KEY `idx_pickups_retention_policy` (`pickup_retention_policy_id`),
  ADD CONSTRAINT `fk_pickups_retention_policy`
    FOREIGN KEY (`pickup_retention_policy_id`)
    REFERENCES `pickup_retention_policies` (`pickup_retention_policy_id`);

UPDATE `pickups`
SET `pickup_retention_policy_id` = (
  SELECT `pickup_retention_policy_id`
  FROM `pickup_retention_policies`
  WHERE `effective_from` = '2026-10-02'
);
