-- Shupick v2 relationship and transaction checks
-- Run after shupick_v2_seed.sql.

USE `shupick_v2`;

-- Expected: 28
SELECT COUNT(*) AS `table_count`
FROM `information_schema`.`tables`
WHERE `table_schema` = 'shupick_v2'
  AND `table_type` = 'BASE TABLE';

-- Expected: two rows, each with stock_quantity 20.
SELECT
  p.`product_name`, v.`product_code`, v.`color_name`, v.`size_mm`,
  b.`branch_name`, s.`stock_quantity`, s.`reserved_quantity`, s.`inventory_status`
FROM `stocks` s
JOIN `branches` b ON b.`branch_id` = s.`branch_id`
JOIN `product_variants` v ON v.`product_variant_id` = s.`product_variant_id`
JOIN `products` p ON p.`product_id` = v.`product_id`
ORDER BY v.`size_mm`;

-- Expected: one completed pickup order and the calculated line total 129000.
SELECT
  o.`order_number`, o.`order_status`, o.`fulfillment_type`,
  oi.`product_code`, oi.`color_name`, oi.`size_mm`, oi.`quantity`, oi.`line_total`,
  pay.`payment_status`, pu.`pickup_status`
FROM `orders` o
JOIN `order_items` oi ON oi.`order_id` = o.`order_id`
JOIN `payments` pay ON pay.`order_id` = o.`order_id`
JOIN `pickups` pu ON pu.`order_id` = o.`order_id`
WHERE o.`order_number` = 'ORD-TEST-0001';

-- Expected: one review connected to the same customer who placed the order.
SELECT
  o.`order_number`, c.`email`, oi.`product_code`, r.`rating`, r.`review_content`
FROM `reviews` r
JOIN `order_items` oi ON oi.`order_item_id` = r.`order_item_id`
JOIN `orders` o ON o.`order_id` = oi.`order_id` AND o.`customer_id` = r.`customer_id`
JOIN `customers` c ON c.`customer_id` = r.`customer_id`;

-- Expected: zero rows for every integrity problem query.
SELECT * FROM `stocks` WHERE `reserved_quantity` > `stock_quantity`;
SELECT * FROM `orders`
WHERE `paid_total` + `coupon_discount` + `points_used` <> `subtotal_amount`;
SELECT r.*
FROM `reviews` r
JOIN `order_items` oi ON oi.`order_item_id` = r.`order_item_id`
JOIN `orders` o ON o.`order_id` = oi.`order_id`
WHERE r.`customer_id` <> o.`customer_id`;

-- Safe stock-decrement simulation. The rollback restores the original quantity.
START TRANSACTION;

SELECT s.`stock_quantity`
FROM `stocks` s
JOIN `product_variants` v ON v.`product_variant_id` = s.`product_variant_id`
JOIN `branches` b ON b.`branch_id` = s.`branch_id`
WHERE v.`product_code` = 'NK-M-SN-0001-BLK-250'
  AND b.`branch_code` = 'SEL-SD'
FOR UPDATE;

UPDATE `stocks` s
JOIN `product_variants` v ON v.`product_variant_id` = s.`product_variant_id`
JOIN `branches` b ON b.`branch_id` = s.`branch_id`
SET s.`stock_quantity` = s.`stock_quantity` - 1
WHERE v.`product_code` = 'NK-M-SN-0001-BLK-250'
  AND b.`branch_code` = 'SEL-SD'
  AND s.`stock_quantity` - s.`reserved_quantity` >= 1;

SELECT ROW_COUNT() AS `updated_stock_rows`; -- Expected: 1
ROLLBACK;
