-- Branch managers can perform the pickup tasks shown in their staff menu.
USE `shupick_v2`;

INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`role_id`, p.`permission_id`
FROM `roles` r CROSS JOIN `permissions` p
WHERE r.`role_code` = 'BRANCH_MANAGER'
  AND p.`permission_code` = 'PICKUP_MANAGE';
