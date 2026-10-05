-- Team data delta since the original single-Seongdong-branch setup.
-- Prerequisite: shupick_v2 schema/seed and migrations 001 through 017 are applied.
-- Migration 018 and the earlier branch-only file 019 are NOT required: their
-- relevant data is included here. Do not re-run schema/seed on an existing DB.
-- This file includes the Gangnam branch and two Firebase-linked staff members,
-- all 25 Seoul district demo branches, and missing demo business hours.
-- It does not create Firebase Authentication users. Use the same Firebase project
-- and create/link the two UIDs there separately before those employees can log in.
-- All new branch addresses, phone numbers and opening hours are TEST DATA.
-- Replace them before real customer pickup. Coordinates are synthetic points
-- randomly offset near district centers, not actual store locations.
-- branch_id and employee_id are generated locally; relationships use stable codes.
-- Re-running the file skips existing districts, employees, roles and assignments.

USE `shupick_v2`;
START TRANSACTION;

INSERT INTO `roles` (`role_code`, `role_name`)
SELECT 'BRANCH_MANAGER', '대리점장'
WHERE NOT EXISTS (SELECT 1 FROM `roles` WHERE `role_code` = 'BRANCH_MANAGER');

INSERT INTO `roles` (`role_code`, `role_name`)
SELECT 'EXECUTIVE', '본사 임원'
WHERE NOT EXISTS (SELECT 1 FROM `roles` WHERE `role_code` = 'EXECUTIVE');

UPDATE `branches`
SET `branch_name` = 'SHOEPICK 성동점'
WHERE `branch_code` = 'SEL-SD' AND `branch_name` = 'SOLE 성동점';

INSERT INTO `branches`
  (`branch_code`, `branch_name`, `district_code`, `address`, `phone`, `latitude`, `longitude`, `is_active`)
SELECT 'SEL-GN', 'SHOEPICK 강남점', 'SEOUL-GANGNAM',
       '서울특별시 강남구 테스트로 40', '02-0000-0002', 37.5176000, 127.0481000, TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM `branches`
  WHERE `branch_code` = 'SEL-GN' OR `district_code` = 'SEOUL-GANGNAM'
);

-- Complete an existing Gangnam row without replacing nonempty local contact data.
UPDATE `branches`
SET `district_code` = CASE WHEN `district_code` IN ('', 'UNASSIGNED')
                           THEN 'SEOUL-GANGNAM' ELSE `district_code` END,
    `latitude` = COALESCE(`latitude`, 37.5176000),
    `longitude` = COALESCE(`longitude`, 127.0481000)
WHERE `branch_code` = 'SEL-GN';

INSERT INTO `branches`
  (`branch_code`, `branch_name`, `district_code`, `address`, `phone`, `latitude`, `longitude`, `is_active`)
SELECT s.`branch_code`, s.`branch_name`, s.`district_code`, s.`address`,
       '02-0000-0000', NULL, NULL, TRUE
