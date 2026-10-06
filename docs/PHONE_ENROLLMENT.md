# 휴대폰 문자 인증과 선택 생년월일 등록

작업 대상: `D:\grace2\shupick\mysql-integration`만 사용합니다. 원본 앱과 직원 앱은 수정하지 않습니다.

## 구현한 범위와 남은 설정

- 실제 Firebase 계정 저장소를 사용하는 이메일 회원가입: 기존 이메일/비밀번호/확인에 휴대폰 문자 인증을 추가했습니다. 생년월일은 선택입니다.
- 기존 이메일·카카오·네이버·구글 회원: 로그인 후 **마이페이지 → 설정 → 휴대폰 인증·생일 등록**에서 등록합니다. 기존 로그인은 강제로 차단하지 않습니다.
- 인증된 번호는 별도 테이블에 저장하며 생년월일은 기존 `customers.birth_date`에 저장합니다. 전화번호는 서버 응답에 일부 가림으로 표시합니다.
- 생일쿠폰 자동 발급, 아이디 찾기/비밀번호 복구용 SMS 화면은 아직 구현하지 않았습니다. 이번 작업은 인증 정보 등록 기반입니다.
- 자동 테스트는 합성 토큰·모의 Firebase/HTTP를 사용합니다. 실제 SMS 발송·수신·기기 앱 인증 검증은 아직 하지 않았습니다. 인증 통과를 흉내 내는 앱 런타임 우회는 넣지 않았습니다.
- Firebase 요금제, 로그인 공급자, SMS 지역 정책, 인증서, 클라우드 보안 규칙은 이번 작업에서 변경하지 않았습니다.

## 계정과 인증 정보

쇼핑 계정의 Firebase UID는 그대로 유지합니다. 별도의 Firebase 앱/Auth 세션에서 휴대폰 인증을 수행한 다음, 휴대폰 증명 ID 토큰을 기본 쇼핑 계정의 Bearer 토큰과 함께 서버에 보냅니다. 기본 계정에 전화번호 자격 증명을 연결하지 않으며 동일 전화번호로 여러 계정을 합치지 않습니다.

Firebase에는 번호당 전화번호 인증용 사용자 identity가 생길 수 있습니다. 보조 세션은 화면을 닫으면 로그아웃하고 보조 Firebase 앱을 정리합니다. Firebase 사용자 자체를 삭제하거나 기존 계정의 번호를 변경하지 않습니다. 토큰·OTP는 파일/로그/URI/장바구니에 저장하지 않습니다.

`customer_enrollments`는 고객당 한 행입니다. `verified_phone`과 `firebase_phone_uid`는 중복을 허용하므로 같은 사람이 다른 소셜 계정에 같은 번호를 등록해도 주문/찜/장바구니는 각각 기존 UID에 귀속됩니다. 기존 `customers.phone`은 인증되지 않은 연락처이므로 자동으로 인증 상태로 승격하지 않습니다. 추후 복구 기능은 번호 하나에 여러 계정이 연결되는 경우를 별도로 처리해야 합니다.

SMS는 번호 소유 확인입니다. 실명·나이·입력한 생년월일의 진위를 인증하지 않습니다. 날짜는 1900-01-01부터 오늘까지 허용하며 생일 입력을 생일 정보 저장 동의로 처리합니다. 인증된 번호가 있는 회원은 재인증 없이 생일만 수정/삭제할 수 있습니다. 쿠폰 악용 방지를 위한 생일 수정 횟수, 2월 29일 지급일, 연 1회 중복 방지, 소셜 계정별 지급 정책은 팀 결정과 쿠폰 구현 단계에서 추가해야 합니다. 현재 날짜 입력은 별도 연령 확인 기능이 아닙니다.

## 서버 검증

- `POST /auth/phone/validate`: 이메일 계정 생성 전 전화번호 증명과 DB 준비 여부를 확인합니다. 새 계정을 만들거나 정보를 저장하지 않습니다.
- `GET /auth/customer/enrollment`: 인증된 기본 계정의 등록 상태만 조회합니다.
- `POST /auth/customer/enrollment`: 기본 계정 UID로 조회한 고객에만 저장합니다. 고객 ID/UID를 클라이언트가 지정하면 요청을 거부합니다.

전화번호 증명은 설정된 Firebase 프로젝트의 서명·만료·철회 여부를 Admin SDK로 검증하고, `sign_in_provider=phone`, 한국 010 번호, 최근 5분 이내 `auth_time`, 사용자 활성 상태와 현재 번호 일치를 확인합니다. 휴대폰 인증 동의 없이 저장할 수 없습니다. 생일 값이 있으면 별도 저장 동의도 요구합니다. 잘못된 요청 응답은 입력된 토큰을 그대로 반환하지 않습니다.

