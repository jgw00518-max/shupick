USE `shupick_v2`;
CREATE TABLE IF NOT EXISTS review_photo_payloads (
  review_id BIGINT UNSIGNED NOT NULL,
  sort_order SMALLINT UNSIGNED NOT NULL,
  photo_base64 LONGTEXT NOT NULL,
  PRIMARY KEY (review_id,sort_order),
  CONSTRAINT fk_review_photo_payloads_review FOREIGN KEY (review_id) REFERENCES reviews(review_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
