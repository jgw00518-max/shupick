-- Remove the approval queue created by the earlier test-stage registration flow.
-- Check for outstanding requests before running this migration.
USE `shupick_v2`;

DROP TABLE IF EXISTS `employee_registration_requests`;
