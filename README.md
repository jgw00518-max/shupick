# SHUPICK — 고객 앱과 공통 백엔드

신발을 주문하고 선택한 대리점에서 수령하는 Flutter 시연 프로젝트입니다. 고객 앱은 FastAPI를 통해 MySQL에 접근하며 SQLite는 기기 안의 설정과 쇼핑 기록을 저장합니다. 직원 앱에서도 사용할 수 있도록 공통 백엔드의 직원 인증·업무 API를 추가했습니다. 이 저장소의 `lib/`는 고객 앱이며 직원 앱 화면 전체가 이 저장소에 구현된 것은 아닙니다.

결제·환불은 실제 결제대행사와 연결하지 않은 데모입니다. 마이그레이션에 포함된 대리점 주소·전화번호·좌표는 테스트 데이터이므로 실제 매장 정보로 사용하면 안 됩니다.

## 지금까지 반영한 변경사항

### 고객 화면과 로컬 저장

- 앱 화면의 브랜드 문구를 SHUPICK으로 변경하고 [참고 목업](https://sole-select.higgsfield.app/)에 맞춰 상품 상세 화면을 구성했습니다.
- 상품 목록·상세·구매 화면의 글자 크기를 조정해 가독성과 줄바꿈을 개선했습니다.
- 비회원 상품 탐색, 성별·분류·브랜드 필터, 정렬, 검색, 최근 본 상품, 찜, 장바구니, 색상·사이즈·수량 선택을 구현했습니다.
- SQLite로 언어·다크 모드·알림 설정, 장바구니·찜·최근 조회·검색 기록과 상품 캐시를 저장합니다.
- 상품 API 연결 실패 시 저장된 캐시를 이용합니다. 주문 가능 여부를 결정하는 옵션 재고는 API에서 조회합니다.
- 로그인 계정의 리뷰·문의 조회 실패가 상품 화면 전체를 막던 문제를 수정했습니다. 초기 로딩에서 이미 refreshOrders()가 처리하는 리뷰·문의 요청을 중복 실행하지 않도록 했습니다.
- Android 개발 빌드에 로컬 HTTP 연결 허용 설정을 추가했습니다.

### 고객용 FastAPI·MySQL 연동

- 상품·색상/사이즈 SKU·재고·분류·브랜드·대리점·요일별 운영시간 조회
- Firebase 로그인 후 MySQL 고객 프로필 동기화와 본인 주문 조회
- 주문 생성, 재고 예약, 데모 결제, 쿠폰·포인트 사용
- 본사 출고 → 대리점 도착 → 고객 수령 완료와 상태 변경 이력
- 주문번호를 이용한 픽업 결제 코드 표시·검증; 실제 QR 생성·스캔은 미구현
- 구매확정, 공개 리뷰·평점·구매 옵션·리뷰 사진 조회, 본인 리뷰 수정·삭제
- 리뷰 최초 작성 1,000P 적립과 회원 혜택 갱신
- 상품별 수량 선택 반품, 검수, 부분 환불, 재고 복구, 사용 포인트 복원
- 포인트 전액 사용으로 결제액이 0원인 주문의 반품·환불 처리
- 고객 문의·직원 답변·재입고 신청과 고객 행동 이벤트 저장
- 포인트 만료, 미결제 예약 만료, 월별 회원등급 산정·쿠폰팩 발급 배치

### 직원용 공통 백엔드

- Firebase UID로 활성 직원을 식별하고 MySQL 직책·권한·현재 소속 대리점을 조회합니다.
- 직원 프로필 API GET /auth/employee/me를 추가했습니다.
- 테스트 환경의 직접 가입 API POST /auth/employee/register를 추가했습니다. Firebase 계정을 만든 뒤 이름·본사/대리점 소속·직책·대리점 자치구를 전달하면 직원과 직책·지점 배정을 생성하고 즉시 활성화합니다. 현재 승인 대기 절차는 없습니다.
- BRANCH_MANAGER(대리점장), EXECUTIVE(본사 임원) 직책과 직원 이메일 필드를 추가했습니다.
- 담당 대리점 주문 조회와 픽업 코드 검증 API를 추가했습니다. 본사 직책은 전체 주문을 조회할 수 있습니다.
- 대리점 도착·수령 완료 처리에 종료되지 않은 직원 지점 배정 검사를 추가했습니다. 대리점장에게도 PICKUP_MANAGE 권한을 부여하는 마이그레이션을 추가했습니다.
- 직원 화면용 재고, 발주 품의, 문의, 고객·고객 상세, 반품, 매출 분석 조회 API를 추가했습니다.
- `GET /staff/returns?branchId=...`에 선택한 대리점 필터를 추가했습니다. 대리점 직원은 현재 소속 대리점 범위 안에서 조회하며, 회귀 테스트로 확인했습니다.

직원 직접 가입은 시연을 위한 구현입니다. 현재 클라이언트가 직책을 선택할 수 있으므로 운영 배포 전에는 직원·직책 등록을 관리자 승인 또는 초대 방식으로 제한해야 합니다.

## 저장소 구조와 데이터 역할

| 경로/저장소 | 역할 |
| --- | --- |
| lib/main.dart | Firebase 초기화와 Flutter 앱 시작 |
| lib/app/ | 저장소 조립, 화면 상태, 이동 관리 |
| lib/domain/ | 상품·주문 등의 모델과 저장소 인터페이스 |
| lib/data/ | FastAPI·Firebase·SQLite 저장소 구현과 테스트용 목업 |
| lib/presentation/ | 고객 화면, 공통 위젯, 다국어 문구 |
| backend/app/ | 고객·직원 API, 인증·권한, 거래 처리, 배치 |
| backend/tests/, test/ | 백엔드와 Flutter 테스트 |
| database/ | 원본/수정 스키마, 시드, 검증 SQL |
| database/migrations/ | 기존 DB에 적용할 추가 변경 |
| database/demo/ | 고객·직원 시연용 임시 데이터 구성안과 미적용 SQL |
| docs/integration_verification.md | 기존 시연·DB 검증 기록 |

- **MySQL shupick_v2**: 고객·직원·상품·재고·주문·결제·수령·반품·환불·리뷰·쿠폰·포인트의 서버 원본입니다. Firebase UID와 업무 프로필을 연결하며 비밀번호는 Firebase Authentication에서 관리합니다.
- **SQLite shupick.sqlite**: app_settings, cached_products, cached_product_options, recent_searches, product_views, favorites, cart_items를 정의합니다. catalog_metadata_cache, interaction_queue는 필요할 때 추가 생성합니다. 현재 로컬 쇼핑 저장소의 기본 owner_key는 guest이며 MySQL의 장바구니 테이블과 자동 동기화되지 않습니다.
- **Firebase**: 고객·직원 로그인 인증과 Firestore 상태 전달을 담당합니다. MySQL outbox_events를 orderStatuses, fulfillmentStatuses, pickupStatuses, inventoryStatuses 문서로 전달하는 코드가 있습니다. 실제 Firestore 전송·보안 규칙 배포·앱 수신 검증은 별도 작업입니다.

## 확정된 거래 정책

- 자치구당 대리점 하나를 운영하는 시연 흐름입니다. 서울 25개 자치구 코드 매핑과 테스트 대리점 데이터를 추가했지만 district_code UNIQUE 제약은 추가하지 않았습니다.
- 교환은 없습니다. 일반 반품은 수령 후 7일 이내, 미착용·훼손 없음·구성품/포장 유지가 조건이며 불량·오배송은 별도로 검수합니다.
- 구매확정 후에는 반품·환불을 할 수 없고 해당 구매 항목의 리뷰를 작성할 수 있습니다.
- 리뷰 최초 작성 시 구매 항목당 1,000P를 지급하며 적립일부터 1년 뒤 만료됩니다. 수정·삭제 후 재작성은 추가 적립하지 않습니다. 구매확정 자체에는 포인트를 지급하지 않습니다.
- 부분 반품은 결제 당시 주문 스냅샷으로 할인·포인트를 배분합니다. 해당 수량의 실제 결제액과 사용 포인트를 반환하며 이미 만료된 포인트와 부분 반품 쿠폰은 복원하지 않습니다.
- 반품 신청은 주문당 한 번이므로 신청할 상품·수량을 한 번에 선택해야 합니다.
- 검수 승인 시 정상 상품은 판매 재고, 판매 부적합 상품은 격리 재고로 입고합니다.
- 회원등급은 매월 직전 12개월 구매확정 실적으로 산정합니다.

## MySQL 준비와 마이그레이션

신규 개발용 DB는 MySQL 8.0.16 이상에서 database/shupick_schema_v2.sql, database/shupick_v2_seed.sql을 적용하고 필요한 마이그레이션을 적용합니다. **스키마 파일은 기존 테이블을 삭제하고 다시 생성하므로 데이터가 있는 DB에는 실행하지 마세요.**

기존 DB는 적용 여부를 확인해 누락된 SQL만 실행합니다. 마이그레이션 적용 이력은 자동으로 추적하지 않습니다. _validation.sql은 해당 변경 뒤에 조회 결과를 확인하는 점검 파일이며 주석의 예상 결과와 비교합니다.

| 파일/번호 | 내용 |
| --- | --- |
| 001~017 | 거래 정책, 재고·배송·수령·상태 이력, Firebase 식별자, 직원 권한, 포인트, 리뷰·문의, 0원 환불 |
| 018_staff_display_roles.sql | 대리점장·본사 임원 직책 |
| 019_seoul_25_test_branches.sql | 서울 자치구별 테스트 대리점·운영시간 |
| 020_team_delta_since_staff_setup.sql | 기존 단일 성동구 구성에서 직책·직원 연결·25개 자치구 테스트 데이터 보완 |
| 021_demo_branch_contact_coordinates.sql | 추가 테스트 대리점의 주소·전화·좌표 보완 |
| 022_staff_registration.sql | 직원 이메일과 가입용 직책 |
| 023_remove_staff_registration_approval.sql | 이전 테스트 승인 대기 테이블 제거; 기존 요청 유무 확인 필요 |
| 024_branch_manager_pickup_permission.sql | 대리점장 픽업 처리 권한 |

020은 001~017 적용을 전제로 하며 018·019의 관련 데이터를 포함합니다. 따라서 018·019를 미리 실행하는 것이 필수는 아닙니다. 022는 컬럼 추가를 포함하므로 재실행 전에 적용 여부를 확인하세요. Firebase UID를 포함한 SQL은 Firebase Authentication 계정을 생성하지 않습니다. 실제 로그인은 같은 Firebase 프로젝트의 계정 UID와 MySQL 값이 일치해야 합니다.

테스트 지점과 직원 데이터는 실제 운영 데이터로 교체해야 합니다. 개인 .env, 서비스 계정 키, 로컬 MySQL의 실제 거래 데이터는 Git 병합에 포함되지 않습니다.

## 고객·직원 시연용 MySQL 임시 데이터 초안

2026-10-05 현재 DB의 실제 컬럼과 고객·직원 API를 참고하여 임시 데이터 SQL을 작성했습니다. **실제 MySQL에 적용하지 않았습니다.**

- [전체 생성 SQL](database/demo/shupick_demo_20261005.sql)
- [데이터 구성·업무 시나리오·적용 절차](database/demo/README.md)

| 구성 | 수량 및 내용 |
| --- | --- |
| 상품·브랜드 | 가상 상품 24개, 브랜드 4개, 추가 카테고리 17개 |
| 상품 옵션·이미지 | 화이트/블랙 × 5사이즈로 240옵션, 이미지 행 48개 |
| 재고 | 정상 200옵션, 부족 20옵션, 품절 20옵션과 재고 정책·이동 원장 |
| 고객·주문·결제 | 기본 가상 고객 12명, 주문·결제 각각 36건 |
| 주문 상태 | 출고 대기 6건, 배송 중 6건, 수령 대기 6건, 수령 완료 18건 |
| 리뷰·포인트 | 리뷰 12건과 리뷰별 1,000P 적립·잔액·적립 단위 |
| 반품·문의 | 검수 대기 반품 6건, 문의 12건 중 미답변 8건 |
| 발주 결재 | 초안·팀장 대기·이사 대기 각각 2건 |
| 재입고 | 품절 옵션에 대한 알림 신청 6건 |

기존 성동·강남 대리점과 직원 권한을 사용해 출고 → 도착 → 고객 인도, 반품 검수·환불, 문의 답변, 발주 결재와 매출 분석을 시연할 수 있도록 구성했습니다. 상품 사진은 기존 목업 URL 6개를 재사용하며 실제 상품 종류·색상을 정확하게 나타내지 않을 수 있습니다.

가상 고객 UID는 Firebase 로그인 계정이 아닙니다. SQL의 `@shupick_demo_customer_uid`에 앱에서 동기화된 기존 고객 UID를 지정하면 해당 고객을 1번 고객 자리에 연결할 수 있습니다. 기존 프로필은 변경하지 않고 데모 리뷰 포인트만 기존 잔액에 추가합니다.

`@shupick_demo_apply` 기본값은 0입니다. 데이터 추가 승인 후에만 1로 변경하여 실행합니다. 실행 자체에는 로더 프로시저 생성·삭제가 포함됩니다. 업무 데이터는 한 트랜잭션으로 추가하며 오류 시 롤백하고, DEMO26/D26 데이터가 이미 있으면 중복 적용을 차단합니다. Firebase 계정 생성·직원 권한 변경·실제 결제 호출·알림 발송은 포함하지 않습니다.

INSERT 35문장의 32개 업무 테이블 컬럼을 실제 DB 메타데이터와 대조했고, 상품·옵션·주문 구성도 정적으로 확인했습니다. 실제 INSERT 실행 검증은 적용 승인 후 진행합니다.

## Windows PowerShell 실행

명령은 한 줄씩 실행합니다. Python 가상환경은 **backend/.venv**에 있습니다.

### 최초 백엔드 설정

~~~powershell
cd C:\0619ksh\Flutter\shupick\backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
~~~

이미 .venv와 .env가 있다면 기존 설정을 사용하세요. .env의 MySQL 접속 정보를 수정한 뒤 Firebase를 설정합니다.

~~~dotenv
FIREBASE_PROJECT_ID=shupick-71b8f
FIREBASE_CREDENTIALS_PATH=C:\secure\shupick-service-account.json
~~~

서비스 계정 경로는 실제 JSON 파일 위치로 바꿉니다. Firebase 콘솔의 프로젝트 설정 → 서비스 계정에서 발급하는 서버용 비공개 키이며 Android의 google-services.json과 다른 파일입니다. 저장소 밖에 보관하고 직원/고객 앱에 넣지 않습니다. OUTBOX_WORKER_SECRET도 별도로 설정합니다.

### 서버 실행

~~~powershell
cd C:\0619ksh\Flutter\shupick\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
~~~

앱 사용 중 서버를 계속 실행해 둡니다. 다른 PowerShell 창에서 확인합니다.

~~~powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:8000/products
~~~

`/health`의 `status: ok`는 API와 MySQL 연결을 확인합니다. [API 문서](http://127.0.0.1:8000/docs)에서 요청·응답 형식을 확인할 수 있습니다.

### 고객 앱 실행

~~~powershell
cd C:\0619ksh\Flutter\shupick
flutter pub get
flutter run
~~~

Android 에뮬레이터의 기본 API 주소는 `http://10.0.2.2:8000`입니다. 명시할 때는 다음 명령을 사용합니다.

~~~powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
~~~

실제 기기에서는 같은 네트워크의 백엔드 PC IPv4 주소를 사용합니다. 아래 IP는 예시입니다.

~~~powershell
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8000
~~~

TCP 8000 접근과 Firebase 프로젝트 설정을 확인하세요. API_BASE_URL 변경은 앱을 종료하고 다시 실행해야 합니다. 노트북의 HTTP 개발 서버는 운영 서버가 아닙니다.

### 별도 배치

backend 폴더의 별도 터미널에서 실행합니다.

~~~powershell
.\.venv\Scripts\python.exe -m app.maintenance_worker
.\.venv\Scripts\python.exe -m app.outbox_worker
~~~

한 번만 처리하려면 각 명령에 --once를 붙입니다. Firestore 사용 전에 데이터베이스를 활성화하고 firestore-status.rules를 팀의 기존 규칙에 병합해야 합니다. 파일을 단독 배포하면 다른 기능의 규칙을 덮어쓸 수 있습니다. 세부 배치 설명은 [backend/README.md](backend/README.md)를 참고하세요.

## 직원 앱에서 사용할 API

직원 앱도 같은 서버와 Firebase 프로젝트를 사용하며 모바일 앱의 Firebase 설정은 해당 패키지 이름으로 별도 등록합니다. 인증이 필요한 요청에는 Firebase ID 토큰을 `Authorization: Bearer <토큰>`으로 전달합니다.

| 기능 | API |
| --- | --- |
| 테스트 직원 가입 / 내 직책·지점 | `POST /auth/employee/register`, `GET /auth/employee/me` |
| 업무 주문 목록 / 픽업 코드 확인 | `GET /staff/orders`, `POST /staff/pickups/verify` |
| 본사 출고 / 대리점 도착 | `POST /fulfillments/{id}/ship`, `POST /fulfillments/{id}/arrive` |
| 고객 수령 완료 | `POST /orders/{id}/pickup/complete` |
| 재고 / 발주 품의 목록 | `GET /staff/inventory`, `GET /staff/procurement/requisitions` |
| 고객 문의 / 고객 목록·상세 | `GET /staff/inquiries`, `GET /staff/customers`, `GET /staff/customers/{id}` |
| 반품 목록 / 매출 분석 | `GET /staff/returns`, `GET /staff/analytics` |

그 밖의 발주 상신·승인, 문의 답변, 검수·환불 API는 /docs와 backend/app/에서 확인합니다. 직책과 기능 권한은 MySQL에서 검사합니다. 대리점 직원의 주문 조회·코드 검증·도착·수령 완료는 현재 지점 배정을 확인합니다. 다른 업무의 권한 범위도 운영 정책에 맞게 점검해야 합니다.

고객 수령 흐름은 **로그인·주문·결제 → 직원 출고 → 직원 대리점 도착 처리 → 고객이 배송 조회에서 픽업 가능 확인 → 결제 코드(주문번호) 제시 → 직원 수령 완료 처리 → 고객 구매확정** 순서입니다. 직원 처리 없이 시간 경과만으로 상태가 바뀌지는 않습니다. Firestore 연결이 실패해도 배송 조회의 새로고침으로 MySQL 상태를 확인할 수 있습니다.

## 검증 기록과 남은 작업

2026-10-05 이번 변경 정리 시 backend 폴더에서 `.\.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider`를 실행하여 **59개 테스트 통과**를 확인했습니다. 직원 반품 목록의 대리점 필터와 현재 배정 조건을 확인하는 테스트가 포함됩니다.

2026-10-05 로컬 main 병합 전에 확인한 결과:

- 백엔드 전체 테스트: **58개 통과** (backend에서 .\.venv\Scripts\python.exe -m pytest -q).
- 변경된 Flutter 컨트롤러 테스트: **5개 통과** (flutter test test/store_controller_test.dart --no-pub). 리뷰 조회 실패에도 상품 목록이 표시되는 회귀 테스트를 포함합니다.
- 이 검증은 직원 앱의 실제 화면·Firebase 로그인·MySQL 거래까지 모두 연결한 종단간 검증은 아닙니다.

기존 시연에서 고객 주문·결제, 서버 직원 함수로 수령 완료, 구매확정·리뷰 적립을 확인했습니다. 실제 MySQL 롤백형 스크립트로 일반/0원 결제의 부분 반품·검수·환불·재시도를 확인한 기록은 [검증 기록](docs/integration_verification.md)에 있습니다. DB 검증 스크립트는 개발용 DB와 전제 데이터를 확인한 뒤 실행합니다.

~~~powershell
# Flutter 프로젝트 루트
flutter analyze
flutter test

# backend 폴더
.\.venv\Scripts\python.exe -m pytest -q
~~~

남은 작업은 직원 화면과 API의 실제 로그인 시연, 운영용 직원 가입·권한 정책, Firestore 전송·수신·규칙 배포 검증, 실제 대리점 데이터 등록입니다. 미수령 안내·회수·환불 배치, 실제 재입고 감지·알림, 생일 쿠폰도 추가 구현·검증이 필요합니다.

## 로컬 Git 병합 기록

2026-10-05 codex/mysql-integration의 변경을 로컬 main에 fast-forward 병합했습니다. 최신 기능 커밋은 24f92a3 (feat: add staff backend workflows and fix customer startup loading)입니다. 이 병합 작업은 로컬에서 완료했으며 GitHub에는 반영하지 않았습니다. .vscode의 개인 환경 설정은 커밋에서 제외했습니다.

## 변경사항 공유 브랜치

2026-10-05 변경사항 공유용 브랜치 `codex/progress-demo-data-20261005`를 생성했습니다. 기존 로컬 main에 병합된 고객·직원 백엔드 기능과 이번 README 정리, 직원 반품 조회 필터·테스트, MySQL 임시 데이터 구성안·SQL을 포함합니다. GitHub에는 이 브랜치를 push하며, main 병합과 Pull Request 생성은 별도 요청 시 진행합니다. 개인 `.vscode/` 설정은 커밋 대상에서 제외합니다.
