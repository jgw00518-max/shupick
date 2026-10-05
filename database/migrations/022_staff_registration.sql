-- Store staff email and selectable roles for self-service registration.
-- Apply once after migration 010 (employee Firebase UID and role tables).
USE `shupick_v2`;

INSERT IGNORE INTO `roles` (`role_code`, `role_name`)
VALUES ('BRANCH_MANAGER', '대리점장'), ('EXECUTIVE', '본사 임원');

ALTER TABLE `employees`
  ADD COLUMN `email` VARCHAR(255) NULL AFTER `firebase_uid`,
  ADD UNIQUE KEY `uq_employees_email` (`email`);
