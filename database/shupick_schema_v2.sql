-- Shupick v2 development schema (MySQL 8.0.16+)
-- Running this file resets only the tables in shupick_v2.

CREATE DATABASE IF NOT EXISTS `shupick_v2`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE `shupick_v2`;
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Drop tables added by ordered migrations so this development reset remains repeatable.
DROP TABLE IF EXISTS `coupon_restorations`, `coupon_refund_policies`;
DROP TABLE IF EXISTS `outbox_events`;
DROP TABLE IF EXISTS `audit_logs`, `employee_roles`;
DROP TABLE IF EXISTS `pickup_status_history`, `fulfillment_status_history`, `order_status_history`;
DROP TABLE IF EXISTS `pickup_holdings`, `fulfillment_items`, `fulfillments`, `inventory_reservations`, `inventory_movements`, `headquarters_inventory`;
DROP TABLE IF EXISTS `refund_items`, `refunds`, `point_usage_details`, `point_lots`, `point_policies`, `point_transactions`, `point_wallets`;
DROP TABLE IF EXISTS `customer_coupons`, `membership_coupon_rules`, `coupon_definitions`;
DROP TABLE IF EXISTS `membership_assessments`, `membership_tiers`, `inventory_policies`;
DROP TABLE IF EXISTS `pickup_reminders`, `pickup_retention_policies`;
DROP TABLE IF EXISTS `after_sales_inspections`, `return_policies`, `branch_business_hours`;
DROP TABLE IF EXISTS `purchase_approvals`, `purchase_requisition_items`, `purchase_requisitions`;
DROP TABLE IF EXISTS `approval_workflow_steps`, `approval_workflows`, `role_permissions`, `permissions`, `roles`;
DROP TABLE IF EXISTS `return_items`, `return_requests`, `inquiry_responses`, `inquiries`;
DROP TABLE IF EXISTS `review_images`, `reviews`, `pickups`, `deliveries`, `payments`;
DROP TABLE IF EXISTS `order_items`, `orders`, `product_views`, `favorites`, `cart_items`;
DROP TABLE IF EXISTS `stocks`, `product_images`, `product_variants`, `products`;
DROP TABLE IF EXISTS `categories`, `brands`, `manufacturers`;
DROP TABLE IF EXISTS `employee_branch_assignments`, `employees`, `customers`, `branches`;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE `branches` (
  `branch_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `branch_code` VARCHAR(20) NOT NULL,
  `branch_name` VARCHAR(100) NOT NULL,
  `address` VARCHAR(255) NOT NULL,
  `phone` VARCHAR(20) NOT NULL,
  `latitude` DECIMAL(10,7) DEFAULT NULL,
  `longitude` DECIMAL(10,7) DEFAULT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`branch_id`),
  UNIQUE KEY `uq_branches_code` (`branch_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `customers` (
  `customer_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(255) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `customer_name` VARCHAR(100) NOT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `reward_points` INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`customer_id`),
  UNIQUE KEY `uq_customers_email` (`email`),
  UNIQUE KEY `uq_customers_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `employees` (
  `employee_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `employee_code` VARCHAR(45) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `employee_name` VARCHAR(100) NOT NULL,
  `department` VARCHAR(50) NOT NULL,
  `position` VARCHAR(50) NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`employee_id`),
  UNIQUE KEY `uq_employees_code` (`employee_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `employee_branch_assignments` (
  `assignment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `employee_id` BIGINT UNSIGNED NOT NULL,
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `assigned_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`assignment_id`),
  KEY `idx_assignments_employee` (`employee_id`),
  KEY `idx_assignments_branch` (`branch_id`),
  CONSTRAINT `fk_assignments_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_assignments_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_assignments_period` CHECK (`ended_at` IS NULL OR `ended_at` >= `assigned_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `manufacturers` (
  `manufacturer_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `manufacturer_name` VARCHAR(100) NOT NULL,
  `contact_name` VARCHAR(100) DEFAULT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `email` VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`manufacturer_id`),
  UNIQUE KEY `uq_manufacturers_name` (`manufacturer_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `brands` (
  `brand_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `brand_code` VARCHAR(10) NOT NULL,
  `brand_name` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`brand_id`),
  UNIQUE KEY `uq_brands_code` (`brand_code`),
  UNIQUE KEY `uq_brands_name` (`brand_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `categories` (
  `category_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `parent_category_id` BIGINT UNSIGNED DEFAULT NULL,
  `category_code` VARCHAR(10) NOT NULL,
  `category_name` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`category_id`),
  UNIQUE KEY `uq_categories_code` (`category_code`),
  KEY `idx_categories_parent` (`parent_category_id`),
  CONSTRAINT `fk_categories_parent` FOREIGN KEY (`parent_category_id`) REFERENCES `categories` (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `products` (
  `product_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `brand_id` BIGINT UNSIGNED NOT NULL,
  `category_id` BIGINT UNSIGNED NOT NULL,
  `manufacturer_id` BIGINT UNSIGNED DEFAULT NULL,
  `model_code` VARCHAR(40) NOT NULL COMMENT 'Example: NK-M-SN-0001',
  `product_name` VARCHAR(150) NOT NULL,
  `gender_code` VARCHAR(10) NOT NULL,
  `product_description` TEXT DEFAULT NULL,
  `price` INT UNSIGNED NOT NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_id`),
  UNIQUE KEY `uq_products_model_code` (`model_code`),
  KEY `idx_products_brand` (`brand_id`),
  KEY `idx_products_category` (`category_id`),
  KEY `idx_products_manufacturer` (`manufacturer_id`),
  CONSTRAINT `fk_products_brand` FOREIGN KEY (`brand_id`) REFERENCES `brands` (`brand_id`),
  CONSTRAINT `fk_products_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  CONSTRAINT `fk_products_manufacturer` FOREIGN KEY (`manufacturer_id`) REFERENCES `manufacturers` (`manufacturer_id`),
  CONSTRAINT `chk_products_gender` CHECK (`gender_code` IN ('M', 'W', 'U', 'K'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `product_variants` (
  `product_variant_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `product_code` VARCHAR(64) NOT NULL COMMENT 'SKU: NK-M-SN-0001-BLK-250',
  `color_code` VARCHAR(20) NOT NULL,
  `color_name` VARCHAR(50) NOT NULL,
  `size_mm` SMALLINT UNSIGNED NOT NULL,
  `additional_price` INT NOT NULL DEFAULT 0,
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`product_variant_id`),
  UNIQUE KEY `uq_variants_product_code` (`product_code`),
  UNIQUE KEY `uq_variants_option` (`product_id`, `color_code`, `size_mm`),
  CONSTRAINT `fk_variants_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_variants_size` CHECK (`size_mm` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `product_images` (
  `product_image_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `color_code` VARCHAR(20) DEFAULT NULL,
  `image_url` VARCHAR(2048) NOT NULL,
  `sort_order` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `is_primary` BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (`product_image_id`),
  KEY `idx_product_images_product_color` (`product_id`, `color_code`),
  CONSTRAINT `fk_product_images_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `stocks` (
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `stock_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `reserved_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `inventory_status` VARCHAR(30) NOT NULL DEFAULT 'AVAILABLE',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`branch_id`, `product_variant_id`),
  KEY `idx_stocks_variant` (`product_variant_id`),
  CONSTRAINT `fk_stocks_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_stocks_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_stocks_reserved` CHECK (`reserved_quantity` <= `stock_quantity`),
  CONSTRAINT `chk_stocks_status` CHECK (`inventory_status` IN ('AVAILABLE','AWAITING_PICKUP','RETURNED','AWAITING_EXCHANGE','DEFECTIVE','UNAVAILABLE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `cart_items` (
  `cart_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL DEFAULT 1,
  `added_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`cart_item_id`),
  UNIQUE KEY `uq_cart_customer_variant` (`customer_id`, `product_variant_id`),
  KEY `idx_cart_variant` (`product_variant_id`),
  CONSTRAINT `fk_cart_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_cart_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_cart_quantity` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `favorites` (
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`, `product_id`),
  KEY `idx_favorites_product` (`product_id`),
  CONSTRAINT `fk_favorites_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_favorites_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `product_views` (
  `product_view_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `viewed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_view_id`),
  KEY `idx_views_customer_time` (`customer_id`, `viewed_at`),
  KEY `idx_views_product` (`product_id`),
  CONSTRAINT `fk_views_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_views_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `orders` (
  `order_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_number` VARCHAR(32) NOT NULL,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `pickup_branch_id` BIGINT UNSIGNED DEFAULT NULL,
  `fulfillment_type` VARCHAR(20) NOT NULL,
  `order_status` VARCHAR(30) NOT NULL DEFAULT 'PENDING_PAYMENT',
  `subtotal_amount` INT UNSIGNED NOT NULL,
  `coupon_discount` INT UNSIGNED NOT NULL DEFAULT 0,
  `points_used` INT UNSIGNED NOT NULL DEFAULT 0,
  `paid_total` INT UNSIGNED NOT NULL,
  `ordered_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `purchase_confirmed_at` DATETIME DEFAULT NULL,
  `canceled_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `uq_orders_number` (`order_number`),
  KEY `idx_orders_customer_time` (`customer_id`, `ordered_at`),
  KEY `idx_orders_pickup_branch` (`pickup_branch_id`),
  CONSTRAINT `fk_orders_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_orders_pickup_branch` FOREIGN KEY (`pickup_branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_orders_fulfillment` CHECK (`fulfillment_type` IN ('DELIVERY','PICKUP')),
  CONSTRAINT `chk_orders_branch` CHECK ((`fulfillment_type`='PICKUP' AND `pickup_branch_id` IS NOT NULL) OR (`fulfillment_type`='DELIVERY' AND `pickup_branch_id` IS NULL)),
  CONSTRAINT `chk_orders_status` CHECK (`order_status` IN ('PENDING_PAYMENT','PAID','PREPARING','SHIPPING','READY_FOR_PICKUP','COMPLETED','CANCELED','REFUNDED')),
  CONSTRAINT `chk_orders_amount`
    CHECK (`paid_total` + `coupon_discount` + `points_used` = `subtotal_amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `order_items` (
  `order_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `product_name` VARCHAR(150) NOT NULL,
  `product_code` VARCHAR(64) NOT NULL,
  `color_name` VARCHAR(50) NOT NULL,
  `size_mm` SMALLINT UNSIGNED NOT NULL,
  `unit_price` INT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `line_total` INT UNSIGNED GENERATED ALWAYS AS (`unit_price` * `quantity`) STORED,
  PRIMARY KEY (`order_item_id`),
  UNIQUE KEY `uq_order_items_variant` (`order_id`, `product_variant_id`),
  KEY `idx_order_items_variant` (`product_variant_id`),
  CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_order_items_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_order_items_quantity` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `payments` (
  `payment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `payment_method` VARCHAR(30) NOT NULL,
  `payment_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `payment_amount` INT UNSIGNED NOT NULL,
  `transaction_key` VARCHAR(100) DEFAULT NULL,
  `paid_at` DATETIME DEFAULT NULL,
  `refunded_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`payment_id`),
  UNIQUE KEY `uq_payments_transaction_key` (`transaction_key`),
  KEY `idx_payments_order` (`order_id`),
  CONSTRAINT `fk_payments_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_payments_status` CHECK (`payment_status` IN ('PENDING','PAID','FAILED','CANCELED','REFUNDED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `deliveries` (
  `delivery_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `delivery_status` VARCHAR(30) NOT NULL DEFAULT 'PREPARING',
  `recipient_name` VARCHAR(100) NOT NULL,
  `recipient_phone` VARCHAR(20) NOT NULL,
  `postal_code` VARCHAR(10) NOT NULL,
  `address` VARCHAR(255) NOT NULL,
  `address_detail` VARCHAR(255) DEFAULT NULL,
  `tracking_number` VARCHAR(100) DEFAULT NULL,
  `shipped_at` DATETIME DEFAULT NULL,
  `delivered_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`delivery_id`),
  UNIQUE KEY `uq_deliveries_order` (`order_id`),
  UNIQUE KEY `uq_deliveries_tracking` (`tracking_number`),
  CONSTRAINT `fk_deliveries_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_deliveries_status` CHECK (`delivery_status` IN ('PREPARING','SHIPPED','IN_TRANSIT','DELIVERED','RETURNED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `pickups` (
  `pickup_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `handled_by_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `pickup_status` VARCHAR(30) NOT NULL DEFAULT 'PREPARING',
  `ready_at` DATETIME DEFAULT NULL,
  `picked_up_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`pickup_id`),
  UNIQUE KEY `uq_pickups_order` (`order_id`),
  KEY `idx_pickups_branch` (`branch_id`),
  KEY `idx_pickups_employee` (`handled_by_employee_id`),
  CONSTRAINT `fk_pickups_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_pickups_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_pickups_employee` FOREIGN KEY (`handled_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_pickups_status` CHECK (`pickup_status` IN ('PREPARING','READY_FOR_PICKUP','COMPLETED','CANCELED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `reviews` (
  `review_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_item_id` BIGINT UNSIGNED NOT NULL,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `rating` TINYINT UNSIGNED NOT NULL,
  `review_content` TEXT NOT NULL,
  `fit_size` VARCHAR(30) DEFAULT NULL,
  `fit_width` VARCHAR(30) DEFAULT NULL,
  `fit_comfort` VARCHAR(30) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`review_id`),
  UNIQUE KEY `uq_reviews_order_item` (`order_item_id`),
  KEY `idx_reviews_customer` (`customer_id`),
  CONSTRAINT `fk_reviews_order_item` FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`order_item_id`),
  CONSTRAINT `fk_reviews_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `chk_reviews_rating` CHECK (`rating` BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `review_images` (
  `review_image_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `review_id` BIGINT UNSIGNED NOT NULL,
  `image_url` VARCHAR(2048) NOT NULL,
  `sort_order` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`review_image_id`),
  KEY `idx_review_images_review` (`review_id`),
  CONSTRAINT `fk_review_images_review` FOREIGN KEY (`review_id`) REFERENCES `reviews` (`review_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `inquiries` (
  `inquiry_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `product_id` BIGINT UNSIGNED DEFAULT NULL,
  `inquiry_type` VARCHAR(30) NOT NULL,
  `title` VARCHAR(150) NOT NULL,
  `inquiry_content` TEXT NOT NULL,
  `inquiry_status` VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inquiry_id`),
  KEY `idx_inquiries_customer` (`customer_id`),
  KEY `idx_inquiries_product` (`product_id`),
  CONSTRAINT `fk_inquiries_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_inquiries_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_inquiries_status` CHECK (`inquiry_status` IN ('OPEN','ANSWERED','CLOSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `inquiry_responses` (
  `inquiry_response_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `inquiry_id` BIGINT UNSIGNED NOT NULL,
  `employee_id` BIGINT UNSIGNED NOT NULL,
  `response_content` TEXT NOT NULL,
  `responded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inquiry_response_id`),
  KEY `idx_responses_inquiry` (`inquiry_id`),
  KEY `idx_responses_employee` (`employee_id`),
  CONSTRAINT `fk_responses_inquiry` FOREIGN KEY (`inquiry_id`) REFERENCES `inquiries` (`inquiry_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_responses_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `return_requests` (
  `return_request_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL,
  `customer_id` BIGINT UNSIGNED NOT NULL,
  `branch_id` BIGINT UNSIGNED DEFAULT NULL,
  `handled_by_employee_id` BIGINT UNSIGNED DEFAULT NULL,
  `request_type` VARCHAR(20) NOT NULL,
  `request_status` VARCHAR(30) NOT NULL DEFAULT 'REQUESTED',
  `return_reason` TEXT NOT NULL,
  `inspection_result` VARCHAR(30) DEFAULT NULL,
  `rejection_reason` TEXT DEFAULT NULL,
  `refund_amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed_at` DATETIME DEFAULT NULL,
  `refunded_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`return_request_id`),
  KEY `idx_returns_order` (`order_id`),
  KEY `idx_returns_customer` (`customer_id`),
  KEY `idx_returns_branch` (`branch_id`),
  KEY `idx_returns_employee` (`handled_by_employee_id`),
  CONSTRAINT `fk_returns_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_returns_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_returns_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_returns_employee` FOREIGN KEY (`handled_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_returns_type` CHECK (`request_type` IN ('RETURN','EXCHANGE')),
  CONSTRAINT `chk_returns_status` CHECK (`request_status` IN ('REQUESTED','APPROVED','REJECTED','COLLECTING','INSPECTING','REFUNDED','EXCHANGED','COMPLETED','CANCELED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `return_items` (
  `return_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `return_request_id` BIGINT UNSIGNED NOT NULL,
  `order_item_id` BIGINT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`return_item_id`),
  UNIQUE KEY `uq_return_items_order_item` (`return_request_id`, `order_item_id`),
  KEY `idx_return_items_order_item` (`order_item_id`),
  CONSTRAINT `fk_return_items_request` FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_return_items_order_item` FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`order_item_id`),
  CONSTRAINT `chk_return_items_quantity` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `purchase_requisitions` (
  `purchase_requisition_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `requested_by_employee_id` BIGINT UNSIGNED NOT NULL,
  `branch_id` BIGINT UNSIGNED NOT NULL,
  `title` VARCHAR(150) NOT NULL,
  `reason` TEXT NOT NULL,
  `requisition_status` VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
  `submitted_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`purchase_requisition_id`),
  KEY `idx_requisitions_employee` (`requested_by_employee_id`),
  KEY `idx_requisitions_branch` (`branch_id`),
  CONSTRAINT `fk_requisitions_employee` FOREIGN KEY (`requested_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_requisitions_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_requisitions_status` CHECK (`requisition_status` IN ('DRAFT','SUBMITTED','APPROVED','REJECTED','ORDERED','CANCELED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `purchase_requisition_items` (
  `purchase_requisition_item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `purchase_requisition_id` BIGINT UNSIGNED NOT NULL,
  `product_variant_id` BIGINT UNSIGNED NOT NULL,
  `requested_quantity` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`purchase_requisition_item_id`),
  UNIQUE KEY `uq_requisition_items_variant` (`purchase_requisition_id`, `product_variant_id`),
  KEY `idx_requisition_items_variant` (`product_variant_id`),
  CONSTRAINT `fk_requisition_items_requisition` FOREIGN KEY (`purchase_requisition_id`) REFERENCES `purchase_requisitions` (`purchase_requisition_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_requisition_items_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_requisition_items_quantity` CHECK (`requested_quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `purchase_approvals` (
  `purchase_approval_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `purchase_requisition_id` BIGINT UNSIGNED NOT NULL,
  `approver_employee_id` BIGINT UNSIGNED NOT NULL,
  `approval_status` VARCHAR(20) NOT NULL,
  `approval_comment` TEXT DEFAULT NULL,
  `decided_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`purchase_approval_id`),
  UNIQUE KEY `uq_approvals_requisition_employee` (`purchase_requisition_id`, `approver_employee_id`),
  KEY `idx_approvals_employee` (`approver_employee_id`),
  CONSTRAINT `fk_approvals_requisition` FOREIGN KEY (`purchase_requisition_id`) REFERENCES `purchase_requisitions` (`purchase_requisition_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_approvals_employee` FOREIGN KEY (`approver_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_approvals_status` CHECK (`approval_status` IN ('APPROVED','REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
