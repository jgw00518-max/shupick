-- Track order-bound stock reservations between checkout and headquarters shipment.
USE `shupick_v2`;

ALTER TABLE `orders`
  ADD COLUMN `order_request_key` VARCHAR(100) DEFAULT NULL AFTER `order_number`,
  ADD UNIQUE KEY `uq_orders_request_key` (`order_request_key`);

CREATE TABLE `inventory_reservations` (
  `inventory_reservation_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `order_item_id` BIGINT UNSIGNED NOT NULL,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `reserved_quantity` INT UNSIGNED NOT NULL,
  `reservation_status` VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
  `expires_at` DATETIME NOT NULL,
  `consumed_at` DATETIME DEFAULT NULL,
  `released_at` DATETIME DEFAULT NULL,
  `release_reason` VARCHAR(255) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`inventory_reservation_id`),
  UNIQUE KEY `uq_inventory_reservations_order_item` (`order_item_id`),
  KEY `idx_inventory_reservations_order_status` (`order_id`, `reservation_status`),
  KEY `idx_inventory_reservations_variant_status` (`product_variant_id`, `reservation_status`),
  KEY `idx_inventory_reservations_expiry` (`reservation_status`, `expires_at`),
  CONSTRAINT `fk_inventory_reservations_order`
    FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_inventory_reservations_order_item_order`
    FOREIGN KEY (`order_item_id`, `order_id`)
    REFERENCES `order_items` (`order_item_id`, `order_id`),
  CONSTRAINT `fk_inventory_reservations_variant`
    FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_inventory_reservations_quantity` CHECK (`reserved_quantity` > 0),
  CONSTRAINT `chk_inventory_reservations_status`
    CHECK (`reservation_status` IN ('RESERVED','CONSUMED','RELEASED','EXPIRED')),
  CONSTRAINT `chk_inventory_reservations_consumed_at`
    CHECK (`reservation_status` <> 'CONSUMED' OR `consumed_at` IS NOT NULL),
  CONSTRAINT `chk_inventory_reservations_released_at`
    CHECK (`reservation_status` NOT IN ('RELEASED','EXPIRED') OR `released_at` IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