휴대폰 증명 확인 실패/DB 사전 검사 실패 시 이메일 가입을 시작하지 않습니다. Firebase 이메일 계정 생성 후 MySQL 저장이 실패한 경우 새 계정을 임의 삭제하지 않고 설정 화면에서 다시 등록하도록 안내합니다. 두 시스템 사이의 원자적 트랜잭션은 아닙니다. 기존 일반 프로필 동기화 API는 유지되며, 계정 생성 자체가 문자 인증 완료를 뜻하지 않습니다. 문자 인증 상태는 별도 테이블 기록으로만 판단합니다.

## 로컬 DB 및 실행

로컬 `localhost`의 `shupick_v2`에서 `026_customer_enrollment.sql`만 적용했습니다. 데이터 초기화·시드 재실행은 하지 않았습니다. 다른 팀원 환경에서는 먼저 읽기 전용 검사 후 추가 마이그레이션을 적용합니다.

```powershell
cd D:\grace2\shupick\mysql-integration\backend
.\.venv\Scripts\python.exe apply_customer_enrollment_schema.py --check
.\.venv\Scripts\python.exe apply_customer_enrollment_schema.py
```

실행 중인 FastAPI는 `--reload`가 없으므로 기존 서버 터미널에서 `Ctrl+C`로 종료하고 다시 실행해야 새 API가 반영됩니다.

```powershell
cd D:\grace2\shupick\mysql-integration\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

이미 켜진 고객 Flutter 실행 터미널에서는 대문자 `R`로 Hot Restart합니다. 새로 실행한다면 기존 소셜 키 설정 파일을 유지합니다. 키/Client Secret/OTP는 채팅에 보내지 마세요.

```powershell
cd D:\grace2\shupick\mysql-integration
& D:\grace2\flutter\flutter\bin\flutter.bat run -d emulator-5554 --dart-define-from-file=D:\grace2\shupick\mysql-integration\social-login.local.json --target=D:\grace2\shupick\mysql-integration\lib\main.dart
```

## Firebase 콘솔에서 함께 확인할 항목

1. `shupick-71b8f` 프로젝트인지 확인하고 Authentication의 로그인 방법에서 **전화번호** 설정 화면을 확인합니다. 결제 계정 연결/업그레이드가 요구되면 진행을 멈추고 비용 사용 여부를 결정합니다.
2. 실제 인증 SMS는 현재 공식 문서상 Blaze 요금제가 필요합니다. 업그레이드·문자 발송·한도 설정은 아직 진행하지 않았습니다. 예산 알림만으로 사용량이 강제 차단된다고 가정하면 안 됩니다.
3. 실제 발송 전 SMS 지역 정책에서 한국 허용 여부, Firebase Android 앱의 패키지명·SHA-1·SHA-256, Play Integrity/reCAPTCHA 요구 사항을 확인합니다. 현재 코드는 Android 한국 010 번호 범위를 지원합니다. 웹 전화번호 로그인과 다른 국가 번호 지원은 이번 범위 밖입니다.
4. 에뮬레이터 검증은 콘솔에 등록한 가상 번호와 인증 코드를 사용합니다. 이 번호에는 실제 문자가 발송되지 않으며 실제 휴대폰 수신 성공을 뜻하지 않습니다. 가상 번호도 Firebase 공급자 설정이 필요하므로 Spark에서 반드시 활성화 가능하다고 단정하지 않습니다.
5. 실제 발송·수신은 별도 사용자 승인을 받은 후 지원되는 실제 기기로 검증합니다. 인증번호는 앱에만 입력합니다.

공식 참고: [Flutter 전화번호 인증](https://firebase.google.com/docs/auth/flutter/phone-auth), [SMS 발송 및 Authentication 한도](https://firebase.google.com/docs/auth/limits), [Android 전화번호 인증 앱 검증](https://firebase.google.com/docs/auth/android/phone-auth).

## 파일과 자동 테스트

2026-10-06 검증: 백엔드 전체 290개, Flutter 전체 277개 테스트 통과, `flutter analyze` 오류/경고 없음. 인증 실패·번호 변경·재전송·취소 콜백·동의·5분 만료·계정 변경·가입 사전 검사·부분 저장 실패를 모의 환경에서 확인했습니다. 실제 Firebase SMS 수신 성공과 동일한 검증은 아닙니다.

- UI: `lib/presentation/shared/phone_enrollment_fields.dart`, `lib/presentation/screens/member_enrollment_screen.dart`, `lib/presentation/screens/account_screens.dart`
- Firebase/HTTP: `lib/data/firebase_phone_verifier.dart`, `lib/data/firebase_account_repository.dart`
- 서버: `backend/app/customer_enrollment.py`
- 추가 스키마: `database/migrations/026_customer_enrollment.sql`
- 테스트: `backend/tests/test_customer_enrollment.py`, `test/phone_enrollment_test.dart`, `test/firebase_phone_verifier_test.dart`, `test/firebase_account_repository_test.dart`

원래 주문 조회 권한과 Firestore 규칙은 변경하지 않았습니다. 보조 전화번호 인증 세션으로 기존 주문 문서를 읽지 않습니다.
