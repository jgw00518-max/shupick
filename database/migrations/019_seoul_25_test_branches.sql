-- Seoul district demo branches. Run against the existing shupick_v2 schema.
-- Addresses, phone numbers, and opening hours below are TEST DATA, not real stores.
-- Replace them and verify each location before using these branches for real pickup.
-- Existing Gangnam and Seongdong addresses, numbers, and coordinates are preserved.
-- Re-running this file does not create another branch in a district or duplicate hours.

USE `shupick_v2`;
START TRANSACTION;

-- The original seed still uses the former brand name.
UPDATE `branches`
SET `branch_name` = 'SHOEPICK 성동점'
WHERE `branch_code` = 'SEL-SD' AND `branch_name` = 'SOLE 성동점';

INSERT INTO `branches`
  (`branch_code`, `branch_name`, `district_code`, `address`, `phone`, `latitude`, `longitude`, `is_active`)
SELECT s.`branch_code`, s.`branch_name`, s.`district_code`, s.`address`, '02-0000-0000', NULL, NULL, TRUE
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
  SELECT 1 FROM `branches` AS b WHERE b.`district_code` = s.`district_code`
);

-- Fill missing demo hours only; preserve hours already set for an existing branch.
-- Monday-Saturday 10:30-20:00, Sunday closed.
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
  SELECT 1 FROM `branch_business_hours` AS existing
  WHERE existing.`branch_id` = b.`branch_id`
    AND existing.`day_of_week` = d.`day_of_week`
);

COMMIT;

SELECT `district_code`, `branch_code`, `branch_name`, `address`, `phone`, `is_active`
FROM `branches`
WHERE `district_code` LIKE 'SEOUL-%'
ORDER BY `district_code`, `branch_id`;
