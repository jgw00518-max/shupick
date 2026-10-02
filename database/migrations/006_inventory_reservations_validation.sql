-- Run after 006_inventory_reservations.sql.
USE `shupick_v2`;

-- Expected: zero rows. Active reservations must match the HQ aggregate.
SELECT
  hi.`product_variant_id`, hi.`reserved_quantity`,
  COALESCE(SUM(ir.`reserved_quantity`), 0) AS `reservation_rows_quantity`
FROM `headquarters_inventory` hi
LEFT JOIN `inventory_reservations` ir
  ON ir.`product_variant_id` = hi.`product_variant_id`
 AND ir.`reservation_status` = 'RESERVED'
GROUP BY hi.`product_variant_id`, hi.`reserved_quantity`
HAVING hi.`reserved_quantity` <> COALESCE(SUM(ir.`reserved_quantity`), 0);

-- Expected: zero rows. Reserved quantities cannot exceed HQ on-hand stock.
SELECT * FROM `headquarters_inventory`
WHERE `reserved_quantity` + `defective_quantity` > `on_hand_quantity`;

-- Expected: zero rows. Reservation/order-item variant and order must agree.
SELECT ir.*
FROM `inventory_reservations` ir
JOIN `order_items` oi ON oi.`order_item_id` = ir.`order_item_id`
WHERE ir.`order_id` <> oi.`order_id`
   OR ir.`product_variant_id` <> oi.`product_variant_id`;
