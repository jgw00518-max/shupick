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

```powershell
.\.venv\Scripts\python.exe -m pytest
```
