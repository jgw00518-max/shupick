"""FastAPI application entrypoint."""

from fastapi import FastAPI, HTTPException
from pymysql import MySQLError

from .auth import router as auth_router
from .database import mysql_connection
from .orders import router as orders_router
from .outbox import router as outbox_router
from .points import router as points_router
from .procurement import audit_router, router as procurement_router
from .products import router as products_router
from .refunds import router as refunds_router
from .status_history import router as status_history_router


app = FastAPI(title="Shupick API", version="0.1.0")
app.include_router(auth_router)
app.include_router(products_router)
app.include_router(refunds_router)
app.include_router(orders_router)
app.include_router(status_history_router)
app.include_router(outbox_router)
app.include_router(points_router)
app.include_router(procurement_router)
app.include_router(audit_router)


@app.get("/health")
def health() -> dict[str, str]:
    """Verify both the API process and its MySQL connection."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT DATABASE() AS database_name")
                row = cursor.fetchone()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error

    return {"status": "ok", "database": str(row["database_name"])}
