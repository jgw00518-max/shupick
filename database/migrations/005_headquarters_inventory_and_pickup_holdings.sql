-- Split sellable headquarters inventory from customer-owned goods held at branches.
USE `shupick_v2`;

CREATE TABLE `headquarters_inventory` (
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `on_hand_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `reserved_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `defective_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `available_quantity` INT GENERATED ALWAYS AS
    (`on_hand_quantity` - `reserved_quantity` - `defective_quantity`) STORED,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_variant_id`),
  CONSTRAINT `fk_headquarters_inventory_variant`
    FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_headquarters_inventory_quantities`
    CHECK (`reserved_quantity` + `defective_quantity` <= `on_hand_quantity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Existing branch stock was previously used as sellable stock, so preserve its totals as HQ opening balances.
INSERT INTO `headquarters_inventory`
  (`product_variant_id`, `on_hand_quantity`, `reserved_quantity`, `defective_quantity`)
SELECT
  `product_variant_id`,
  SUM(`stock_quantity`),
  SUM(`reserved_quantity`),
  SUM(CASE WHEN `inventory_status` = 'DEFECTIVE' THEN `stock_quantity` ELSE 0 END)
FROM `stocks`
GROUP BY `product_variant_id`;

INSERT INTO `headquarters_inventory` (`product_variant_id`)
SELECT v.`product_variant_id`
FROM `product_variants` v
LEFT JOIN `headquarters_inventory` hi
  ON hi.`product_variant_id` = v.`product_variant_id`
WHERE hi.`product_variant_id` IS NULL;