FROM (
  SELECT 'SEL-GANGDONG' AS `branch_code`, 'SHOEPICK 강동점' AS `branch_name`, 'SEOUL-GANGDONG' AS `district_code`, '서울특별시 강동구 (테스트 지점)' AS `address`
  UNION ALL SELECT 'SEL-GANGBUK', 'SHOEPICK 강북점', 'SEOUL-GANGBUK', '서울특별시 강북구 (테스트 지점)'
  UNION ALL SELECT 'SEL-GANGSEO', 'SHOEPICK 강서점', 'SEOUL-GANGSEO', '서울특별시 강서구 (테스트 지점)'
  UNION ALL SELECT 'SEL-GWANAK', 'SHOEPICK 관악점', 'SEOUL-GWANAK', '서울특별시 관악구 (테스트 지점)'
  UNION ALL SELECT 'SEL-GWANGJIN', 'SHOEPICK 광진점', 'SEOUL-GWANGJIN', '서울특별시 광진구 (테스트 지점)'
  UNION ALL SELECT 'SEL-GURO', 'SHOEPICK 구로점', 'SEOUL-GURO', '서울특별시 구로구 (테스트 지점)'
  UNION ALL SELECT 'SEL-GEUMCHEON', 'SHOEPICK 금천점', 'SEOUL-GEUMCHEON', '서울특별시 금천구 (테스트 지점)'
  UNION ALL SELECT 'SEL-NOWON', 'SHOEPICK 노원점', 'SEOUL-NOWON', '서울특별시 노원구 (테스트 지점)'
  UNION ALL SELECT 'SEL-DOBONG', 'SHOEPICK 도봉점', 'SEOUL-DOBONG', '서울특별시 도봉구 (테스트 지점)'
  UNION ALL SELECT 'SEL-DONGDAEMUN', 'SHOEPICK 동대문점', 'SEOUL-DONGDAEMUN', '서울특별시 동대문구 (테스트 지점)'
  UNION ALL SELECT 'SEL-DONGJAK', 'SHOEPICK 동작점', 'SEOUL-DONGJAK', '서울특별시 동작구 (테스트 지점)'
  UNION ALL SELECT 'SEL-MAPO', 'SHOEPICK 마포점', 'SEOUL-MAPO', '서울특별시 마포구 (테스트 지점)'
  UNION ALL SELECT 'SEL-SEODAEMUN', 'SHOEPICK 서대문점', 'SEOUL-SEODAEMUN', '서울특별시 서대문구 (테스트 지점)'
  UNION ALL SELECT 'SEL-SEOCHO', 'SHOEPICK 서초점', 'SEOUL-SEOCHO', '서울특별시 서초구 (테스트 지점)'
  UNION ALL SELECT 'SEL-SEONGBUK', 'SHOEPICK 성북점', 'SEOUL-SEONGBUK', '서울특별시 성북구 (테스트 지점)'
  UNION ALL SELECT 'SEL-SONGPA', 'SHOEPICK 송파점', 'SEOUL-SONGPA', '서울특별시 송파구 (테스트 지점)'
  UNION ALL SELECT 'SEL-YANGCHEON', 'SHOEPICK 양천점', 'SEOUL-YANGCHEON', '서울특별시 양천구 (테스트 지점)'
  UNION ALL SELECT 'SEL-YEONGDEUNGPO', 'SHOEPICK 영등포점', 'SEOUL-YEONGDEUNGPO', '서울특별시 영등포구 (테스트 지점)'
  UNION ALL SELECT 'SEL-YONGSAN', 'SHOEPICK 용산점', 'SEOUL-YONGSAN', '서울특별시 용산구 (테스트 지점)'
  UNION ALL SELECT 'SEL-EUNPYEONG', 'SHOEPICK 은평점', 'SEOUL-EUNPYEONG', '서울특별시 은평구 (테스트 지점)'
  UNION ALL SELECT 'SEL-JONGNO', 'SHOEPICK 종로점', 'SEOUL-JONGNO', '서울특별시 종로구 (테스트 지점)'
  UNION ALL SELECT 'SEL-JUNG', 'SHOEPICK 중구점', 'SEOUL-JUNG', '서울특별시 중구 (테스트 지점)'
  UNION ALL SELECT 'SEL-JUNGNANG', 'SHOEPICK 중랑점', 'SEOUL-JUNGNANG', '서울특별시 중랑구 (테스트 지점)'
) AS s
WHERE NOT EXISTS (
  SELECT 1 FROM `branches` AS b
  WHERE b.`district_code` = s.`district_code` OR b.`branch_code` = s.`branch_code`
);

-- Preserve any hours already entered by a teammate; fill missing days only.
-- Demo schedule: Monday-Saturday 10:30-20:00, Sunday closed.
INSERT INTO `branch_business_hours`
  (`branch_id`, `day_of_week`, `opens_at`, `closes_at`, `is_closed`)
SELECT b.`branch_id`, d.`day_of_week`,
       CASE WHEN d.`day_of_week` = 7 THEN NULL ELSE '10:30:00' END,
       CASE WHEN d.`day_of_week` = 7 THEN NULL ELSE '20:00:00' END,
       d.`day_of_week` = 7
