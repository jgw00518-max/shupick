-- Employee Firebase identity, role permissions, ordered procurement approval, and audit logs.
USE `shupick_v2`;

ALTER TABLE `employees`
  ADD COLUMN `firebase_uid` VARCHAR(128) DEFAULT NULL AFTER `employee_id`;

UPDATE `employees`
SET `firebase_uid` = CONCAT('legacy-employee-', `employee_id`)
WHERE `firebase_uid` IS NULL;

ALTER TABLE `employees`
  MODIFY COLUMN `firebase_uid` VARCHAR(128) NOT NULL,
  ADD UNIQUE KEY `uq_employees_firebase_uid` (`firebase_uid`),
  DROP COLUMN `password_hash`;

CREATE TABLE `roles` (
  `role_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `role_code` VARCHAR(50) NOT NULL,
  `role_name` VARCHAR(100) NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`role_id`),
  UNIQUE KEY `uq_roles_code` (`role_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `permissions` (
  `permission_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `permission_code` VARCHAR(80) NOT NULL,
  `permission_name` VARCHAR(120) NOT NULL,
  PRIMARY KEY (`permission_id`),
  UNIQUE KEY `uq_permissions_code` (`permission_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `role_permissions` (
  `role_id` BIGINT UNSIGNED NOT NULL,
  `permission_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`role_id`, `permission_id`),
  CONSTRAINT `fk_role_permissions_role`
    FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_role_permissions_permission`
    FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`permission_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `employee_roles` (
  `employee_id` BIGINT UNSIGNED NOT NULL,
  `role_id` BIGINT UNSIGNED NOT NULL,
  `assigned_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `assigned_by_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  PRIMARY KEY (`employee_id`, `role_id`),
  KEY `idx_employee_roles_role` (`role_id`),
  KEY `idx_employee_roles_assigner` (`assigned_by_employee_id`),
  CONSTRAINT `fk_employee_roles_employee`
    FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_employee_roles_role`
    FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_employee_roles_assigner`
    FOREIGN KEY (`assigned_by_employee_id`) REFERENCES `employees` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `roles` (`role_code`, `role_name`) VALUES
  ('BRANCH_STAFF', '대리점 직원'),
  ('HQ_STAFF', '본사 직원'),
  ('TEAM_LEAD', '팀장'),
  ('DIRECTOR', '이사'),
  ('ADMIN', '시스템 관리자');

INSERT INTO `permissions` (`permission_code`, `permission_name`) VALUES
  ('PROCUREMENT_REQUISITION_CREATE', '발주 품의 작성'),
  ('PROCUREMENT_REQUISITION_SUBMIT', '발주 품의 상신'),
  ('PROCUREMENT_APPROVE_TEAM_LEAD', '팀장 발주 승인'),
  ('PROCUREMENT_APPROVE_DIRECTOR', '이사 발주 승인'),
  ('PROCUREMENT_ORDER_CREATE', '제조사 발주 생성'),
  ('INVENTORY_SHIP', '본사 출고 처리'),
  ('AUDIT_LOG_READ', '감사 로그 조회'),
  ('ROLE_MANAGE', '직원 역할 관리');

INSERT INTO `role_permissions` (`role_id`, `permission_id`)
SELECT r.`role_id`, p.`permission_id`
FROM `roles` r
JOIN `permissions` p ON
  (r.`role_code`='BRANCH_STAFF' AND p.`permission_code` IN (
    'PROCUREMENT_REQUISITION_CREATE','PROCUREMENT_REQUISITION_SUBMIT'
  ))
  OR (r.`role_code`='HQ_STAFF' AND p.`permission_code` IN (
    'PROCUREMENT_REQUISITION_CREATE','PROCUREMENT_REQUISITION_SUBMIT','PROCUREMENT_ORDER_CREATE','INVENTORY_SHIP'
  ))
  OR (r.`role_code`='TEAM_LEAD' AND p.`permission_code`='PROCUREMENT_APPROVE_TEAM_LEAD')
  OR (r.`role_code`='DIRECTOR' AND p.`permission_code` IN (
    'PROCUREMENT_APPROVE_DIRECTOR','AUDIT_LOG_READ'
  ))
  OR r.`role_code`='ADMIN';

INSERT INTO `employee_roles` (`employee_id`, `role_id`)
SELECT e.`employee_id`, r.`role_id`
FROM `employees` e
JOIN `roles` r ON
  (e.`employee_code`='EMP-0001' AND r.`role_code`='BRANCH_STAFF')
  OR (e.`employee_code`='EMP-0002' AND r.`role_code` IN ('HQ_STAFF','TEAM_LEAD'));

CREATE TABLE `approval_workflows` (
  `approval_workflow_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `workflow_code` VARCHAR(50) NOT NULL,
  `workflow_name` VARCHAR(100) NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`approval_workflow_id`),
  UNIQUE KEY `uq_approval_workflows_code` (`workflow_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `approval_workflow_steps` (
  `approval_workflow_step_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `approval_workflow_id` BIGINT UNSIGNED NOT NULL,
  `step_order` TINYINT UNSIGNED NOT NULL,
  `step_name` VARCHAR(100) NOT NULL,
  `required_role_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`approval_workflow_step_id`),
  UNIQUE KEY `uq_approval_workflow_steps_order` (`approval_workflow_id`, `step_order`),
  KEY `idx_approval_workflow_steps_role` (`required_role_id`),
  CONSTRAINT `fk_approval_workflow_steps_workflow`
    FOREIGN KEY (`approval_workflow_id`) REFERENCES `approval_workflows` (`approval_workflow_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_approval_workflow_steps_role`
    FOREIGN KEY (`required_role_id`) REFERENCES `roles` (`role_id`),
  CONSTRAINT `chk_approval_workflow_steps_order` CHECK (`step_order` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `approval_workflows` (`workflow_code`, `workflow_name`)
VALUES ('PROCUREMENT_STANDARD', '팀장 승인 후 이사 승인');

INSERT INTO `approval_workflow_steps`
  (`approval_workflow_id`, `step_order`, `step_name`, `required_role_id`)
SELECT w.`approval_workflow_id`, steps.`step_order`, steps.`step_name`, r.`role_id`
FROM `approval_workflows` w
CROSS JOIN (
  SELECT 1 AS `step_order`, '팀장 승인' AS `step_name`, 'TEAM_LEAD' AS `role_code`
  UNION ALL
  SELECT 2, '이사 승인', 'DIRECTOR'
) steps
JOIN `roles` r ON r.`role_code`=steps.`role_code`
WHERE w.`workflow_code`='PROCUREMENT_STANDARD';

ALTER TABLE `purchase_requisitions` DROP CHECK `chk_requisitions_status`;
ALTER TABLE `purchase_requisitions`
  ADD COLUMN `approval_workflow_id` BIGINT UNSIGNED DEFAULT NULL AFTER `branch_id`,
  ADD KEY `idx_requisitions_workflow` (`approval_workflow_id`),
  ADD CONSTRAINT `fk_requisitions_workflow`
    FOREIGN KEY (`approval_workflow_id`) REFERENCES `approval_workflows` (`approval_workflow_id`),
  ADD CONSTRAINT `chk_requisitions_status`
    CHECK (`requisition_status` IN (
      'DRAFT','SUBMITTED','PENDING_TEAM_LEAD','PENDING_DIRECTOR',
      'APPROVED','REJECTED','ORDERED','CANCELED'
    ));

UPDATE `purchase_requisitions`
SET `approval_workflow_id` = (
  SELECT `approval_workflow_id` FROM `approval_workflows`
  WHERE `workflow_code`='PROCUREMENT_STANDARD'
);

ALTER TABLE `purchase_requisitions`
  MODIFY COLUMN `approval_workflow_id` BIGINT UNSIGNED NOT NULL;

ALTER TABLE `purchase_approvals` DROP CHECK `chk_approvals_status`;
ALTER TABLE `purchase_approvals`
  DROP INDEX `uq_approvals_requisition_employee`,
  MODIFY COLUMN `approver_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  MODIFY COLUMN `decided_at` DATETIME DEFAULT NULL,
  ADD COLUMN `approval_sequence` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `purchase_requisition_id`,
  ADD COLUMN `required_role_id` BIGINT UNSIGNED DEFAULT NULL AFTER `approval_sequence`,
  ADD UNIQUE KEY `uq_purchase_approvals_requisition_sequence`
    (`purchase_requisition_id`, `approval_sequence`),
  ADD KEY `idx_purchase_approvals_required_role` (`required_role_id`),
  ADD CONSTRAINT `fk_purchase_approvals_required_role`
    FOREIGN KEY (`required_role_id`) REFERENCES `roles` (`role_id`),
  ADD CONSTRAINT `chk_approvals_status`
    CHECK (`approval_status` IN ('PENDING','APPROVED','REJECTED','WAIVED')),
  ADD CONSTRAINT `chk_approvals_decision_fields`
    CHECK (
      (`approval_status`='PENDING' AND `approver_employee_id` IS NULL AND `decided_at` IS NULL)
      OR (`approval_status` IN ('APPROVED','REJECTED') AND `approver_employee_id` IS NOT NULL AND `decided_at` IS NOT NULL)
      OR (`approval_status`='WAIVED' AND `decided_at` IS NOT NULL)
    );

UPDATE `purchase_approvals`
SET `required_role_id`=(SELECT `role_id` FROM `roles` WHERE `role_code`='TEAM_LEAD')
WHERE `approval_sequence`=1;

INSERT INTO `purchase_approvals`
  (`purchase_requisition_id`, `approval_sequence`, `required_role_id`,
   `approver_employee_id`, `approval_status`, `approval_comment`, `decided_at`)
SELECT
  pr.`purchase_requisition_id`, 2, r.`role_id`, NULL, 'WAIVED',
  '기존 승인 완료 데이터 마이그레이션', COALESCE(pr.`submitted_at`, pr.`created_at`)
FROM `purchase_requisitions` pr
JOIN `roles` r ON r.`role_code`='DIRECTOR'
WHERE pr.`requisition_status` IN ('APPROVED','ORDERED')
  AND NOT EXISTS (
    SELECT 1 FROM `purchase_approvals` pa
    WHERE pa.`purchase_requisition_id`=pr.`purchase_requisition_id`
      AND pa.`approval_sequence`=2
  );

ALTER TABLE `purchase_approvals`
  DROP FOREIGN KEY `fk_purchase_approvals_required_role`,
  MODIFY COLUMN `required_role_id` BIGINT UNSIGNED NOT NULL;

ALTER TABLE `purchase_approvals`
  ADD CONSTRAINT `fk_purchase_approvals_required_role`
    FOREIGN KEY (`required_role_id`) REFERENCES `roles` (`role_id`);

CREATE TABLE `audit_logs` (
  `audit_log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_type` VARCHAR(20) NOT NULL,
  `actor_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `actor_customer_id` BIGINT UNSIGNED DEFAULT NULL,
  `action_code` VARCHAR(80) NOT NULL,
  `entity_type` VARCHAR(50) NOT NULL,
  `entity_id` BIGINT UNSIGNED NOT NULL,
  `before_data` JSON DEFAULT NULL,
  `after_data` JSON DEFAULT NULL,
  `request_id` VARCHAR(100) DEFAULT NULL,
  `ip_address` VARCHAR(45) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`audit_log_id`),
  KEY `idx_audit_logs_entity_time` (`entity_type`, `entity_id`, `created_at`),
  KEY `idx_audit_logs_employee_time` (`actor_employee_id`, `created_at`),
  KEY `idx_audit_logs_customer_time` (`actor_customer_id`, `created_at`),
  CONSTRAINT `fk_audit_logs_employee`
    FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_audit_logs_customer`
    FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `chk_audit_logs_actor`
    CHECK (
      (`actor_type`='SYSTEM' AND `actor_employee_id` IS NULL AND `actor_customer_id` IS NULL)
      OR (`actor_type`='EMPLOYEE' AND `actor_employee_id` IS NOT NULL AND `actor_customer_id` IS NULL)
      OR (`actor_type`='CUSTOMER' AND `actor_employee_id` IS NULL AND `actor_customer_id` IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
