# 카카오·네이버 고객 로그인 (로컬 준비)

대상은 `D:\grace2\shupick\mysql-integration` 고객 앱과 그 안의 `backend`입니다.
기존 `shupick` 앱 및 `shupick_staff` 직원 앱은 이 작업의 변경 대상이 아닙니다.

## 연결 방식

카카오 또는 네이버 인증 → 서버에서 공급자 인증 검증 → Firebase custom token
→ 고객 앱 Firebase 로그인 → Firebase ID token으로 기존 주문/문의 API 사용.
Firebase와 MySQL은 계속 사용합니다. 앱이 MySQL에 직접 접속하지 않습니다.

회원 식별자는 이메일이 아니라 공급자와 앱 ID를 포함한 안정적인 UID입니다.
동일한 공급자 계정으로 다시 로그인하면 같은 회원/주문을 조회합니다.
다른 로그인 방식의 동일 이메일 계정과 자동 합치지는 않습니다.
따라서 이메일로 쓰던 주문을 카카오 로그인 계정이 자동 공유하지 않습니다.
계정 연결은 별도의 본인 확인 설계가 필요합니다.

현재 코드는 Android/iOS 고객 로그인용입니다. 웹/Windows 로그인은 이 변경에
포함되지 않습니다. 실제 공급자 로그인은 개발자센터 설정 후 별도로 검증합니다.

## 1. 카카오 개발자센터

1. SHUPICK 앱의 숫자 **앱 ID**를 확인합니다. 32자리 앱 키와 다릅니다.
2. 네이티브 앱 키를 확인합니다. REST API 키/JavaScript 키/어드민 키가 아닙니다.
3. Android 플랫폼에 패키지 `com.example.shupick`과 실제 디버그 서명 키 해시를
   등록하고 카카오 로그인을 활성화합니다. 출시 시 출시 서명의 키 해시도 필요합니다.
4. `social-login.local.json`의 `KAKAO_NATIVE_APP_KEY`에 네이티브 앱 키를 넣습니다.
   Android의 콜백 스킴도 이 값에서 빌드 시 생성됩니다.
5. `backend/.env`에 숫자 `KAKAO_APP_ID`를 설정합니다.

앱 키는 로컬 설정에만 두고 코드/채팅에 다시 붙이지 않습니다.
2026-10-06 기준 사용자 확인 후 이 PC의 로컬 설정에 네이티브 앱 키와 숫자 앱 ID
`1595768`을 반영했습니다. 키 값은 이 문서에 기록하지 않습니다. 개발자센터의
Android 패키지/키 해시와 로그인 ON 상태는 사용자 화면에서 확인했습니다.
2026-10-06 사용자 Android 테스트에서 카카오 로그인에 성공했습니다.
읽기 전용 확인으로 MySQL 카카오 회원 1명과 포인트 지갑 생성, Firebase 계정의
활성 상태 및 실제 로그인 기록을 확인했습니다. 로그아웃 후 같은 카카오 계정으로
재로그인하여 같은 회원을 사용하는지 추가 검증합니다. 네이버 최초 로그인은 사용자 화면에서
성공을 확인했지만, 동의받은 별명의 실제 수신/표시는 아직 추가 검증이 필요합니다.
다른 개발자의 설정에 키가 없으면 설정 안내를 표시하며 기존 이메일/Google 로그인은 유지합니다.

## 2. 네이버 개발자센터

2026-10-06 사용자가 SHUPICK용 애플리케이션 등록과 로컬 서버 설정을 완료했고,
Android 에뮬레이터에서 최초 네이버 로그인 및 마이페이지 진입을 확인했습니다.
다른 환경에서는 공식 등록 화면에서 **네이버 로그인**을 선택하고 브라우저 OAuth 콜백을 사용할 수
있도록 서비스 URL/Callback URL을 등록합니다. 이 구현은 네이티브 네이버 SDK가
아니라 서버가 Client Secret을 보관하는 OIDC + PKCE 방식입니다.

