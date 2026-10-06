-- Run after 005_headquarters_inventory_and_pickup_holdings.sql.
USE `shupick_v2`;

-- Expected: no legacy stocks table.
SELECT `table_name`
FROM `information_schema`.`tables`
WHERE `table_schema` = 'shupick_v2' AND `table_name` = 'stocks';

-- Expected: HQ quantities are valid and available quantity is calculated correctly.
SELECT
  v.`product_code`, hi.`on_hand_quantity`, hi.`reserved_quantity`,
  hi.`defective_quantity`, hi.`available_quantity`
FROM `headquarters_inventory` hi
JOIN `product_variants` v ON v.`product_variant_id` = hi.`product_variant_id`
ORDER BY v.`product_code`;

-- Expected: zero rows.
SELECT *
FROM `headquarters_inventory`
WHERE `available_quantity` < 0
   OR `reserved_quantity` + `defective_quantity` > `on_hand_quantity`;

-- Existing pickup orders must have fulfillment items and branch holdings.
SELECT
  o.`order_number`, f.`fulfillment_status`, ph.`holding_status`,
  v.`product_code`, fi.`quantity`, b.`branch_code`
FROM `fulfillments` f
JOIN `orders` o ON o.`order_id` = f.`order_id`
JOIN `fulfillment_items` fi ON fi.`fulfillment_id` = f.`fulfillment_id`
JOIN `order_items` oi ON oi.`order_item_id` = fi.`order_item_id`
JOIN `product_variants` v ON v.`product_variant_id` = oi.`product_variant_id`
JOIN `pickup_holdings` ph ON ph.`fulfillment_item_id` = fi.`fulfillment_item_id`
JOIN `branches` b ON b.`branch_id` = ph.`branch_id`
ORDER BY o.`order_number`, fi.`fulfillment_item_id`;

-- Expected: zero rows. A fulfillment item cannot belong to another order.
SELECT fi.*
FROM `fulfillment_items` fi
JOIN `fulfillments` f ON f.`fulfillment_id` = fi.`fulfillment_id`
JOIN `order_items` oi ON oi.`order_item_id` = fi.`order_item_id`
WHERE fi.`order_id` <> f.`order_id` OR fi.`order_id` <> oi.`order_id`;