CREATE TABLE `inventory_movements` (
  `inventory_movement_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `movement_type` VARCHAR(30) NOT NULL,
  `on_hand_delta` INT NOT NULL DEFAULT 0,
  `reserved_delta` INT NOT NULL DEFAULT 0,
  `defective_delta` INT NOT NULL DEFAULT 0,
  `on_hand_after` INT UNSIGNED NOT NULL,
  `reserved_after` INT UNSIGNED NOT NULL,
  `defective_after` INT UNSIGNED NOT NULL,
  `reference_type` VARCHAR(30) DEFAULT NULL,
  `reference_id` BIGINT UNSIGNED DEFAULT NULL,
  `idempotency_key` VARCHAR(100) NOT NULL,
  `reason` VARCHAR(255) DEFAULT NULL,
  `created_by_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inventory_movement_id`),
  UNIQUE KEY `uq_inventory_movements_idempotency` (`idempotency_key`),
  KEY `idx_inventory_movements_variant_time` (`product_variant_id`, `created_at`),
  KEY `idx_inventory_movements_reference` (`reference_type`, `reference_id`),
  KEY `idx_inventory_movements_employee` (`created_by_employee_id`),
  CONSTRAINT `fk_inventory_movements_variant`
    FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `fk_inventory_movements_employee`
    FOREIGN KEY (`created_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_inventory_movements_delta`
    CHECK (`on_hand_delta` <> 0 OR `reserved_delta` <> 0 OR `defective_delta` <> 0),
  CONSTRAINT `chk_inventory_movements_after`
    CHECK (`reserved_after` + `defective_after` <= `on_hand_after`),
  CONSTRAINT `chk_inventory_movements_reference`
    CHECK (
      (`reference_type` IS NULL AND `reference_id` IS NULL)
      OR (`reference_type` IS NOT NULL AND `reference_id` IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `inventory_movements`
  (`product_variant_id`, `movement_type`, `on_hand_delta`,
   `on_hand_after`, `reserved_after`, `defective_after`,
   `idempotency_key`, `reason`)
SELECT
  hi.`product_variant_id`, 'INITIAL_BALANCE', hi.`on_hand_quantity`,
  hi.`on_hand_quantity`, hi.`reserved_quantity`, hi.`defective_quantity`,
  CONCAT('hq-opening-balance-', hi.`product_variant_id`),
  '기존 재고를 본사 판매 가능 재고로 이전'
FROM `headquarters_inventory` hi
WHERE hi.`on_hand_quantity` > 0
   OR hi.`reserved_quantity` > 0
   OR hi.`defective_quantity` > 0;

CREATE TABLE `fulfillments` (
  `fulfillment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `fulfillment_number` VARCHAR(32) NOT NULL,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `destination_branch_id` BIGINT UNSIGNED NOT NULL,
  `fulfillment_status` VARCHAR(30) NOT NULL DEFAULT 'PREPARING',
  `tracking_number` VARCHAR(100) DEFAULT NULL,
  `shipped_at` DATETIME DEFAULT NULL,
  `arrived_at` DATETIME DEFAULT NULL,
  `inspected_at` DATETIME DEFAULT NULL,
  `completed_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`fulfillment_id`),
  UNIQUE KEY `uq_fulfillments_number` (`fulfillment_number`),
  UNIQUE KEY `uq_fulfillments_tracking` (`tracking_number`),
  UNIQUE KEY `uq_fulfillments_id_order` (`fulfillment_id`, `order_id`),
  KEY `idx_fulfillments_order` (`order_id`),
  KEY `idx_fulfillments_branch_status` (`destination_branch_id`, `fulfillment_status`),
  CONSTRAINT `fk_fulfillments_order`
    FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_fulfillments_branch`
    FOREIGN KEY (`destination_branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_fulfillments_status`
    CHECK (`fulfillment_status` IN (
      'PREPARING','IN_TRANSIT','ARRIVED','INSPECTING','READY_FOR_PICKUP',
      'RECALLING','RETURNED_TO_HQ','COMPLETED','CANCELED'
    ))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `fulfillment_items` (
  `fulfillment_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `fulfillment_id` BIGINT UNSIGNED NOT NULL,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `order_item_id` BIGINT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`fulfillment_item_id`),
  UNIQUE KEY `uq_fulfillment_items_order_item` (`fulfillment_id`, `order_item_id`),
  UNIQUE KEY `uq_fulfillment_items_id_order` (`fulfillment_item_id`, `order_id`),
  KEY `idx_fulfillment_items_order_item_order` (`order_item_id`, `order_id`),
  CONSTRAINT `fk_fulfillment_items_fulfillment_order`
    FOREIGN KEY (`fulfillment_id`, `order_id`)
    REFERENCES `fulfillments` (`fulfillment_id`, `order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_fulfillment_items_order_item_order`
    FOREIGN KEY (`order_item_id`, `order_id`)
    REFERENCES `order_items` (`order_item_id`, `order_id`),
  CONSTRAINT `chk_fulfillment_items_quantity` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `pickup_holdings` (
  `pickup_holding_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `fulfillment_item_id` BIGINT UNSIGNED NOT NULL,
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `holding_status` VARCHAR(30) NOT NULL DEFAULT 'AWAITING_ARRIVAL',
  `quantity` INT UNSIGNED NOT NULL,
  `received_at` DATETIME DEFAULT NULL,
  `ready_at` DATETIME DEFAULT NULL,
  `picked_up_at` DATETIME DEFAULT NULL,
  `recalled_at` DATETIME DEFAULT NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`pickup_holding_id`),
  UNIQUE KEY `uq_pickup_holdings_fulfillment_item` (`fulfillment_item_id`),
  KEY `idx_pickup_holdings_branch_status` (`branch_id`, `holding_status`),
  CONSTRAINT `fk_pickup_holdings_fulfillment_item`
    FOREIGN KEY (`fulfillment_item_id`) REFERENCES `fulfillment_items` (`fulfillment_item_id`),
  CONSTRAINT `fk_pickup_holdings_branch`
    FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_pickup_holdings_status`
    CHECK (`holding_status` IN (
      'AWAITING_ARRIVAL','INSPECTING','READY_FOR_PICKUP','PICKED_UP',
      'RECALLING','RETURNED_TO_HQ','DAMAGED','CANCELED'
    )),
  CONSTRAINT `chk_pickup_holdings_quantity` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Convert existing pickup orders into fulfillment and branch-holding history.
INSERT INTO `fulfillments`
  (`fulfillment_number`, `order_id`, `destination_branch_id`, `fulfillment_status`,
   `arrived_at`, `completed_at`, `created_at`)
SELECT
  CONCAT('FF-LEGACY-', p.`pickup_id`), p.`order_id`, p.`branch_id`,
  CASE p.`pickup_status`
    WHEN 'READY_FOR_PICKUP' THEN 'READY_FOR_PICKUP'
    WHEN 'COMPLETED' THEN 'COMPLETED'
    WHEN 'CANCELED' THEN 'CANCELED'
    ELSE 'PREPARING'
  END,
  COALESCE(p.`arrived_at`, p.`ready_at`),
  CASE WHEN p.`pickup_status` = 'COMPLETED' THEN p.`picked_up_at` ELSE NULL END,
  o.`ordered_at`
FROM `pickups` p
JOIN `orders` o ON o.`order_id` = p.`order_id`;

INSERT INTO `fulfillment_items`
  (`fulfillment_id`, `order_id`, `order_item_id`, `quantity`)
SELECT f.`fulfillment_id`, oi.`order_id`, oi.`order_item_id`, oi.`quantity`
FROM `fulfillments` f
JOIN `order_items` oi ON oi.`order_id` = f.`order_id`;

INSERT INTO `pickup_holdings`
  (`fulfillment_item_id`, `branch_id`, `holding_status`, `quantity`,
   `received_at`, `ready_at`, `picked_up_at`, `recalled_at`)
SELECT
  fi.`fulfillment_item_id`, p.`branch_id`,
  CASE p.`pickup_status`
    WHEN 'READY_FOR_PICKUP' THEN 'READY_FOR_PICKUP'
    WHEN 'COMPLETED' THEN 'PICKED_UP'
    WHEN 'CANCELED' THEN 'CANCELED'
    ELSE 'AWAITING_ARRIVAL'
  END,
  fi.`quantity`, COALESCE(p.`arrived_at`, p.`ready_at`), p.`ready_at`,
  p.`picked_up_at`, p.`recalled_at`
FROM `fulfillment_items` fi
JOIN `fulfillments` f ON f.`fulfillment_id` = fi.`fulfillment_id`
JOIN `pickups` p ON p.`order_id` = f.`order_id`;

-- The old branch-level stock table mixed sellable inventory with pickup holdings.
DROP TABLE `stocks`;
