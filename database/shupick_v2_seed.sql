-- Shupick v2 sample data
-- Run after shupick_schema_v2.sql. This file is intended to run once on an empty schema.

USE `shupick_v2`;

INSERT INTO `branches`
  (`branch_code`, `branch_name`, `address`, `phone`, `latitude`, `longitude`)
VALUES
  ('SEL-SD', 'SOLE 성동점', '서울특별시 성동구 테스트로 10', '02-0000-0001', 37.5635000, 127.0369000);

INSERT INTO `customers`
  (`email`, `password_hash`, `customer_name`, `phone`, `reward_points`)
VALUES
  ('customer@example.com', 'TEST_ONLY_REPLACE_WITH_REAL_PASSWORD_HASH', '테스트 고객', '010-0000-0001', 3000);

INSERT INTO `employees`
  (`employee_code`, `password_hash`, `employee_name`, `department`, `position`)
VALUES
  ('EMP-0001', 'TEST_ONLY_REPLACE_WITH_REAL_PASSWORD_HASH', '테스트 직원', '대리점', '매니저'),
  ('EMP-0002', 'TEST_ONLY_REPLACE_WITH_REAL_PASSWORD_HASH', '본사 승인자', '구매', '팀장');

INSERT INTO `employee_branch_assignments`
  (`employee_id`, `branch_id`)
SELECT e.`employee_id`, b.`branch_id`
FROM `employees` e
JOIN `branches` b ON b.`branch_code` = 'SEL-SD'
WHERE e.`employee_code` = 'EMP-0001';

INSERT INTO `manufacturers` (`manufacturer_name`, `contact_name`, `phone`, `email`)
VALUES ('나이키 코리아', '테스트 담당자', '02-0000-0010', 'vendor@example.com');

INSERT INTO `brands` (`brand_code`, `brand_name`)
VALUES ('NK', 'Nike');

INSERT INTO `categories` (`category_code`, `category_name`)
VALUES ('SH', '신발');

INSERT INTO `categories` (`parent_category_id`, `category_code`, `category_name`)
SELECT `category_id`, 'SN', '운동화'
FROM `categories`
WHERE `category_code` = 'SH';

INSERT INTO `products`
  (`brand_id`, `category_id`, `manufacturer_id`, `model_code`, `product_name`,
   `gender_code`, `product_description`, `price`)
SELECT
  b.`brand_id`, c.`category_id`, m.`manufacturer_id`,
  'NK-M-SN-0001', 'Silver Current', 'M', 'Shupick v2 테스트 상품', 129000
FROM `brands` b
JOIN `categories` c ON c.`category_code` = 'SN'
JOIN `manufacturers` m ON m.`manufacturer_name` = '나이키 코리아'
WHERE b.`brand_code` = 'NK';

INSERT INTO `product_variants`
  (`product_id`, `product_code`, `color_code`, `color_name`, `size_mm`)
SELECT `product_id`, 'NK-M-SN-0001-BLK-250', 'BLK', '블랙', 250
FROM `products`
WHERE `model_code` = 'NK-M-SN-0001';

INSERT INTO `product_variants`
  (`product_id`, `product_code`, `color_code`, `color_name`, `size_mm`)
SELECT `product_id`, 'NK-M-SN-0001-BLK-260', 'BLK', '블랙', 260
FROM `products`
WHERE `model_code` = 'NK-M-SN-0001';

INSERT INTO `product_images`
  (`product_id`, `color_code`, `image_url`, `sort_order`, `is_primary`)
SELECT `product_id`, 'BLK', 'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png', 0, TRUE
FROM `products`
WHERE `model_code` = 'NK-M-SN-0001';

INSERT INTO `stocks`
  (`branch_id`, `product_variant_id`, `stock_quantity`, `reserved_quantity`, `inventory_status`)
SELECT b.`branch_id`, v.`product_variant_id`, 20, 0, 'AVAILABLE'
FROM `branches` b
CROSS JOIN `product_variants` v
WHERE b.`branch_code` = 'SEL-SD'
  AND v.`product_code` IN ('NK-M-SN-0001-BLK-250', 'NK-M-SN-0001-BLK-260');

INSERT INTO `cart_items` (`customer_id`, `product_variant_id`, `quantity`)
SELECT c.`customer_id`, v.`product_variant_id`, 1
FROM `customers` c
JOIN `product_variants` v ON v.`product_code` = 'NK-M-SN-0001-BLK-260'
WHERE c.`email` = 'customer@example.com';

INSERT INTO `favorites` (`customer_id`, `product_id`)
SELECT c.`customer_id`, p.`product_id`
FROM `customers` c
CROSS JOIN `products` p
WHERE c.`email` = 'customer@example.com'
  AND p.`model_code` = 'NK-M-SN-0001';

INSERT INTO `product_views` (`customer_id`, `product_id`)
SELECT c.`customer_id`, p.`product_id`
FROM `customers` c
CROSS JOIN `products` p
WHERE c.`email` = 'customer@example.com'
  AND p.`model_code` = 'NK-M-SN-0001';

