USE `shupick_v2`;
INSERT IGNORE INTO permissions (permission_code,permission_name) VALUES ('PICKUP_MANAGE','대리점 도착 및 수령 처리');
INSERT IGNORE INTO role_permissions (role_id,permission_id)
SELECT r.role_id,p.permission_id FROM roles r JOIN permissions p ON p.permission_code='PICKUP_MANAGE'
WHERE r.role_code IN ('ADMIN','BRANCH_STAFF','HQ_STAFF');
