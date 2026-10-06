-- Run after 007_status_histories.sql.
USE `shupick_v2`;

-- Expected: zero rows. Every current entity must have a matching latest history state.
SELECT o.`order_id`, o.`order_status`, h.`new_status` AS `history_status`
FROM `orders` o
LEFT JOIN `order_status_history` h
  ON h.`order_status_history_id` = (
    SELECT h2.`order_status_history_id`
    FROM `order_status_history` h2
    WHERE h2.`order_id` = o.`order_id`
    ORDER BY h2.`changed_at` DESC, h2.`order_status_history_id` DESC
    LIMIT 1
  )
WHERE h.`order_status_history_id` IS NULL OR h.`new_status` <> o.`order_status`;

SELECT f.`fulfillment_id`, f.`fulfillment_status`, h.`new_status` AS `history_status`
FROM `fulfillments` f
LEFT JOIN `fulfillment_status_history` h
  ON h.`fulfillment_status_history_id` = (
    SELECT h2.`fulfillment_status_history_id`
    FROM `fulfillment_status_history` h2
    WHERE h2.`fulfillment_id` = f.`fulfillment_id`
    ORDER BY h2.`changed_at` DESC, h2.`fulfillment_status_history_id` DESC
    LIMIT 1
  )
WHERE h.`fulfillment_status_history_id` IS NULL OR h.`new_status` <> f.`fulfillment_status`;

SELECT p.`pickup_id`, p.`pickup_status`, h.`new_status` AS `history_status`
FROM `pickups` p
LEFT JOIN `pickup_status_history` h
  ON h.`pickup_status_history_id` = (
    SELECT h2.`pickup_status_history_id`
    FROM `pickup_status_history` h2
    WHERE h2.`pickup_id` = p.`pickup_id`
    ORDER BY h2.`changed_at` DESC, h2.`pickup_status_history_id` DESC
    LIMIT 1
  )
WHERE h.`pickup_status_history_id` IS NULL OR h.`new_status` <> p.`pickup_status`;
