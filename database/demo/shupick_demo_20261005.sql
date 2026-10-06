-- SHUPICK demo dataset proposal, 2026-10-05. NOT APPLIED.
-- Target: current shupick_v2 schema, migrations through 024.
-- MySQL client / Workbench: execute the entire script with DELIMITER support.
-- Default guard prevents business-data insertion. Change apply to 1 ONLY after approval.
-- This script defines a temporary loader procedure; CREATE/DROP PROCEDURE require privileges.
-- One-time dataset: existing DEMO26-* records cause an error, never overwrite existing data.
-- No Firebase accounts, employee permissions, notifications, or real payment calls are created.
SET NAMES utf8mb4;
USE shupick_v2;
SET @shupick_demo_apply = 0;
-- Optional: existing customers.firebase_uid for YOUR test login. NULL creates 12 fake profiles.
-- A non-NULL UID must already be synchronized by the customer app; no account is overwritten.
SET @shupick_demo_customer_uid = NULL;

DELIMITER $$
DROP PROCEDURE IF EXISTS shupick_load_demo_20261005$$
CREATE PROCEDURE shupick_load_demo_20261005(IN p_apply BOOLEAN, IN p_customer_uid VARCHAR(128))
BEGIN
  DECLARE n INT DEFAULT 1;
  DECLARE v_customer BIGINT UNSIGNED;
  DECLARE v_product BIGINT UNSIGNED;
  DECLARE v_variant BIGINT UNSIGNED;
  DECLARE v_branch BIGINT UNSIGNED;
  DECLARE v_order BIGINT UNSIGNED;
  DECLARE v_item BIGINT UNSIGNED;
  DECLARE v_fulfillment BIGINT UNSIGNED;
  DECLARE v_fitem BIGINT UNSIGNED;
  DECLARE v_pickup BIGINT UNSIGNED;
  DECLARE v_return BIGINT UNSIGNED;
  DECLARE v_requisition BIGINT UNSIGNED;
  DECLARE v_review BIGINT UNSIGNED;
  DECLARE v_transaction BIGINT UNSIGNED;
  DECLARE v_root BIGINT UNSIGNED;
  DECLARE v_workflow BIGINT UNSIGNED;
  DECLARE v_requester BIGINT UNSIGNED;
  DECLARE v_lead BIGINT UNSIGNED;
  DECLARE v_director BIGINT UNSIGNED;
  DECLARE v_support BIGINT UNSIGNED;
  DECLARE v_pickup_policy BIGINT UNSIGNED;
  DECLARE v_return_policy BIGINT UNSIGNED;
  DECLARE v_hold_days INT;
  DECLARE v_return_days INT;
  DECLARE v_price INT;
  DECLARE v_balance INT;
  DECLARE v_state VARCHAR(30);
  DECLARE v_fstate VARCHAR(30);
  DECLARE v_pstate VARCHAR(30);
  DECLARE v_ordered DATETIME;
  DECLARE v_now DATETIME DEFAULT NOW();
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    DROP TEMPORARY TABLE IF EXISTS demo26_products, demo26_customers, demo26_orders;
    RESIGNAL;
  END;

  IF COALESCE(p_apply,0) <> 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Preview only. Set @shupick_demo_apply=1 only after approval.';
  END IF;
  IF EXISTS(SELECT 1 FROM products WHERE model_code LIKE 'DEMO26-%')
     OR EXISTS(SELECT 1 FROM orders WHERE order_number LIKE 'DEMO26-%')
     OR EXISTS(SELECT 1 FROM customers WHERE firebase_uid LIKE 'DEMO26-%')
     OR EXISTS(SELECT 1 FROM brands WHERE brand_code LIKE 'D26%')
     OR EXISTS(SELECT 1 FROM categories WHERE category_code LIKE 'D26%')
     OR EXISTS(SELECT 1 FROM purchase_requisitions WHERE title LIKE '[DEMO26]%') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 dataset already exists or prefix collision. Stop; do not rerun.';
  END IF;
  IF p_customer_uid IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM customers WHERE firebase_uid=p_customer_uid AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Test Firebase UID is not linked to an active customer. Sign in/sync first.';
  END IF;
  SELECT category_id INTO v_root FROM categories WHERE category_code='SH';
  SELECT approval_workflow_id INTO v_workflow FROM approval_workflows
    WHERE workflow_code='PROCUREMENT_STANDARD' AND is_active=1;
  SELECT MIN(e.employee_id) INTO v_requester FROM employees e
    JOIN employee_roles er ON er.employee_id=e.employee_id JOIN roles r ON r.role_id=er.role_id
    WHERE e.is_active=1 AND r.role_code='HQ_STAFF'
      AND NOT EXISTS(SELECT 1 FROM employee_roles er2 JOIN roles r2 ON r2.role_id=er2.role_id
        WHERE er2.employee_id=e.employee_id AND r2.role_code IN ('TEAM_LEAD','DIRECTOR'));
  SELECT MIN(e.employee_id) INTO v_lead FROM employees e
    JOIN employee_roles er ON er.employee_id=e.employee_id JOIN roles r ON r.role_id=er.role_id
    WHERE e.is_active=1 AND r.role_code='TEAM_LEAD' AND e.employee_id<>v_requester;
  SELECT MIN(e.employee_id) INTO v_director FROM employees e
    JOIN employee_roles er ON er.employee_id=e.employee_id JOIN roles r ON r.role_id=er.role_id
    WHERE e.is_active=1 AND r.role_code='DIRECTOR' AND e.employee_id<>v_requester;
  SET v_support=v_requester;
  SELECT pickup_retention_policy_id,holding_days INTO v_pickup_policy,v_hold_days
    FROM pickup_retention_policies WHERE effective_from<=DATE(v_now)
      AND (effective_to IS NULL OR effective_to>=DATE(v_now))
    ORDER BY effective_from DESC,pickup_retention_policy_id DESC LIMIT 1;
  SELECT return_policy_id,standard_return_days INTO v_return_policy,v_return_days
    FROM return_policies WHERE effective_from<=DATE(v_now)
      AND (effective_to IS NULL OR effective_to>=DATE(v_now))
    ORDER BY effective_from DESC,return_policy_id DESC LIMIT 1;
  IF v_root IS NULL OR v_workflow IS NULL OR v_requester IS NULL OR v_lead IS NULL
     OR v_director IS NULL OR v_pickup_policy IS NULL OR v_return_policy IS NULL
     OR NOT EXISTS(SELECT 1 FROM categories WHERE category_code='SN' AND parent_category_id=v_root)
     OR (SELECT COUNT(*) FROM branches WHERE branch_code IN ('SEL-SD','SEL-GN') AND is_active=1)<>2
     OR (SELECT COUNT(*) FROM approval_workflow_steps s JOIN roles r ON r.role_id=s.required_role_id
         WHERE s.approval_workflow_id=v_workflow
         AND ((s.step_order=1 AND r.role_code='TEAM_LEAD') OR
              (s.step_order=2 AND r.role_code='DIRECTOR')))<>2
     OR (SELECT COUNT(*) FROM approval_workflow_steps WHERE approval_workflow_id=v_workflow)<>2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Required categories, branches, employees, policies, or approval workflow missing.';
  END IF;

  START TRANSACTION;
  CREATE TEMPORARY TABLE demo26_products(
    seq INT PRIMARY KEY, brand_code VARCHAR(20), category_code VARCHAR(30),
    name VARCHAR(150), gender CHAR(1), price INT, image_url VARCHAR(1000)
  );
  INSERT INTO demo26_products VALUES
    (1,'D26C','D26RUN','에어 라이트 러너','U',89000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png'),
    (2,'D26C','D26RUN','데일리 페이스 러너','M',119000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_2e7f3842-62de-421a-8855-6bbac9864ab6.png'),
    (3,'D26C','D26WALK','클라우드 워커','W',99000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_496afa2f-095c-4ce1-87bd-81f09c8f9fc7.png'),
    (4,'D26C','D26WALK','시티 컴포트 워커','U',109000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_883111c9-d119-43bf-a16d-d11f25469a67.png'),
    (5,'D26A','D26CANVAS','클래식 캔버스 로우','M',59000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071117_6e9218c6-59d9-4a86-ab98-c15b856fd71c.png'),
    (6,'D26A','D26CANVAS','위켄드 캔버스','W',69000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_4a6637ae-b3c0-45bf-8dc4-23873e53ac6c.png'),
    (7,'D26A','D26SLIP','이지 데이 슬립온','U',79000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png'),
    (8,'D26A','D26SLIP','소프트 니트 슬립온','M',89000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_2e7f3842-62de-421a-8855-6bbac9864ab6.png'),
    (9,'D26B','D26LOAF','모던 페니 로퍼','M',129000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_496afa2f-095c-4ce1-87bd-81f09c8f9fc7.png'),
    (10,'D26B','D26LOAF','컴포트 스웨이드 로퍼','M',119000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_883111c9-d119-43bf-a16d-d11f25469a67.png'),
    (11,'D26B','D26OX','클래식 레더 옥스퍼드','M',149000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071117_6e9218c6-59d9-4a86-ab98-c15b856fd71c.png'),
    (12,'D26B','D26OX','라이트 비즈니스 옥스퍼드','M',139000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_4a6637ae-b3c0-45bf-8dc4-23873e53ac6c.png'),
    (13,'D26B','D26ANKLE','스웨이드 앵클 부츠','W',159000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png'),
    (14,'D26B','D26ANKLE','시티 레더 앵클','W',169000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_2e7f3842-62de-421a-8855-6bbac9864ab6.png'),
    (15,'D26B','D26CHEL','어반 첼시 부츠','W',179000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_496afa2f-095c-4ce1-87bd-81f09c8f9fc7.png'),
    (16,'D26B','D26CHEL','데일리 첼시','U',189000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_883111c9-d119-43bf-a16d-d11f25469a67.png'),
    (17,'D26A','D26SPORT','트레일 스포츠 샌들','M',79000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071117_6e9218c6-59d9-4a86-ab98-c15b856fd71c.png'),
    (18,'D26A','D26SPORT','라이트 스트랩 샌들','W',89000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_4a6637ae-b3c0-45bf-8dc4-23873e53ac6c.png'),
    (19,'D26A','D26SLIDE','쿠션 데일리 슬라이드','U',39000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_4579da28-0d2f-42fc-8ecf-9901a170129b.png'),
    (20,'D26A','D26SLIDE','리커버리 슬라이드','M',49000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071141_2e7f3842-62de-421a-8855-6bbac9864ab6.png'),
    (21,'D26D','D26KRUN','키즈 점프 러너','K',59000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_496afa2f-095c-4ce1-87bd-81f09c8f9fc7.png'),
    (22,'D26D','D26KRUN','키즈 컬러 러너','K',69000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_883111c9-d119-43bf-a16d-d11f25469a67.png'),
    (23,'D26D','D26KSAND','키즈 썸머 샌들','K',39000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071117_6e9218c6-59d9-4a86-ab98-c15b856fd71c.png'),
    (24,'D26D','D26KSAND','키즈 플레이 샌들','K',49000,'https://d8j0ntlcm91z4.cloudfront.net/user_3JjAHkEXFHHfG3ERJjDsSHbdRq6/hf_20260928_071118_4a6637ae-b3c0-45bf-8dc4-23873e53ac6c.png');

  INSERT INTO brands(brand_code,brand_name) VALUES
    ('D26A','SHUPICK LAB'),('D26B','CITY STEP'),('D26C','RUN FLOW'),('D26D','LITTLE PICK');
  -- Reuse SH -> SN (신발 -> 운동화); add the other five middle categories.
  INSERT INTO categories(parent_category_id,category_code,category_name) VALUES
    (v_root,'D26CA','캐주얼화'),(v_root,'D26DR','구두'),(v_root,'D26BO','부츠'),
    (v_root,'D26SA','샌들'),(v_root,'D26KI','키즈');
  INSERT INTO categories(parent_category_id,category_code,category_name)
  SELECT c.category_id,x.code,x.name FROM categories c JOIN (
    SELECT 'SN' parent,'D26RUN' code,'러닝화' name UNION ALL
    SELECT 'SN','D26WALK','워킹화' UNION ALL
    SELECT 'D26CA','D26CANVAS','캔버스화' UNION ALL SELECT 'D26CA','D26SLIP','슬립온' UNION ALL
    SELECT 'D26DR','D26LOAF','로퍼' UNION ALL SELECT 'D26DR','D26OX','옥스퍼드' UNION ALL
    SELECT 'D26BO','D26ANKLE','앵클부츠' UNION ALL SELECT 'D26BO','D26CHEL','첼시부츠' UNION ALL
    SELECT 'D26SA','D26SPORT','스포츠샌들' UNION ALL SELECT 'D26SA','D26SLIDE','슬라이드' UNION ALL
    SELECT 'D26KI','D26KRUN','키즈운동화' UNION ALL SELECT 'D26KI','D26KSAND','키즈샌들'
  ) x ON c.category_code=x.parent;
  INSERT INTO products(brand_id,category_id,model_code,product_name,gender_code,product_description,price,is_active)
  SELECT b.brand_id,c.category_id,CONCAT('DEMO26-P',LPAD(d.seq,2,'0')),d.name,d.gender,
    'SHUPICK 화면 및 업무 테스트용 가상 상품입니다. 이미지와 색상은 실제 판매 상품을 보증하지 않습니다.',d.price,1
  FROM demo26_products d JOIN brands b ON b.brand_code=d.brand_code
    JOIN categories c ON c.category_code=d.category_code;
  INSERT INTO product_variants(product_id,product_code,color_code,color_name,size_mm,additional_price,is_active)
  SELECT p.product_id,CONCAT(p.model_code,'-',co.code,'-',sz.mm),co.code,co.name,sz.mm,0,1
  FROM demo26_products d JOIN products p ON p.model_code=CONCAT('DEMO26-P',LPAD(d.seq,2,'0'))
  CROSS JOIN (SELECT 'WH' code,'화이트' name UNION ALL SELECT 'BK','블랙') co
  JOIN (
    SELECT 'M' gender,250 mm UNION ALL SELECT 'M',255 UNION ALL SELECT 'M',260 UNION ALL SELECT 'M',265 UNION ALL SELECT 'M',270 UNION ALL
    SELECT 'W',230 UNION ALL SELECT 'W',235 UNION ALL SELECT 'W',240 UNION ALL SELECT 'W',245 UNION ALL SELECT 'W',250 UNION ALL
    SELECT 'U',240 UNION ALL SELECT 'U',245 UNION ALL SELECT 'U',250 UNION ALL SELECT 'U',255 UNION ALL SELECT 'U',260 UNION ALL
    SELECT 'K',180 UNION ALL SELECT 'K',185 UNION ALL SELECT 'K',190 UNION ALL SELECT 'K',195 UNION ALL SELECT 'K',200
  ) sz ON sz.gender=d.gender;
  INSERT INTO product_images(product_id,color_code,image_url,sort_order,is_primary)
  SELECT p.product_id,co.code,d.image_url,0,1 FROM demo26_products d
    JOIN products p ON p.model_code=CONCAT('DEMO26-P',LPAD(d.seq,2,'0'))
    CROSS JOIN (SELECT 'WH' code UNION ALL SELECT 'BK') co;
  -- 200 normal SKUs (40 units), 20 low-stock SKUs (3 units), 20 sold-out SKUs (0 units).
  INSERT INTO headquarters_inventory(product_variant_id,on_hand_quantity,reserved_quantity,defective_quantity)
  SELECT v.product_variant_id,CASE WHEN d.seq<=20 THEN 40 WHEN d.seq<=22 THEN 3 ELSE 0 END,0,0
  FROM demo26_products d JOIN products p ON p.model_code=CONCAT('DEMO26-P',LPAD(d.seq,2,'0'))
    JOIN product_variants v ON v.product_id=p.product_id;
  INSERT INTO inventory_policies(product_variant_id,initial_stock_quantity,reorder_threshold_percent,reorder_quantity)
  SELECT v.product_variant_id,40,30,20 FROM product_variants v JOIN products p ON p.product_id=v.product_id
    WHERE p.model_code LIKE 'DEMO26-P%';
  INSERT INTO inventory_movements(product_variant_id,movement_type,on_hand_delta,on_hand_after,reserved_after,defective_after,idempotency_key,reason,created_at)
  SELECT hi.product_variant_id,'INITIAL_STOCK',hi.on_hand_quantity,hi.on_hand_quantity,0,0,
    CONCAT('DEMO26-initial-',hi.product_variant_id),'DEMO26 가상 초기 재고',DATE_SUB(v_now,INTERVAL 30 DAY)
  FROM headquarters_inventory hi JOIN product_variants v ON v.product_variant_id=hi.product_variant_id
    JOIN products p ON p.product_id=v.product_id WHERE p.model_code LIKE 'DEMO26-P%' AND hi.on_hand_quantity>0;

  CREATE TEMPORARY TABLE demo26_customers(seq INT PRIMARY KEY,customer_id BIGINT UNSIGNED NOT NULL);
  WHILE n<=12 DO
    IF n=1 AND p_customer_uid IS NOT NULL THEN
      SELECT customer_id INTO v_customer FROM customers WHERE firebase_uid=p_customer_uid AND deleted_at IS NULL;
    ELSE
      INSERT INTO customers(firebase_uid,email,customer_name,birth_date) VALUES
        (CONCAT('DEMO26-C',LPAD(n,2,'0')),CONCAT('demo26-c',LPAD(n,2,'0'),'@example.invalid'),
         CONCAT('테스트 고객 ',LPAD(n,2,'0')),DATE_ADD('1990-01-01',INTERVAL n YEAR));
      SET v_customer=LAST_INSERT_ID();
    END IF;
    INSERT INTO demo26_customers VALUES(n,v_customer);
    INSERT INTO point_wallets(customer_id,point_balance) VALUES(v_customer,0)
      ON DUPLICATE KEY UPDATE point_balance=point_balance;
    SET n=n+1;
  END WHILE;

  CREATE TEMPORARY TABLE demo26_orders(seq INT PRIMARY KEY,order_id BIGINT UNSIGNED NOT NULL,order_item_id BIGINT UNSIGNED NOT NULL);
  SET n=1;
  WHILE n<=36 DO
    SELECT customer_id INTO v_customer FROM demo26_customers WHERE seq=1+MOD(n-1,12);
    SELECT branch_id INTO v_branch FROM branches WHERE branch_code=IF(MOD(n,2)=1,'SEL-SD','SEL-GN');
    SELECT p.product_id,v.product_variant_id,p.price INTO v_product,v_variant,v_price
      FROM products p JOIN product_variants v ON v.product_id=p.product_id
      WHERE p.model_code=CONCAT('DEMO26-P',LPAD(1+MOD(n-1,18),2,'0'))
        AND v.color_code=IF(n<=18,'WH','BK')
        AND v.size_mm=CASE p.gender_code WHEN 'M' THEN 260 WHEN 'W' THEN 240 WHEN 'K' THEN 190 ELSE 250 END;
    SET v_state=CASE WHEN n<=6 THEN 'PREPARING' WHEN n<=12 THEN 'SHIPPING'
                     WHEN n<=18 THEN 'READY_FOR_PICKUP' ELSE 'COMPLETED' END;
    SET v_fstate=CASE WHEN n<=6 THEN 'PREPARING' WHEN n<=12 THEN 'IN_TRANSIT'
                     WHEN n<=18 THEN 'READY_FOR_PICKUP' ELSE 'COMPLETED' END;
    SET v_pstate=CASE WHEN n<=12 THEN 'PREPARING' WHEN n<=18 THEN 'READY_FOR_PICKUP' ELSE 'COMPLETED' END;
    SET v_ordered=DATE_SUB(v_now,INTERVAL (3+MOD(n,20)) DAY);
    INSERT INTO orders(order_number,order_request_key,customer_id,pickup_branch_id,fulfillment_type,
      order_status,subtotal_amount,paid_total,ordered_at,purchase_confirmed_at)
    VALUES(CONCAT('DEMO26-O',LPAD(n,3,'0')),CONCAT('DEMO26-request-',n),v_customer,v_branch,'PICKUP',
      v_state,v_price,v_price,v_ordered,IF(n BETWEEN 19 AND 30,DATE_SUB(v_now,INTERVAL 12 HOUR),NULL));
    SET v_order=LAST_INSERT_ID();
    INSERT INTO order_items(order_id,product_variant_id,product_name,product_code,color_name,size_mm,unit_price,quantity)
    SELECT v_order,v.product_variant_id,p.product_name,v.product_code,v.color_name,v.size_mm,v_price,1
      FROM product_variants v JOIN products p ON p.product_id=v.product_id WHERE v.product_variant_id=v_variant;
    SET v_item=LAST_INSERT_ID();
    INSERT INTO demo26_orders VALUES(n,v_order,v_item);
    INSERT INTO payments(order_id,payment_method,payment_status,payment_amount,transaction_key,paid_at)
      VALUES(v_order,'CARD','PAID',v_price,CONCAT('DEMO26-payment-',n),v_ordered);
    INSERT INTO fulfillments(fulfillment_number,order_id,destination_branch_id,fulfillment_status,tracking_number,
      shipped_at,arrived_at,inspected_at,completed_at,created_at)
    VALUES(CONCAT('DEMO26-F',LPAD(n,3,'0')),v_order,v_branch,v_fstate,
      IF(n>6,CONCAT('DEMO26-TRACK-',n),NULL),
      IF(n>6,DATE_SUB(v_now,INTERVAL 2 DAY),NULL),
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>18,DATE_SUB(v_now,INTERVAL 1 DAY),NULL),v_ordered);
    SET v_fulfillment=LAST_INSERT_ID();
    INSERT INTO fulfillment_items(fulfillment_id,order_id,order_item_id,quantity) VALUES(v_fulfillment,v_order,v_item,1);
    SET v_fitem=LAST_INSERT_ID();
    INSERT INTO pickups(order_id,pickup_retention_policy_id,branch_id,pickup_status,arrived_at,ready_at,pickup_deadline_at,picked_up_at)
    VALUES(v_order,v_pickup_policy,v_branch,v_pstate,
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>12,DATE_ADD(DATE_SUB(v_now,INTERVAL 36 HOUR),INTERVAL v_hold_days DAY),NULL),
      IF(n>18,DATE_SUB(v_now,INTERVAL 1 DAY),NULL));
    SET v_pickup=LAST_INSERT_ID();
    INSERT INTO pickup_holdings(fulfillment_item_id,branch_id,holding_status,quantity,received_at,ready_at,picked_up_at)
    VALUES(v_fitem,v_branch,CASE WHEN n<=12 THEN 'AWAITING_ARRIVAL' WHEN n<=18 THEN 'READY_FOR_PICKUP' ELSE 'PICKED_UP' END,1,
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>12,DATE_SUB(v_now,INTERVAL 36 HOUR),NULL),
      IF(n>18,DATE_SUB(v_now,INTERVAL 1 DAY),NULL));
    INSERT INTO inventory_reservations(order_id,order_item_id,product_variant_id,reserved_quantity,reservation_status,expires_at,consumed_at,created_at)
    VALUES(v_order,v_item,v_variant,1,IF(n<=6,'RESERVED','CONSUMED'),DATE_ADD(v_now,INTERVAL 7 DAY),
      IF(n>6,DATE_SUB(v_now,INTERVAL 2 DAY),NULL),v_ordered);
    UPDATE headquarters_inventory SET reserved_quantity=reserved_quantity+1 WHERE product_variant_id=v_variant;
    INSERT INTO inventory_movements(product_variant_id,movement_type,reserved_delta,on_hand_after,reserved_after,
      defective_after,reference_type,reference_id,idempotency_key,reason,created_at)
    SELECT v_variant,'ORDER_RESERVATION',1,on_hand_quantity,reserved_quantity,defective_quantity,'ORDER',v_order,
      CONCAT('DEMO26-reserve-',n),'DEMO26 주문 예약',v_ordered FROM headquarters_inventory WHERE product_variant_id=v_variant;
    IF n>6 THEN
      UPDATE headquarters_inventory SET on_hand_quantity=on_hand_quantity-1,reserved_quantity=reserved_quantity-1
        WHERE product_variant_id=v_variant;
      INSERT INTO inventory_movements(product_variant_id,movement_type,on_hand_delta,reserved_delta,on_hand_after,
        reserved_after,defective_after,reference_type,reference_id,idempotency_key,reason,created_at)
      SELECT v_variant,'ORDER_SHIPMENT',-1,-1,on_hand_quantity,reserved_quantity,defective_quantity,'ORDER',v_order,
        CONCAT('DEMO26-ship-',n),'DEMO26 가상 출고',DATE_SUB(v_now,INTERVAL 2 DAY)
        FROM headquarters_inventory WHERE product_variant_id=v_variant;
    END IF;
    -- Import snapshots, explicitly marked SYSTEM; do not impersonate employee actions.
    INSERT INTO order_status_history(order_id,new_status,change_source,change_reason,actor_type,changed_at)
      VALUES(v_order,v_state,'DEMO_SEED','DEMO26 초기 상태 스냅샷','SYSTEM',v_now);
    INSERT INTO fulfillment_status_history(fulfillment_id,new_status,change_source,change_reason,actor_type,changed_at)
      VALUES(v_fulfillment,v_fstate,'DEMO_SEED','DEMO26 초기 상태 스냅샷','SYSTEM',v_now);
    INSERT INTO pickup_status_history(pickup_id,new_status,change_source,change_reason,actor_type,changed_at)
      VALUES(v_pickup,v_pstate,'DEMO_SEED','DEMO26 초기 상태 스냅샷','SYSTEM',v_now);

    IF n BETWEEN 19 AND 30 THEN
      INSERT INTO reviews(order_item_id,customer_id,rating,review_content,fit_size,fit_width,fit_comfort,created_at)
      VALUES(v_item,v_customer,IF(MOD(n,3)=0,4,5),
        CASE MOD(n,3) WHEN 0 THEN '색상이 예쁘고 출퇴근할 때 신기 좋습니다.'
          WHEN 1 THEN '정사이즈로 잘 맞고 오래 걸어도 발이 편했습니다.'
          ELSE '매장에서 빠르게 수령했습니다. 가벼워서 만족합니다.' END,
        '정사이즈','적당함','편함',DATE_SUB(v_now,INTERVAL 6 HOUR));
      SET v_review=LAST_INSERT_ID();
      SELECT point_balance INTO v_balance FROM point_wallets WHERE customer_id=v_customer FOR UPDATE;
      INSERT INTO point_transactions(customer_id,transaction_type,point_amount,balance_after,order_id,review_id,
        idempotency_key,description,expires_at,created_at)
      VALUES(v_customer,'EARN',1000,v_balance+1000,v_order,v_review,CONCAT('review-reward-',v_item),
        'DEMO26 리뷰 최초 작성 적립',DATE_ADD(v_now,INTERVAL 1 YEAR),DATE_SUB(v_now,INTERVAL 6 HOUR));
      SET v_transaction=LAST_INSERT_ID();
      INSERT INTO point_lots(customer_id,source_transaction_id,original_amount,remaining_amount,earned_at,expires_at,lot_status)
      VALUES(v_customer,v_transaction,1000,1000,DATE_SUB(v_now,INTERVAL 6 HOUR),DATE_ADD(v_now,INTERVAL 1 YEAR),'AVAILABLE');
      UPDATE point_wallets SET point_balance=v_balance+1000 WHERE customer_id=v_customer;
    END IF;
    IF n>=31 THEN
      INSERT INTO return_requests(order_id,customer_id,return_policy_id,branch_id,return_reason_code,request_status,
        return_reason,return_deadline_at,requested_at)
      VALUES(v_order,v_customer,v_return_policy,v_branch,
        CASE MOD(n,3) WHEN 0 THEN 'CUSTOMER_CHANGE' WHEN 1 THEN 'PRODUCT_DEFECT' ELSE 'WRONG_ITEM' END,
        'REQUESTED',CASE MOD(n,3) WHEN 0 THEN '미착용 상태이며 사이즈 교환 대신 반품을 요청합니다.'
          WHEN 1 THEN '봉제 부분 불량이 의심되어 본사 검수를 요청합니다.'
          ELSE '주문한 옵션과 다른 상품이 도착하여 확인을 요청합니다.' END,
        DATE_ADD(DATE_SUB(v_now,INTERVAL 1 DAY),INTERVAL v_return_days DAY),DATE_SUB(v_now,INTERVAL 3 HOUR));
      SET v_return=LAST_INSERT_ID();
      INSERT INTO return_items(return_request_id,order_item_id,quantity) VALUES(v_return,v_item,1);
    END IF;
    SET n=n+1;
  END WHILE;

  -- 12 inquiries: 8 unanswered and 4 answered, including customer/product/order topics.
  INSERT INTO inquiries(customer_id,product_id,inquiry_type,title,inquiry_content,inquiry_status,created_at)
  SELECT c.customer_id,p.product_id,CASE MOD(c.seq,3) WHEN 0 THEN '상품 문의' WHEN 1 THEN '주문 문의' ELSE '반품 문의' END,
    CONCAT('[DEMO26] ',CASE MOD(c.seq,3) WHEN 0 THEN '재입고 일정이 궁금합니다'
      WHEN 1 THEN '대리점 수령일을 확인해주세요' ELSE '반품 준비물을 알려주세요' END),
    '테스트 문의입니다. 재고, 수령 절차 또는 반품 정책에 대한 안내를 부탁드립니다.',
    IF(c.seq<=8,'OPEN','ANSWERED'),DATE_SUB(v_now,INTERVAL c.seq HOUR)
  FROM demo26_customers c JOIN products p ON p.model_code=CONCAT('DEMO26-P',LPAD(c.seq,2,'0'));
  INSERT INTO inquiry_responses(inquiry_id,employee_id,response_content,responded_at)
  SELECT i.inquiry_id,v_support,'[DEMO26 예시 답변] 수령 시 주문번호를 준비해주세요. 반품은 미착용·포장 유지 조건을 확인해주세요.',
    DATE_SUB(v_now,INTERVAL 1 HOUR)
  FROM inquiries i JOIN demo26_customers c ON c.customer_id=i.customer_id
    WHERE i.title LIKE '[DEMO26]%' AND i.inquiry_status='ANSWERED';

  -- 6 procurement requests: 2 drafts, 2 waiting for team lead, 2 waiting for director.
  SET n=1;
  WHILE n<=6 DO
    SELECT branch_id INTO v_branch FROM branches WHERE branch_code=IF(MOD(n,2)=1,'SEL-SD','SEL-GN');
    SET v_state=CASE WHEN n<=2 THEN 'DRAFT' WHEN n<=4 THEN 'PENDING_TEAM_LEAD' ELSE 'PENDING_DIRECTOR' END;
    INSERT INTO purchase_requisitions(requested_by_employee_id,branch_id,approval_workflow_id,title,reason,requisition_status,submitted_at,created_at)
    VALUES(v_requester,v_branch,v_workflow,CONCAT('[DEMO26] 재고 보충 요청 ',n),
      '품절 또는 재고 부족 옵션을 보충하기 위한 테스트 발주입니다.',v_state,
      IF(n>2,DATE_SUB(v_now,INTERVAL 4 HOUR),NULL),DATE_SUB(v_now,INTERVAL 5 HOUR));
    SET v_requisition=LAST_INSERT_ID();
    INSERT INTO purchase_requisition_items(purchase_requisition_id,product_variant_id,requested_quantity)
    SELECT v_requisition,v.product_variant_id,20 FROM products p JOIN product_variants v ON v.product_id=p.product_id
    WHERE p.model_code=CONCAT('DEMO26-P',LPAD(21+MOD(n-1,4),2,'0')) AND v.color_code IN ('WH','BK')
      AND v.size_mm=CASE p.gender_code WHEN 'M' THEN 260 WHEN 'W' THEN 240 WHEN 'K' THEN 190 ELSE 250 END;
    IF n>2 THEN
      INSERT INTO purchase_approvals(purchase_requisition_id,approval_sequence,required_role_id,approver_employee_id,
        approval_status,approval_comment,decided_at)
      SELECT v_requisition,s.step_order,s.required_role_id,
        IF(n>4 AND s.step_order=1,v_lead,NULL),
        IF(n>4 AND s.step_order=1,'APPROVED','PENDING'),
        IF(n>4 AND s.step_order=1,'DEMO26 가상 팀장 승인 이력',NULL),
        IF(n>4 AND s.step_order=1,DATE_SUB(v_now,INTERVAL 2 HOUR),NULL)
      FROM approval_workflow_steps s WHERE s.approval_workflow_id=v_workflow;
    END IF;
    SET n=n+1;
  END WHILE;
  INSERT INTO restock_subscriptions(customer_id,product_variant_id)
  SELECT c.customer_id,v.product_variant_id FROM demo26_customers c
    JOIN products p ON p.model_code=CONCAT('DEMO26-P',LPAD(23+MOD(c.seq,2),2,'0'))
    JOIN product_variants v ON v.product_id=p.product_id AND v.color_code='WH' AND v.size_mm=190
    WHERE c.seq<=6;

  -- Integrity gates: failures roll back all InnoDB business rows.
  -- MySQL 1137: reference each temporary table only once per statement.
  IF (SELECT COUNT(*) FROM reviews r JOIN demo26_orders d ON d.order_item_id=r.order_item_id)<>12 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 review count does not match.';
  END IF;
  IF (SELECT COUNT(*) FROM return_requests r JOIN demo26_orders d ON d.order_id=r.order_id)<>6 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 return count does not match.';
  END IF;
  IF EXISTS(SELECT 1 FROM demo26_orders d JOIN orders o ON o.order_id=d.order_id
    JOIN order_items oi ON oi.order_id=o.order_id WHERE o.subtotal_amount<>oi.line_total) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 order totals do not match.';
  END IF;
  IF (SELECT COUNT(*) FROM products WHERE model_code LIKE 'DEMO26-P%')<>24
     OR (SELECT COUNT(*) FROM product_variants v JOIN products p ON p.product_id=v.product_id WHERE p.model_code LIKE 'DEMO26-P%')<>240
     OR (SELECT COUNT(*) FROM orders WHERE order_number LIKE 'DEMO26-O%')<>36
     OR (SELECT COUNT(*) FROM purchase_requisitions WHERE title LIKE '[DEMO26]%')<>6
     OR EXISTS(SELECT 1 FROM headquarters_inventory h JOIN product_variants v ON v.product_variant_id=h.product_variant_id
       JOIN products p ON p.product_id=v.product_id WHERE p.model_code LIKE 'DEMO26-P%'
       AND h.reserved_quantity<>(SELECT COALESCE(SUM(r.reserved_quantity),0) FROM inventory_reservations r
         WHERE r.product_variant_id=h.product_variant_id AND r.reservation_status='RESERVED')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 counts, order totals, or inventory reservations do not match.';
  END IF;
  IF EXISTS(
    SELECT 1 FROM headquarters_inventory h JOIN product_variants v ON v.product_variant_id=h.product_variant_id
    JOIN products p ON p.product_id=v.product_id
    LEFT JOIN (SELECT product_variant_id,SUM(on_hand_delta) on_hand,SUM(reserved_delta) reserved,
      SUM(defective_delta) defective FROM inventory_movements GROUP BY product_variant_id) m
      ON m.product_variant_id=h.product_variant_id
    WHERE p.model_code LIKE 'DEMO26-P%' AND
      (h.on_hand_quantity<>COALESCE(m.on_hand,0) OR h.reserved_quantity<>COALESCE(m.reserved,0)
       OR h.defective_quantity<>COALESCE(m.defective,0))
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DEMO26 inventory ledger does not match inventory balances.';
  END IF;
  COMMIT;
  SELECT 'DEMO26 committed' AS result,24 AS products,240 AS variants,36 AS orders,12 AS reviews,6 AS returns,6 AS requisitions;
  SELECT c.seq,c.customer_id,e.customer_name,e.firebase_uid FROM demo26_customers c JOIN customers e ON e.customer_id=c.customer_id ORDER BY c.seq;
  SELECT e.employee_code AS procurement_requester FROM employees e WHERE e.employee_id=v_requester;
  DROP TEMPORARY TABLE demo26_products, demo26_customers, demo26_orders;
END$$
DELIMITER ;

CALL shupick_load_demo_20261005(@shupick_demo_apply,@shupick_demo_customer_uid);
DROP PROCEDURE IF EXISTS shupick_load_demo_20261005;
