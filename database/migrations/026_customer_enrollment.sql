-- Separate verified recovery numbers from the legacy, unverified contact phone.
-- One customer per row; multiple independent accounts may own the same number.
-- Do not import existing customers.phone values as verified.
CREATE TABLE IF NOT EXISTS customer_enrollments (
  customer_id BIGINT UNSIGNED NOT NULL,
  verified_phone VARCHAR(20) NOT NULL,
  firebase_phone_uid VARCHAR(128) NOT NULL,
  phone_verified_at DATETIME(6) NOT NULL,
  phone_consent_at DATETIME(6) NOT NULL,
  birth_date_consent_at DATETIME(6) DEFAULT NULL,
  PRIMARY KEY (customer_id),
  KEY idx_enrollments_phone (verified_phone),
  CONSTRAINT fk_enrollments_customer FOREIGN KEY (customer_id)
    REFERENCES customers (customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
