-- Run after 003_refunds.sql.
USE `shupick_v2`;

-- Expected: two rows.
SELECT `table_name`
FROM `information_schema`.`tables`
WHERE `table_schema` = 'shupick_v2'
  AND `table_name` IN ('refunds', 'refund_items')
ORDER BY `table_name`;

-- Expected: zero rows. Financial refund fields must not remain on return_requests/payments.
SELECT `table_name`, `column_name`
FROM `information_schema`.`columns`
WHERE `table_schema` = 'shupick_v2'
  AND (
    (`table_name` = 'return_requests' AND `column_name` IN ('refund_amount', 'refunded_at'))
    OR (`table_name` = 'payments' AND `column_name` = 'refunded_at')
  );

-- Expected: zero rows. Successful refunds cannot exceed the original payment.
SELECT
  r.`payment_id`,
  p.`payment_amount`,
  SUM(r.`refund_amount`) AS `succeeded_refund_amount`
FROM `refunds` r
JOIN `payments` p ON p.`payment_id` = r.`payment_id`
WHERE r.`refund_status` = 'SUCCEEDED'
GROUP BY r.`payment_id`, p.`payment_amount`
HAVING SUM(r.`refund_amount`) > p.`payment_amount`;

-- Expected: zero rows. Refund item allocation must match its parent refund amount.
SELECT
  r.`refund_id`,
  r.`refund_amount`,
  COALESCE(SUM(ri.`refund_amount`), 0) AS `item_refund_amount`
FROM `refunds` r
LEFT JOIN `refund_items` ri ON ri.`refund_id` = r.`refund_id`
WHERE r.`refund_type` = 'RETURN'
GROUP BY r.`refund_id`, r.`refund_amount`
HAVING COALESCE(SUM(ri.`refund_amount`), 0) <> r.`refund_amount`;