로컬 Android 에뮬레이터에서 제안하는 콜백은 다음과 같습니다.

`http://10.0.2.2:8000/auth/social/naver/callback`

개발자센터가 이 로컬 URL을 허용하는지는 등록 화면에서 확인해야 합니다.
거부된다면 임의 외부 터널을 만들지 말고, 팀의 HTTPS 테스트 서버 주소를 정한 뒤
Callback URL과 `NAVER_REDIRECT_URI`를 **정확히 같은 값**으로 설정합니다.
실물 기기에서는 `10.0.2.2`를 사용할 수 없습니다.

Client ID, Client Secret은 아래 서버 파일에만 입력합니다.

```dotenv
# backend/.env — 기존 MySQL/Firebase 설정은 유지
KAKAO_APP_ID=0
NAVER_CLIENT_ID=
NAVER_CLIENT_SECRET=
NAVER_REDIRECT_URI=http://10.0.2.2:8000/auth/social/naver/callback
```

Client Secret/서비스 계정 JSON은 Flutter 앱, GitHub, 채팅에 넣지 않습니다.
앱으로 돌려보내는 콜백 URL에는 Firebase 토큰/공급자 access token이 없습니다.
서버의 기본 Uvicorn 접근 로그에서 OAuth 콜백 쿼리도 제거합니다.

### 다른 네이버 계정으로 로그인

