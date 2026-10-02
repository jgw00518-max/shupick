USE `shupick_v2`;
INSERT IGNORE INTO permissions (permission_code,permission_name)
VALUES ('REFUND_MANAGE','반품 검수 및 환불 처리');
INSERT IGNORE INTO role_permissions (role_id,permission_id)
SELECT r.role_id,p.permission_id FROM roles r JOIN permissions p
ON p.permission_code='REFUND_MANAGE' WHERE r.role_code IN ('ADMIN','HQ_STAFF');
