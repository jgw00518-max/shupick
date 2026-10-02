USE `shupick_v2`;
CREATE TABLE IF NOT EXISTS restock_subscriptions (
  customer_id BIGINT UNSIGNED NOT NULL,
  product_variant_id BIGINT UNSIGNED NOT NULL,
  subscribed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (customer_id,product_variant_id),
  CONSTRAINT fk_restock_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  CONSTRAINT fk_restock_variant FOREIGN KEY (product_variant_id) REFERENCES product_variants(product_variant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT IGNORE INTO permissions (permission_code,permission_name) VALUES ('SUPPORT_MANAGE','고객 문의 답변');
INSERT IGNORE INTO role_permissions (role_id,permission_id)
SELECT r.role_id,p.permission_id FROM roles r JOIN permissions p ON p.permission_code='SUPPORT_MANAGE'
WHERE r.role_code IN ('ADMIN','HQ_STAFF');
