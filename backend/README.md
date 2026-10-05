# Shupick API

## Local setup

```powershell
cd C:\My\shupick\backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
```

Edit `.env` with the local MySQL account. To enable Firebase Auth and Firestore
projections, also set `FIREBASE_PROJECT_ID`, `FIREBASE_CREDENTIALS_PATH`, and a
long random `OUTBOX_WORKER_SECRET`. Do not commit `.env` or the service-account JSON.

## Run

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Check `http://127.0.0.1:8000/health` and `http://127.0.0.1:8000/products`.

## Firebase outbox worker

Firestore must first be enabled and a `(default)` database created for
`shupick-71b8f`. Merge the collection rules in `../firestore-status.rules`
into the team's existing rules; deploying that standalone file would replace
rules for other team features. Status documents are server-written and
customer reads require `customerUid` to match the authenticated UID.

The shipping screen subscribes to `orderStatuses/{orderId}` and reloads the
authoritative tracking API when a status changes. Firestore failure leaves
manual refresh available. The publisher resolves ownership from MySQL,
rejects stale event versions, and retries failed deliveries.

Run one batch:

```powershell
.\.venv\Scripts\python.exe -m app.outbox_worker --once
```

Run continuously with a ten-second polling interval:

```powershell
.\.venv\Scripts\python.exe -m app.outbox_worker
```

The protected `POST /internal/outbox/publish` endpoint is available for an
external scheduler. Send the configured secret in `X-Outbox-Secret`.

## Test

## Demo maintenance

Run one batch with `.\.venv\Scripts\python.exe -m app.maintenance_worker --once`,
or run continuously with `.\.venv\Scripts\python.exe -m app.maintenance_worker`.
The process checks every minute and stops when the process or laptop stops.
It expires points, cancels overdue unpaid reservations, assesses the current
month using confirmed purchases in the preceding 12 calendar months, and
issues tier coupon packs through exclusive next-month-start expiration.
Monthly assessment and issuance are idempotent, including catch-up after downtime.
Only orders with `purchase_confirmed_at` participate; pickup completion alone
does not constitute purchase confirmation. Birthday coupons and automatic
purchase confirmation are separate policies, not included in this worker.

```powershell
.\.venv\Scripts\python.exe -m pytest
```


## 직원용 태블릿 로그인

직원 앱은 고객용 앱과 같은 Firebase 프로젝트를 사용합니다. 직원용 Android/iOS 앱은 Firebase 프로젝트에 별도 등록해야 합니다. 앱은 Firebase 이메일·비밀번호 로그인 후 ID 토큰을 `GET /auth/employee/me`에 전달합니다. API는 활성 `employees.firebase_uid`로 직원을 찾고 활성 직책 및 종료되지 않은 소속 지점 배정만 반환합니다.

직원 계정은 앱에서 가입할 수 없습니다. 관리자가 Firebase Authentication에 계정을 만든 다음, 발급된 UID를 해당 `employees.firebase_uid`에 연결하고 `employee_roles`에 직책을 배정합니다. 대리점 직책은 `employee_branch_assignments`에 현재 지점 배정(`ended_at IS NULL`)이 있어야 앱에 들어갈 수 있습니다. 기존 시드 직원의 `legacy-employee-*` UID는 실제 Firebase 계정 UID로 교체해야 합니다.

직원용 앱의 추가 직책 코드 `BRANCH_MANAGER`와 `EXECUTIVE`는 `database/migrations/018_staff_display_roles.sql`에 정의되어 있습니다. 이 마이그레이션을 적용한 뒤 필요한 직원에게 직책을 배정합니다. 직원 인증 API는 지점 배정을 조회하지만 주문·입고·수령 처리 API의 지점별 권한 검사는 별도 작업으로 보완해야 합니다.
