-- Firebase Authentication owns customer credentials; MySQL stores only the business profile.
USE `shupick_v2`;

ALTER TABLE `customers`
  ADD COLUMN `firebase_uid` VARCHAR(128) DEFAULT NULL AFTER `customer_id`;

-- Existing development accounts receive a replaceable legacy identifier until first verified sync.
UPDATE `customers`
SET `firebase_uid` = CONCAT('legacy-customer-', `customer_id`)
WHERE `firebase_uid` IS NULL;

ALTER TABLE `customers`
  MODIFY COLUMN `firebase_uid` VARCHAR(128) NOT NULL,
  ADD UNIQUE KEY `uq_customers_firebase_uid` (`firebase_uid`),
  DROP COLUMN `password_hash`;