FROM `branches` AS b
CROSS JOIN (
  SELECT 1 AS `day_of_week` UNION ALL SELECT 2 UNION ALL SELECT 3
  UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
) AS d
WHERE b.`district_code` IN (
  'SEOUL-GANGNAM', 'SEOUL-GANGDONG', 'SEOUL-GANGBUK', 'SEOUL-GANGSEO',
  'SEOUL-GWANAK', 'SEOUL-GWANGJIN', 'SEOUL-GURO', 'SEOUL-GEUMCHEON',
  'SEOUL-NOWON', 'SEOUL-DOBONG', 'SEOUL-DONGDAEMUN', 'SEOUL-DONGJAK',
  'SEOUL-MAPO', 'SEOUL-SEODAEMUN', 'SEOUL-SEOCHO', 'SEOUL-SEONGDONG',
  'SEOUL-SEONGBUK', 'SEOUL-SONGPA', 'SEOUL-YANGCHEON', 'SEOUL-YEONGDEUNGPO',
  'SEOUL-YONGSAN', 'SEOUL-EUNPYEONG', 'SEOUL-JONGNO', 'SEOUL-JUNG',
  'SEOUL-JUNGNANG'
)
AND NOT EXISTS (
  SELECT 1 FROM `branch_business_hours` AS h
  WHERE h.`branch_id` = b.`branch_id` AND h.`day_of_week` = d.`day_of_week`
);

INSERT INTO `employees`
  (`firebase_uid`, `employee_code`, `employee_name`, `department`, `position`, `is_active`)
SELECT 'wUTqNVwxkwcu0zbrZxivaQWIP8j2', 'EMP-GN-0001',
       '강남 대리점 직원', '대리점', '직원', TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM `employees`
  WHERE `firebase_uid` = 'wUTqNVwxkwcu0zbrZxivaQWIP8j2'
     OR `employee_code` = 'EMP-GN-0001'
);

INSERT INTO `employees`
  (`firebase_uid`, `employee_code`, `employee_name`, `department`, `position`, `is_active`)
SELECT 'ifuqvLFdD5SKPq89fnsHQfMcMcD3', 'EMP-GN-0002',
       '강남 대리점장', '대리점', '대리점장', TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM `employees`
  WHERE `firebase_uid` = 'ifuqvLFdD5SKPq89fnsHQfMcMcD3'
     OR `employee_code` = 'EMP-GN-0002'
);

INSERT INTO `employee_branch_assignments` (`employee_id`, `branch_id`)
SELECT e.`employee_id`, b.`branch_id`
FROM `employees` AS e
JOIN `branches` AS b ON b.`branch_code` = 'SEL-GN'
WHERE (
  (e.`employee_code` = 'EMP-GN-0001' AND e.`firebase_uid` = 'wUTqNVwxkwcu0zbrZxivaQWIP8j2')
  OR (e.`employee_code` = 'EMP-GN-0002' AND e.`firebase_uid` = 'ifuqvLFdD5SKPq89fnsHQfMcMcD3')
)
AND NOT EXISTS (
  SELECT 1 FROM `employee_branch_assignments` AS a
  WHERE a.`employee_id` = e.`employee_id`
    AND a.`branch_id` = b.`branch_id` AND a.`ended_at` IS NULL
);

INSERT INTO `employee_roles` (`employee_id`, `role_id`)
SELECT e.`employee_id`, r.`role_id`
FROM `employees` AS e
JOIN `roles` AS r ON
  (e.`employee_code` = 'EMP-GN-0001' AND r.`role_code` = 'BRANCH_STAFF')
  OR (e.`employee_code` = 'EMP-GN-0002' AND r.`role_code` = 'BRANCH_MANAGER')
WHERE (
  (e.`employee_code` = 'EMP-GN-0001' AND e.`firebase_uid` = 'wUTqNVwxkwcu0zbrZxivaQWIP8j2')
  OR (e.`employee_code` = 'EMP-GN-0002' AND e.`firebase_uid` = 'ifuqvLFdD5SKPq89fnsHQfMcMcD3')
)
AND NOT EXISTS (
  SELECT 1 FROM `employee_roles` AS er
  WHERE er.`employee_id` = e.`employee_id` AND er.`role_id` = r.`role_id`
);