INSERT INTO `orders`
  (`order_number`, `customer_id`, `pickup_branch_id`, `fulfillment_type`, `order_status`,
   `subtotal_amount`, `coupon_discount`, `points_used`, `paid_total`, `purchase_confirmed_at`)
SELECT
  'ORD-TEST-0001', c.`customer_id`, b.`branch_id`, 'PICKUP', 'COMPLETED',
  129000, 0, 0, 129000, CURRENT_TIMESTAMP
FROM `customers` c
CROSS JOIN `branches` b
WHERE c.`email` = 'customer@example.com'
  AND b.`branch_code` = 'SEL-SD';

INSERT INTO `order_items`
  (`order_id`, `product_variant_id`, `product_name`, `product_code`, `color_name`,
   `size_mm`, `unit_price`, `quantity`)
SELECT
  o.`order_id`, v.`product_variant_id`, p.`product_name`, v.`product_code`,
  v.`color_name`, v.`size_mm`, p.`price` + v.`additional_price`, 1
FROM `orders` o
JOIN `product_variants` v ON v.`product_code` = 'NK-M-SN-0001-BLK-250'
JOIN `products` p ON p.`product_id` = v.`product_id`
WHERE o.`order_number` = 'ORD-TEST-0001';

INSERT INTO `payments`
  (`order_id`, `payment_method`, `payment_status`, `payment_amount`, `transaction_key`, `paid_at`)
SELECT `order_id`, 'CARD', 'PAID', 129000, 'TEST-PAYMENT-0001', CURRENT_TIMESTAMP
FROM `orders`
WHERE `order_number` = 'ORD-TEST-0001';

INSERT INTO `pickups`
  (`order_id`, `branch_id`, `handled_by_employee_id`, `pickup_status`, `ready_at`, `picked_up_at`)
SELECT o.`order_id`, o.`pickup_branch_id`, e.`employee_id`, 'COMPLETED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM `orders` o
JOIN `employees` e ON e.`employee_code` = 'EMP-0001'
WHERE o.`order_number` = 'ORD-TEST-0001';

INSERT INTO `reviews`
  (`order_item_id`, `customer_id`, `rating`, `review_content`, `fit_size`, `fit_width`, `fit_comfort`)
SELECT oi.`order_item_id`, o.`customer_id`, 5, '테스트 리뷰입니다.', '정사이즈', '적당함', '편안함'
FROM `order_items` oi
JOIN `orders` o ON o.`order_id` = oi.`order_id`
WHERE o.`order_number` = 'ORD-TEST-0001';

INSERT INTO `inquiries`
  (`customer_id`, `product_id`, `inquiry_type`, `title`, `inquiry_content`)
SELECT c.`customer_id`, p.`product_id`, 'PRODUCT', '재입고 문의', '260 사이즈 재입고 예정일이 궁금합니다.'
FROM `customers` c
CROSS JOIN `products` p
WHERE c.`email` = 'customer@example.com'
  AND p.`model_code` = 'NK-M-SN-0001';

INSERT INTO `inquiry_responses` (`inquiry_id`, `employee_id`, `response_content`)
SELECT i.`inquiry_id`, e.`employee_id`, '다음 주 입고 예정입니다.'
FROM `inquiries` i
JOIN `employees` e ON e.`employee_code` = 'EMP-0001'
WHERE i.`title` = '재입고 문의';

UPDATE `inquiries`
SET `inquiry_status` = 'ANSWERED'
WHERE `title` = '재입고 문의';

INSERT INTO `purchase_requisitions`
  (`requested_by_employee_id`, `branch_id`, `title`, `reason`, `requisition_status`, `submitted_at`)
SELECT e.`employee_id`, b.`branch_id`, 'Silver Current 추가 발주', '안전 재고 확보', 'APPROVED', CURRENT_TIMESTAMP
FROM `employees` e
CROSS JOIN `branches` b
WHERE e.`employee_code` = 'EMP-0001'
  AND b.`branch_code` = 'SEL-SD';

INSERT INTO `purchase_requisition_items`
  (`purchase_requisition_id`, `product_variant_id`, `requested_quantity`)
SELECT r.`purchase_requisition_id`, v.`product_variant_id`, 10
FROM `purchase_requisitions` r
JOIN `product_variants` v ON v.`product_code` = 'NK-M-SN-0001-BLK-250'
WHERE r.`title` = 'Silver Current 추가 발주';

INSERT INTO `purchase_approvals`
  (`purchase_requisition_id`, `approver_employee_id`, `approval_status`, `approval_comment`)
SELECT r.`purchase_requisition_id`, e.`employee_id`, 'APPROVED', '발주를 승인합니다.'
FROM `purchase_requisitions` r
JOIN `employees` e ON e.`employee_code` = 'EMP-0002'
WHERE r.`title` = 'Silver Current 추가 발주';