SHUPICK 로그아웃과 브라우저의 네이버 로그아웃은 별개입니다. 브라우저에 남은
네이버 세션으로 바로 로그인되지 않도록 인증 요청에
`auth_type=reauthenticate`를 넣어 매번 네이버 ID/PW 입력을 요청합니다.
이 값은 OIDC `/oauth2/authorize`에서도 지원하는 공식 재인증 방식입니다.
여러 계정을 목록으로 보여주는 계정 선택창을 보장하는 기능은 아닙니다.
[네이버 재인증 안내](https://developers.naver.com/docs/login/devguide/devguide.md)

### 별명 제공 동의와 표시명

네이버 **로그인 아이디**와 **프로필 별명**은 다릅니다. 로그인 아이디는 API가
제공하지 않으므로 아이디를 자동 표시하지 않습니다. 별명을 설정하지 않은 경우
네이버가 `id***` 형태의 값을 반환할 수도 있습니다.
[네이버 회원 프로필 조회 명세](https://developers.naver.com/docs/login/profile/profile.md)

1. 네이버 개발자센터의 **내 애플리케이션 → SHUPICK → API 설정**에서 네이버 로그인의
   제공 정보 선택 항목을 엽니다.
2. **별명** 행의 **추가** 열만 체크하고 저장합니다. 별명은 선택 제공으로 요청하며,
   **필수**로 만들거나 이메일/실명/전화번호 등의 항목을 함께 요청할 필요는 없습니다.
3. 서버 코드 변경을 반영하도록 서버를 재시작한 뒤 SHUPICK 앱에서 로그아웃하고
   같은 네이버 계정으로 다시 로그인합니다. 별명 제공 동의가 표시되면 내용을 읽고
   제공을 원할 때 동의합니다. 제공하지 않아도 로그인 자체는 계속 사용할 수 있습니다.
4. 동의 화면이 나오지 않거나 이름이 그대로라면 현재 화면을 확인합니다. 동의 화면을
   띄우려고 네이버 연결 해제, Firebase 계정 삭제 또는 앱 데이터 삭제를 하지 않습니다.

추가 제공 항목은 사용자가 제공에 동의한 경우에만 프로필 응답으로 전달됩니다.
[네이버 선택적 제공 안내](https://developers.naver.com/docs/login/devguide/devguide.md)

서버는 기존 OIDC 서명 검증으로 확인한 `sub`와 Firebase UID를 그대로 사용하고,
동일한 로그인 과정에서 서버가 발급받은 access token으로 고정된
`https://openapi.naver.com/v1/nid/me`에서 `nickname`만 추가 조회합니다.
프로필의 `id`나 별명으로 UID를 다시 만들지 않으며 이메일로 다른 계정을 합치지 않습니다.
별명을 받았을 때 Firebase/MySQL의 기존 표시명이 정확히 `네이버 회원`이라는
기본값인 경우만 갱신합니다. 직접 설정된 이름, 이메일, 주문/문의 및 계정별 쇼핑 기록은
덮어쓰지 않습니다. 별명 미동의, 빈 응답 또는 조회 실패 시 기존 표시명을 유지하고,
기본명이었다면 `네이버 회원`으로 계속 표시합니다.

별명 제공 동의 후 실제 네이버 응답과 마이페이지 표시가 함께 확인되어야 검증 완료입니다.
최초 로그인 성공 화면이나 오프라인 자동 테스트만으로 별명 연동 성공을 판단하지 않습니다.
개발자센터에서 별명 항목을 추가했더라도 해당 사용자가 제공에 동의하지 않으면
`네이버 회원`이라는 기본 이름을 유지하는 것이 정상입니다. 재인증의 ID/PW 입력과
별명 제공 동의는 서로 다른 단계입니다.

문제가 계속되면 서버의 네이버 별명 진단 로그에서 고정된 원인 코드만 확인합니다.
`nickname_present`는 별명 수신, `nickname_missing`은 빈 값/항목 누락,
`profile_rejected`는 제공자 거절, `profile_unavailable`은 일시적인 조회 실패,
`invalid_profile_response`는 예상하지 못한 응답 형식입니다. 실제 별명·이메일·
UID·인증 토큰·응답 본문은 로그에 남기지 않습니다. 이름 확인을 위해 계정을 삭제하거나
기존 주문/회원 데이터를 다시 넣지 않습니다.

## 3. 이메일 없는 회원용 DB 준비

기존 이메일/주문/문의 행을 덮어쓰지 않고, `customers.email`만 NULL 허용으로
바꾸는 전진 변경을 준비했습니다. 2026-10-06 이 PC의 로컬 `shupick_v2`에 적용했고,
적용 전후 회원·주문·문의 전체 행을 비교해 기존 데이터가 그대로임을 확인했습니다.
기존 schema/seed/001–017 및 018–024 데모 SQL을 다시 실행하지 마세요.

```powershell
cd D:\grace2\shupick\mysql-integration\backend
.\.venv\Scripts\python.exe .\apply_social_login_schema.py --check
# 다른 개발 PC에서 공급자 설정 준비 후 적용. 이 PC에서는 적용 완료입니다.
.\.venv\Scripts\python.exe .\apply_social_login_schema.py
```

이미 이메일이 선택 사항이면 다시 변경하지 않습니다. 다른 DB/원격 호스트이면
유틸리티가 적용을 거부합니다. 같은 변경의 SQL은 `025_social_customer_email_optional.sql`입니다.

## 4. 실행 및 검증

기존 서버 터미널에서 Ctrl+C 후 **같은 backend**를 재시작합니다.

```powershell
cd D:\grace2\shupick\mysql-integration\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

고객 앱 VS Code는 `mysql-integration` 폴더를 열고 실행 설정
`SHUPICK - local MySQL + social login`을 선택합니다. 또는 새 터미널에서:

```powershell
cd D:\grace2\shupick\mysql-integration
flutter run --dart-define-from-file=social-login.local.json
```

패키지/네이티브 콜백 설정을 처음 적용할 때는 hot reload만으로는 부족합니다.
앱 실행을 중단한 후 다시 빌드/실행하되 앱 데이터 삭제/재설치로 주문을 지우지 않습니다.

이미 위 설정으로 실행 중인 앱에 이번 네이버 재인증/표시명 수정만 반영할 때는
**서버 재시작 → 고객 앱 Hot Restart → 로그아웃 → 네이버 로그인** 순서로 확인합니다.
Flutter 실행 터미널에서 대문자 `R` 또는 VS Code의 디버깅 재시작 버튼을 사용합니다.
기존 실행의 `--dart-define-from-file` 설정은 유지합니다. 서버는 `--reload` 없이
실행하므로 앱만 재시작해도 서버 코드 변경은 반영되지 않습니다.
이번 확인에서도 실행 중인 서버의 시작 시각이 별명 코드 수정 시각보다 빨라,
별명 수신 여부를 다시 시험하기 전에 서버 재시작이 필요했습니다.

`카카오 로그인 앱 키 설정을 먼저 완료해주세요.`가 뜨는데 로컬 JSON의 키가 정상이라면,
실행 명령에서 `--dart-define-from-file` 옵션이 빠졌는지 확인합니다. VS Code 설정에는
`templateFor: lib`를 추가하여 `main.dart`의 기본 Run/Debug도 동일한 설정을 사용합니다.
이는 [Dart Code의 공식 실행 설정](https://dartcode.org/docs/launch-configuration/) 방식입니다.
고객 앱의 실행 중인 디버깅 세션을 중지하고, 별도 터미널에서 다음 명령으로 직접 실행하면
프로젝트/설정 파일/에뮬레이터를 명확히 지정할 수 있습니다. 서버 터미널은 종료하지 않습니다.

```powershell
cd D:\grace2\shupick\mysql-integration
& D:\grace2\flutter\flutter\bin\flutter.bat run -d emulator-5554 --dart-define-from-file=D:\grace2\shupick\mysql-integration\social-login.local.json --target=D:\grace2\shupick\mysql-integration\lib\main.dart
```

실제 테스트 순서:

1. 기존 이메일 계정으로 로그인 → 기존 주문/문의 보존 확인 → 로그아웃.
2. 카카오 로그인 → `/auth/social/kakao`와 `/auth/me` 성공 확인.
3. 로그아웃/같은 카카오 계정 재로그인 → 같은 UID/회원 데이터 확인.
4. 네이버도 start → 브라우저 동의 → callback → complete → `/auth/me` 순서 확인.
5. 로그인 취소, 잘못된 설정, 이메일 제공 동의 없음에도 전체 탭이 막히지 않는지 확인.
6. 별명을 추가 제공으로 설정하고 동의한 계정에서 기본 표시명이 별명으로 바뀌는지 확인.
   별명 미제공/조회 실패 시 로그인은 유지되고, 기존 직접 설정 이름과 계정 기록이 보존되는지도 확인.

설정 전에는 소셜 계정이 새로 생성되지 않습니다. 오프라인 자동 테스트는 실제
공급자, Firebase 계정, DB를 변경하지 않으며 실제 로그인 성공을 대신하지 않습니다.

## iOS 및 공개 배포 제한

Windows에서 iOS 빌드/실기기 로그인은 확인할 수 없습니다. Mac에서 iOS 플랫폼의
번들 ID 등록과 Firebase 구성을 확인하고, `SocialLogin.example.xcconfig`를
`ios/Flutter/SocialLogin.local.xcconfig`로 복사하여 Dart와 동일한 네이티브 앱 키를
설정해야 합니다. 실제 API/콜백은 HTTPS 주소를 사용하는 편이 적합합니다.

네이버 진행 상태는 단일 서버 프로세스 메모리에 5분간 보관합니다. 로그인 중 서버를
재시작하면 처음부터 다시 로그인해야 합니다. 공개 배포/다중 worker에는 공유 저장소,
HTTPS, 요청 빈도 제한, 로그/프록시의 인증정보 마스킹이 추가로 필요합니다.

## 공식 자료

- [카카오 Flutter 시작하기](https://developers.kakao.com/docs/ko/flutter/getting-started)
- [카카오 로그인 REST API](https://developers.kakao.com/docs/ko/kakaologin/rest-api)
- [네이버 로그인 개발가이드](https://developers.naver.com/docs/login/devguide/devguide.md)
- [네이버 회원 프로필 조회 명세](https://developers.naver.com/docs/login/profile/profile.md)
- [Firebase custom token](https://firebase.google.com/docs/auth/admin/create-custom-tokens)
