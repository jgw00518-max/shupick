-- Run after 008_firebase_customer_identity.sql.
USE `shupick_v2`;

-- Expected: zero rows.
SELECT `customer_id`, `email`
FROM `customers`
WHERE `firebase_uid` IS NULL OR `firebase_uid` = '';

-- Expected: zero rows. MySQL must no longer store customer passwords.
SELECT `column_name`
FROM `information_schema`.`columns`
WHERE `table_schema` = 'shupick_v2'
  AND `table_name` = 'customers'
  AND `column_name` = 'password_hash';

-- Expected: one row for each customer and no duplicates.
SELECT `firebase_uid`, COUNT(*) AS `customer_count`
FROM `customers`
GROUP BY `firebase_uid`
HAVING COUNT(*) > 1;
