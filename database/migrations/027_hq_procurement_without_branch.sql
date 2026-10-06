-- Headquarters replenishment requisitions no longer require a related branch.
-- Existing branch associations and foreign keys are preserved.
USE `shupick_v2`;
ALTER TABLE `purchase_requisitions`
  MODIFY COLUMN `branch_id` BIGINT UNSIGNED NULL DEFAULT NULL;
