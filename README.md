# ShuPick — MySQL 연동 변경사항 및 팀 전달

Flutter → FastAPI → MySQL 구조의 대리점 수령 시연 프로젝트입니다. 결제·환불은 실제 결제대행사에 연결하지 않은 데모입니다.

## DB 역할

- MySQL: 상품·SKU·재고·주문·결제·수령·반품·환불·리뷰·쿠폰·포인트의 거래 원본. 추천 분석용 고객 행동 이벤트도 저장합니다.
- SQLite: 기기 로컬 장바구니·찜·조회/검색 기록·설정·상품 캐시 등 UX 데이터.
- Firebase: 로그인 인증·알림·실시간 상태 투영. MySQL outbox와 주문 배송 화면 구독은 연결했지만 실제 Firestore 전송·규칙 배포 검증은 보류했습니다.

## 이번 연결 변경사항

- 상품·옵션·재고·분류·브랜드·대리점·요일별 운영시간 조회
- Firebase 로그인 후 MySQL 고객 동기화, 인증된 고객 소유 주문 조회
- 주문 생성·재고 예약·데모 결제, 쿠폰 및 포인트 사용
- 출고 → 대리점 도착 → 수령 완료 및 상태 이력, 결제 코드 시연 인증
- 구매확정, 공개 리뷰·실제 평점·구매 옵션·사진 확대
- 본인 리뷰 수정·삭제 버튼, 처리 후 공개 목록·평점 갱신
- 리뷰 최초 작성 1,000P 적립 및 회원 혜택 갱신
- 선택 수량 반품·본사 검수·부분 환불·재고 복구·사용 포인트 복원
- 0원 결제 반품 처리 및 예상 환불액 조회
- 문의·직원 답변·재입고 신청 저장, 고객 행동 이벤트 재시도·중복 방지
- 포인트 만료·미결제 예약 만료·월별 회원등급/쿠폰팩 발급 배치

## 확정 정책

- 자치구당 대리점 하나를 운영합니다. 현재 DB에는 성동구 한 곳만 등록되어 있고 서울 25개 자치구 추가는 보류했습니다. `district_code UNIQUE` 제약은 추가하지 않습니다.
- 교환은 없습니다. 일반 반품은 수령 후 7일 이내·미착용·훼손 없음·구성품/포장 유지이며 불량·오배송은 별도 검수합니다.
- 고객이 구매확정을 누른 후에는 반품·환불 불가, 해당 상품 리뷰 작성 가능입니다.
- 신규 포인트는 리뷰 최초 작성만 적립합니다. 일반/사진 리뷰 모두 구매 항목당 1,000P, 적립일부터 1년 만료입니다. 수정·삭제 후 재작성은 추가 적립하지 않습니다. 환불에 따른 사용 포인트 복원은 신규 적립과 별개입니다.
- 부분 반품은 결제 당시 주문 스냅샷으로 쿠폰 할인·포인트를 배분합니다. 해당 수량의 실제 결제액과 사용 포인트만 반환하며, 이미 만료된 포인트는 복원하지 않습니다. 부분 반품 쿠폰은 복원하지 않습니다.
- 현행 반품 신청은 주문당 한 번입니다. 신청할 상품과 수량을 한 번에 선택해야 합니다.
- 본사 검수 승인 시 정상 상품은 판매 재고로, 판매 부적합 상품은 격리 재고로 입고합니다.
- 회원등급은 매월 직전 12개월 구매확정 실적 기준으로 산정합니다. 구매확정 자체에는 포인트를 지급하지 않습니다.

## 팀원 실행·인수인계

### 백엔드 설정

저장소의 `backend` 폴더에서 실행합니다.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

실행 전에 `.env`의 MySQL 접속·Firebase 프로젝트·서비스 계정 경로를 설정합니다. 서비스 계정 JSON은 저장소 밖에 보관하고 `.env`, 비밀번호, 개인키를 Git에 올리지 마세요. Flutter에는 MySQL 비밀번호나 Firebase Admin 키를 넣지 않습니다.

- 로컬 수정 스키마는 `shupick_v2`입니다. 원본 스키마에 덮어쓰지 마세요.
- `database/migrations`의 기존 적용 여부를 확인하고 누락된 SQL만 순서대로 적용하세요. 적용 이력 자동 추적은 없으며 이미 적용된 SQL을 무조건 다시 실행하면 오류가 날 수 있습니다.
- 이번 추가 마이그레이션은 `012`~`017`입니다. `017`은 0원 환불 원장 허용입니다. 실제 DB 데이터·접속 계정·시연 주문은 Git push에 포함되지 않습니다.
- 백엔드는 앱 이용 중 계속 실행해야 합니다. 노트북 절전·종료나 서버 종료 시 조회가 실패합니다. `/health`로 상태를 확인하세요.
- 상세 설정: [backend/README.md](backend/README.md).

### Flutter와 팀원 기기 접속

```powershell
flutter pub get
flutter run
```

Android 에뮬레이터 기본 주소는 `http://10.0.2.2:8000`, 다른 플랫폼은 `http://127.0.0.1:8000`입니다. 팀원 실제 기기는 백엔드 노트북 LAN IP로 지정해야 합니다.

