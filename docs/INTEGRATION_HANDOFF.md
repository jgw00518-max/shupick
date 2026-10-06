# Firebase · 고객 UI · 직원 API 통합 (2026-10-06)

## 합친 작업

- 고객 UI·직원 업무 API: `codex/progress-demo-data-20261005` (`f354fd0`)
- 소셜 로그인·계정별 쇼핑 데이터·휴대폰 인증 가입: `codex/firebase-auth-enrollment-20261006` (`0467025`)
- 병합 보관 브랜치: `codex/integration-firebase-20261006`

팀원의 고객 화면·테마·찜 삭제 애니메이션·직원 등록/주문/업무 API를 유지하면서 Firebase 인증 기능을 연결했습니다.
로그인 시 전용 로딩 화면, 공급자 로고, 이메일 앞부분 표시, 계정별 장바구니·찜·최근 본 상품 분리를 유지합니다.
실제 Firebase 이메일 가입에서는 문자 인증과 선택 생일·이름 입력을 사용합니다. 목업 저장소의 기존 가입 입력은 유지합니다.
프로필 복원은 기존 회원 정보를 덮어쓰지 않으며, 명시하지 않은 휴대폰·생일은 서버에서도 보존합니다.

## 자동 검증

- `flutter analyze --no-pub`: 오류 없음
- `flutter test --no-pub`: 310개 통과
- 백엔드 `python -m pytest tests -q`: 310개 통과 (기존 Starlette/httpx 폐기 예정 경고 1개)

위 결과는 코드 병합 검증입니다. 실제 SMS 발송, 소셜 공급자 설정, 직원 DB 권한·배정, 푸시 알림까지 검증한 결과는 아닙니다.

## 팀원이 실행하기 전에

Git 병합은 로컬 비밀 설정, 실행 중인 서버, MySQL 데이터 및 마이그레이션 적용을 동기화하지 않습니다.

1. 고객 앱과 직원 앱이 같은 Firebase 프로젝트를 사용하고, 각 앱의 Firebase 구성을 준비했는지 확인합니다.
2. 백엔드 `.env`의 MySQL 접속값과 Firebase 프로젝트·서비스 계정 경로를 확인합니다. 예제 파일로 기존 `.env`를 덮어쓰지 않습니다.
3. 앱 루트의 `social-login.example.json`을 참고해 각자의 `social-login.json`을 준비합니다. 현재 F5 실행 설정은 이 파일을 사용합니다. 기존 `social-login.local.json`도 사용할 수 있지만 실행 명령이나 `.vscode/launch.json`의 파일명을 맞춰야 합니다. 서버의 네이버 비밀키는 백엔드 `.env`에만 둡니다.
4. 실행 중인 이전 FastAPI를 종료하고 이 통합 코드의 `backend`에서 서버를 다시 실행합니다. 8000 포트에 중복 실행하지 않습니다.
5. 앱도 `flutter run --dart-define-from-file=social-login.json`으로 완전히 다시 실행합니다. 에뮬레이터의 API 주소는 `http://10.0.2.2:8000`입니다.
6. 기존 DB의 적용 이력을 확인해 누락된 마이그레이션만 순서대로 적용합니다. 직원 관련 018~024, 고객 관련 025~026을 확인하되, 데이터가 있는 DB에 전체 초기화 스키마를 실행하지 않습니다.

직원 로그인은 Firebase 계정만으로 완료되지 않습니다. 연결된 MySQL의 직원 UID, 활성 직책, 대리점 직원의 활성 지점 배정이 필요합니다.
`.env`, `social-login.json`, `social-login.local.json`, Firebase 서비스 계정 JSON은 Git에 올리지 않습니다.
