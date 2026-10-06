-- Align staff tablet roles with the employee role catalog.
USE `shupick_v2`;

INSERT IGNORE INTO `roles` (`role_code`, `role_name`)
VALUES
  ('BRANCH_MANAGER', '대리점장'),
  ('EXECUTIVE', '본사 임원');
