-- Update the 23 demo branches created after Gangnam and Seongdong.
-- Addresses, telephone numbers and coordinates are synthetic TEST DATA.
-- Coordinates are randomly offset near each district center; they are not store locations.
-- Stable branch_code is used instead of branch_id so teammates can apply this file too.
USE `shupick_v2`;
START TRANSACTION;

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

SELECT branch_id, branch_code, district_code, address, phone, latitude, longitude
FROM `branches`
WHERE branch_code IN ('SEL-GANGDONG', 'SEL-GANGBUK', 'SEL-GANGSEO', 'SEL-GWANAK', 'SEL-GWANGJIN', 'SEL-GURO', 'SEL-GEUMCHEON', 'SEL-NOWON', 'SEL-DOBONG', 'SEL-DONGDAEMUN', 'SEL-DONGJAK', 'SEL-MAPO', 'SEL-SEODAEMUN', 'SEL-SEOCHO', 'SEL-SEONGBUK', 'SEL-SONGPA', 'SEL-YANGCHEON', 'SEL-YEONGDEUNGPO', 'SEL-YONGSAN', 'SEL-EUNPYEONG', 'SEL-JONGNO', 'SEL-JUNG', 'SEL-JUNGNANG')
ORDER BY branch_id;
