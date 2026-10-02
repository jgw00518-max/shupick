-- Run after 009_firebase_outbox.sql.
USE `shupick_v2`;

-- Expected: zero rows. Every current aggregate needs at least one outbox event.
SELECT 'ORDER' AS `missing_type`, o.`order_id` AS `missing_id`
FROM `orders` o
LEFT JOIN `outbox_events` e
  ON e.`aggregate_type`='ORDER' AND e.`aggregate_id`=o.`order_id`
WHERE e.`outbox_event_id` IS NULL
UNION ALL
SELECT 'FULFILLMENT', f.`fulfillment_id`
FROM `fulfillments` f
LEFT JOIN `outbox_events` e
  ON e.`aggregate_type`='FULFILLMENT' AND e.`aggregate_id`=f.`fulfillment_id`
WHERE e.`outbox_event_id` IS NULL
UNION ALL
SELECT 'PICKUP', p.`pickup_id`
FROM `pickups` p
LEFT JOIN `outbox_events` e
  ON e.`aggregate_type`='PICKUP' AND e.`aggregate_id`=p.`pickup_id`
WHERE e.`outbox_event_id` IS NULL
UNION ALL
SELECT 'INVENTORY', hi.`product_variant_id`
FROM `headquarters_inventory` hi
LEFT JOIN `outbox_events` e
  ON e.`aggregate_type`='INVENTORY' AND e.`aggregate_id`=hi.`product_variant_id`
WHERE e.`outbox_event_id` IS NULL;

-- Expected: zero rows.
SELECT * FROM `outbox_events`
WHERE (`event_status`='PUBLISHED' AND `published_at` IS NULL)
   OR (`event_status`<>'PUBLISHED' AND `published_at` IS NOT NULL);