-- Fixed synthetic contact details and random nearby district coordinates.
-- Kept in this consolidated file so teammates only need one data-delta script.
UPDATE `branches` AS b
JOIN (
  SELECT 'SEL-GANGDONG' AS branch_code, '서울특별시 강동구 테스트로 95' AS address, '02-0000-0095' AS phone, 37.5301451 AS latitude, 127.1233993 AS longitude
  UNION ALL SELECT 'SEL-GANGBUK', '서울특별시 강북구 테스트로 40', '02-0000-0040', 37.6393291, 127.0256719
  UNION ALL SELECT 'SEL-GANGSEO', '서울특별시 강서구 테스트로 12', '02-0000-0012', 37.5505417, 126.8493161
  UNION ALL SELECT 'SEL-GWANAK', '서울특별시 관악구 테스트로 44', '02-0000-0044', 37.4784660, 126.9515104
  UNION ALL SELECT 'SEL-GWANGJIN', '서울특별시 광진구 테스트로 14', '02-0000-0014', 37.5386002, 127.0830378
  UNION ALL SELECT 'SEL-GURO', '서울특별시 구로구 테스트로 36', '02-0000-0036', 37.4951708, 126.8874441
  UNION ALL SELECT 'SEL-GEUMCHEON', '서울특별시 금천구 테스트로 29', '02-0000-0029', 37.4562350, 126.8951977
  UNION ALL SELECT 'SEL-NOWON', '서울특별시 노원구 테스트로 46', '02-0000-0046', 37.6543340, 127.0568821
  UNION ALL SELECT 'SEL-DOBONG', '서울특별시 도봉구 테스트로 24', '02-0000-0024', 37.6688300, 127.0466527
  UNION ALL SELECT 'SEL-DONGDAEMUN', '서울특별시 동대문구 테스트로 85', '02-0000-0085', 37.5744381, 127.0397953
  UNION ALL SELECT 'SEL-DONGJAK', '서울특별시 동작구 테스트로 13', '02-0000-0013', 37.5121233, 126.9394540
  UNION ALL SELECT 'SEL-MAPO', '서울특별시 마포구 테스트로 37', '02-0000-0037', 37.5662936, 126.9013637
  UNION ALL SELECT 'SEL-SEODAEMUN', '서울특별시 서대문구 테스트로 45', '02-0000-0045', 37.5787372, 126.9367211
  UNION ALL SELECT 'SEL-SEOCHO', '서울특별시 서초구 테스트로 28', '02-0000-0028', 37.4838860, 127.0318465
  UNION ALL SELECT 'SEL-SEONGBUK', '서울특별시 성북구 테스트로 10', '02-0000-0010', 37.5899254, 127.0163920
  UNION ALL SELECT 'SEL-SONGPA', '서울특별시 송파구 테스트로 26', '02-0000-0026', 37.5148638, 127.1058674
  UNION ALL SELECT 'SEL-YANGCHEON', '서울특별시 양천구 테스트로 52', '02-0000-0052', 37.5167478, 126.8661508
  UNION ALL SELECT 'SEL-YEONGDEUNGPO', '서울특별시 영등포구 테스트로 71', '02-0000-0071', 37.5260508, 126.8957654
  UNION ALL SELECT 'SEL-YONGSAN', '서울특별시 용산구 테스트로 23', '02-0000-0023', 37.5321782, 126.9899409
  UNION ALL SELECT 'SEL-EUNPYEONG', '서울특별시 은평구 테스트로 11', '02-0000-0011', 37.6024592, 126.9291293
  UNION ALL SELECT 'SEL-JONGNO', '서울특별시 종로구 테스트로 25', '02-0000-0025', 37.5805655, 126.9824136
  UNION ALL SELECT 'SEL-JUNG', '서울특별시 중구 테스트로 56', '02-0000-0056', 37.5632883, 126.9978498
  UNION ALL SELECT 'SEL-JUNGNANG', '서울특별시 중랑구 테스트로 15', '02-0000-0015', 37.6061097, 127.0926257
) AS demo ON demo.branch_code = b.branch_code
SET b.address = demo.address,
    b.phone = demo.phone,
    b.latitude = demo.latitude,
    b.longitude = demo.longitude;

COMMIT;

-- Expected on the original baseline: 25 active Seoul districts, 25 branches,
-- 175 branch-business-hour rows across these districts, and 2 new staff members.
SELECT COUNT(*) AS `seoul_branches`, COUNT(DISTINCT `district_code`) AS `districts`
FROM `branches` WHERE `district_code` LIKE 'SEOUL-%' AND `is_active` = TRUE;
SELECT e.`employee_code`, e.`firebase_uid`, b.`branch_code`, r.`role_code`
FROM `employees` AS e
JOIN `employee_branch_assignments` AS a
  ON a.`employee_id` = e.`employee_id` AND a.`ended_at` IS NULL
JOIN `branches` AS b ON b.`branch_id` = a.`branch_id`
JOIN `employee_roles` AS er ON er.`employee_id` = e.`employee_id`
JOIN `roles` AS r ON r.`role_id` = er.`role_id`
WHERE e.`employee_code` IN ('EMP-GN-0001', 'EMP-GN-0002');
