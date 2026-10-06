-- Preserve append-only order, fulfillment, and pickup status changes.
USE `shupick_v2`;

CREATE TABLE `order_status_history` (
  `order_status_history_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `previous_status` VARCHAR(30) DEFAULT NULL,
  `new_status` VARCHAR(30) NOT NULL,
  `change_source` VARCHAR(30) NOT NULL,
  `change_reason` VARCHAR(255) DEFAULT NULL,
  `actor_type` VARCHAR(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_customer_id` BIGINT UNSIGNED DEFAULT NULL,
  `actor_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `changed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_status_history_id`),
  KEY `idx_order_status_history_order_time` (`order_id`, `changed_at`),
  KEY `idx_order_status_history_customer` (`actor_customer_id`),
  KEY `idx_order_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_order_status_history_order`
    FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_order_status_history_customer`
    FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_order_status_history_employee`
    FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_order_status_history_actor`
    CHECK (
      (`actor_type` = 'SYSTEM' AND `actor_customer_id` IS NULL AND `actor_employee_id` IS NULL)
      OR (`actor_type` = 'CUSTOMER' AND `actor_customer_id` IS NOT NULL AND `actor_employee_id` IS NULL)
      OR (`actor_type` = 'EMPLOYEE' AND `actor_customer_id` IS NULL AND `actor_employee_id` IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `fulfillment_status_history` (
  `fulfillment_status_history_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `fulfillment_id` BIGINT UNSIGNED NOT NULL,
  `previous_status` VARCHAR(30) DEFAULT NULL,
  `new_status` VARCHAR(30) NOT NULL,
  `change_source` VARCHAR(30) NOT NULL,
  `change_reason` VARCHAR(255) DEFAULT NULL,
  `actor_type` VARCHAR(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `changed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`fulfillment_status_history_id`),
  KEY `idx_fulfillment_status_history_time` (`fulfillment_id`, `changed_at`),
  KEY `idx_fulfillment_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_fulfillment_status_history_fulfillment`
    FOREIGN KEY (`fulfillment_id`) REFERENCES `fulfillments` (`fulfillment_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_fulfillment_status_history_employee`
    FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_fulfillment_status_history_actor`
    CHECK (
      (`actor_type` = 'SYSTEM' AND `actor_employee_id` IS NULL)
      OR (`actor_type` = 'EMPLOYEE' AND `actor_employee_id` IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `pickup_status_history` (
  `pickup_status_history_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `pickup_id` BIGINT UNSIGNED NOT NULL,
  `previous_status` VARCHAR(30) DEFAULT NULL,
  `new_status` VARCHAR(30) NOT NULL,
  `change_source` VARCHAR(30) NOT NULL,
  `change_reason` VARCHAR(255) DEFAULT NULL,
  `actor_type` VARCHAR(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_customer_id` BIGINT UNSIGNED DEFAULT NULL,
  `actor_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `changed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`pickup_status_history_id`),
  KEY `idx_pickup_status_history_time` (`pickup_id`, `changed_at`),
  KEY `idx_pickup_status_history_customer` (`actor_customer_id`),
  KEY `idx_pickup_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_pickup_status_history_pickup`
    FOREIGN KEY (`pickup_id`) REFERENCES `pickups` (`pickup_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_pickup_status_history_customer`
    FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_pickup_status_history_employee`
    FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_pickup_status_history_actor`
    CHECK (
      (`actor_type` = 'SYSTEM' AND `actor_customer_id` IS NULL AND `actor_employee_id` IS NULL)
      OR (`actor_type` = 'CUSTOMER' AND `actor_customer_id` IS NOT NULL AND `actor_employee_id` IS NULL)
      OR (`actor_type` = 'EMPLOYEE' AND `actor_customer_id` IS NULL AND `actor_employee_id` IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `order_status_history`
  (`order_id`, `previous_status`, `new_status`, `change_source`, `change_reason`)
SELECT `order_id`, NULL, `order_status`, 'MIGRATION', '상태 이력 도입 시점의 현재 상태'
FROM `orders`;

INSERT INTO `fulfillment_status_history`
  (`fulfillment_id`, `previous_status`, `new_status`, `change_source`, `change_reason`)
SELECT `fulfillment_id`, NULL, `fulfillment_status`, 'MIGRATION', '상태 이력 도입 시점의 현재 상태'
FROM `fulfillments`;

INSERT INTO `pickup_status_history`
  (`pickup_id`, `previous_status`, `new_status`, `change_source`, `change_reason`)
SELECT `pickup_id`, NULL, `pickup_status`, 'MIGRATION', '상태 이력 도입 시점의 현재 상태'
FROM `pickups`;
