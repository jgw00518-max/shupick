USE `shupick_v2`;
CREATE TABLE IF NOT EXISTS customer_interaction_events (
  interaction_event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_key VARCHAR(100) NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  session_key VARCHAR(100) NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  event_type VARCHAR(30) NOT NULL,
  color_name VARCHAR(50) DEFAULT NULL,
  size_mm SMALLINT UNSIGNED DEFAULT NULL,
  quantity SMALLINT UNSIGNED DEFAULT NULL,
  occurred_at DATETIME(6) NOT NULL,
  received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (interaction_event_id),
  UNIQUE KEY uq_interaction_event_key (event_key),
  KEY idx_interactions_customer_session (customer_id,session_key,occurred_at,interaction_event_id),
  KEY idx_interactions_product_type (product_id,event_type,occurred_at),
  CONSTRAINT fk_interactions_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  CONSTRAINT fk_interactions_product FOREIGN KEY (product_id) REFERENCES products(product_id),
  CONSTRAINT chk_interactions_type CHECK (event_type IN ('VIEW','WISH_ADD','WISH_REMOVE','CART_ADD','CART_REMOVE','CART_QUANTITY','CART_OPTION'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