```powershell
flutter run --dart-define=API_BASE_URL=http://<백엔드_노트북_LAN_IP>:8000
```

같은 네트워크 및 TCP 8000 접근을 확인하고 Firebase 프로젝트 설정을 일치시키세요. 노트북 개발 서버는 운영 서버가 아닙니다.

### 담당별 남은 작업

- Firebase 담당: Firestore 활성화, outbox 실제 전송·앱 수신, 보안 규칙 병합·배포. `firestore-status.rules`를 단독 배포하면 다른 기능의 규칙을 덮어쓸 수 있으므로 기존 팀 규칙과 병합해야 합니다.
- 직원 UI 담당: 출고·도착·수령·검수·환불 API를 직원 화면에 연결하고 실제 직원 인증·권한으로 시연합니다. 고객 앱에 직원 작업 권한을 주지 않습니다.
- 알림/배치 담당: 미수령 안내·회수·환불, 실제 재입고 감지·알림, 생일 쿠폰은 추가 구현·점검이 필요합니다. 유지보수는 `python -m app.maintenance_worker`, Firebase 전송은 `python -m app.outbox_worker`로 별도 실행합니다.
- 데이터 담당: 서울 25개 자치구별 실제 대리점과 주소·연락처·운영시간 등록은 추후 진행합니다.

## 현재 검증 범위

- 실제 앱: 로그인 → 주문·결제 → 서버 직원 처리 함수로 수령 완료 → 앱 구매확정 → 리뷰 적립 확인. 사용자 수정·삭제·재작성 후 적립 원장 한 건·잔액 1,000P 유지 확인.
- 실제 MySQL 롤백형 API 검증: 일반/0원 결제의 부분 반품·검수·환불·재고/포인트 복원·재시도. 고객 인증은 테스트 의존성으로 대체하고 직원 처리는 서버 함수를 직접 호출하므로 직원 UI 인증까지의 검증은 아닙니다.
- 최근 전체 검증: 백엔드 44개·Flutter 24개 테스트 통과, Flutter 분석 오류 없음. 실제 Firebase 전송과 직원 화면 종단간 시연은 별도입니다.

```powershell
dart format lib test
flutter analyze
flutter test
```

백엔드에서는 `.\.venv\Scripts\python.exe -m pytest -q`를 실행합니다. DB 검증 스크립트는 개발용 스키마와 테스트 전제 데이터를 확인한 후 실행하세요. 세부 기록: [검증 기록](docs/integration_verification.md).

---

## 초기 목업 참고 기록 (아래 설명은 연동 전 기준)

Higgsfield 목업의 화면 구조와 로컬에서 확인 가능한 상호작용을 Flutter로 옮긴 팀 작업본입니다.

## 실행

```sh
flutter pub get
flutter run
```

## 구현 범위

- 비회원 홈 탐색, 기획전, 성별·카테고리·하위 분류·정렬, 검색, 최근 본 상품, 찜
- 상품 상세, 색상별 이미지와 옵션, 복수 옵션 선택, 재입고 신청
- 장바구니 선택·수량·옵션 수정, 대리점 선택, 쿠폰·적립금·결제 수단 선택, 목업 주문 완료
- 로그인·회원가입 목업, 주문·배송·픽업 QR, 리뷰 작성·수정·삭제·사진, 쿠폰·포인트·고객센터
- 한국어·영어 화면 문구, 다크 화면, 푸시 설정

화면에 보이는 결제 수단, 소셜 로그인, 비밀번호 재설정 메일, 실제 푸시 발송, QR 검증, 주문 배송 정보는 실제 외부 서비스와 연동하지 않습니다. UI 전용 항목은 비활성 상태로 표시합니다.

## 구조와 추후 DB 연결

- `lib/main.dart`: 앱 진입점
- `lib/app`: 의존성 조립과 화면 상태
- `lib/domain/models.dart`: 상품·주문·리뷰·문의 모델
- `lib/domain/repositories.dart`: 저장·조회 인터페이스
- `lib/data/mock_repositories.dart`: 상품·주문·리뷰·문의 더미 데이터
- `lib/data/local_settings_repository.dart`, `lib/data/local_support_repository.dart`: 언어·화면 설정과 재입고 신청의 기기 저장
- `lib/presentation/screens`: 기능별 화면
- `lib/presentation/shared`: 공통 상품 위젯
- `lib/presentation/localization.dart`, `lib/presentation/locale_dictionary.dart`: 목업의 영어 문구 사전

현재 상품·주문·리뷰·문의·장바구니는 앱 실행 동안 유지되는 목업 저장소를 사용합니다. 실제 서비스로 전환할 때 `ProductRepository`, `OrderRepository`, `ReviewRepository`, `ShoppingRepository`, `SupportRepository`, `AccountRepository` 구현을 교체하면 화면 상태와 위젯을 유지할 수 있습니다. MySQL 트랜잭션 데이터는 백엔드 API를 통해 연결하고, SQLite는 기기 캐시나 임시 저장, Firebase는 알림 등 보조 기능에 연결하는 구조를 권장합니다.

## 검증

```sh
dart format lib test
flutter analyze
flutter test
```
