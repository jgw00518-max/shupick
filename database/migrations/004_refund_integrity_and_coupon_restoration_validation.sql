-- Run after 004_refund_integrity_and_coupon_restoration.sql.
USE `shupick_v2`;

-- Expected: two composite foreign keys that keep refund rows on one order.
SELECT `constraint_name`, `table_name`
FROM `information_schema`.`referential_constraints`
WHERE `constraint_schema` = 'shupick_v2'
  AND `constraint_name` IN (
    'fk_refunds_payment_order',
    'fk_refund_items_order_item_order'
  )
ORDER BY `constraint_name`;

-- Expected: one active policy with full cancellation enabled and partial return disabled.
SELECT
  `policy_name`, `restore_on_full_cancel`, `restore_on_partial_return`,
  `require_unexpired_coupon`
FROM `coupon_refund_policies`
WHERE `effective_from` <= CURRENT_DATE
  AND (`effective_to` IS NULL OR `effective_to` >= CURRENT_DATE)
ORDER BY `effective_from` DESC
LIMIT 1;

-- Expected: zero rows. Refund and item orders must agree.
SELECT ri.*
FROM `refund_items` ri
JOIN `refunds` r ON r.`refund_id` = ri.`refund_id`
JOIN `order_items` oi ON oi.`order_item_id` = ri.`order_item_id`
WHERE ri.`order_id` <> r.`order_id`
   OR ri.`order_id` <> oi.`order_id`;

-- Expected: zero rows. Successful refunds must not exceed their payment.
SELECT r.`payment_id`, p.`payment_amount`, SUM(r.`refund_amount`) AS `refunded_amount`
FROM `refunds` r
JOIN `payments` p ON p.`payment_id` = r.`payment_id`
WHERE r.`refund_status` = 'SUCCEEDED'
GROUP BY r.`payment_id`, p.`payment_amount`
HAVING SUM(r.`refund_amount`) > p.`payment_amount`;
