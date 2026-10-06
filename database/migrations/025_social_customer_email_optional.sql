-- Forward-only social-login compatibility change. Never rerun the base schema.
-- Provider subject/Firebase UID is the identity; email is optional contact data.
-- Existing emails, customers, wallets, orders, and inquiries remain unchanged.
USE `shupick_v2`;
ALTER TABLE `customers` MODIFY COLUMN `email` VARCHAR(255) NULL;
