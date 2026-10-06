-- Run after 010_employee_rbac_and_procurement_approvals.sql.
USE `shupick_v2`;

-- Expected: two ordered steps.
SELECT w.`workflow_code`, s.`step_order`, s.`step_name`, r.`role_code`
FROM `approval_workflow_steps` s
JOIN `approval_workflows` w ON w.`approval_workflow_id`=s.`approval_workflow_id`
JOIN `roles` r ON r.`role_id`=s.`required_role_id`
WHERE w.`workflow_code`='PROCUREMENT_STANDARD'
ORDER BY s.`step_order`;

-- Expected: zero rows. MySQL must not retain employee passwords.
SELECT `column_name`
FROM `information_schema`.`columns`
WHERE `table_schema`='shupick_v2' AND `table_name`='employees' AND `column_name`='password_hash';

-- Expected: zero rows. Decided approvals require the correct role.
SELECT pa.`purchase_approval_id`, pa.`approver_employee_id`, r.`role_code`
FROM `purchase_approvals` pa
JOIN `roles` r ON r.`role_id`=pa.`required_role_id`
LEFT JOIN `employee_roles` er
  ON er.`employee_id`=pa.`approver_employee_id` AND er.`role_id`=pa.`required_role_id`
WHERE pa.`approval_status` IN ('APPROVED','REJECTED') AND er.`employee_id` IS NULL;
