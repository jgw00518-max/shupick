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
