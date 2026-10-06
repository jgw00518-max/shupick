"""FastAPI application entrypoint."""

from fastapi import FastAPI, HTTPException
from pymysql import MySQLError

from .auth import router as auth_router
from .staff_registration import router as staff_registration_router
from .staff_orders import router as staff_orders_router
from .customer_enrollment import router as enrollment_router
from .social_auth import router as social_auth_router, install_social_auth_access_log_filter
from .staff_work import router as staff_work_router
from .staff_returns import router as staff_returns_router
from .staff_refunds import router as staff_refunds_router
from .branches import router as branches_router
from .checkout_benefits import router as benefits_router
from .database import mysql_connection
from .orders import router as orders_router
from .order_queries import router as order_queries_router
from .outbox import router as outbox_router
from .points import router as points_router
from .procurement import audit_router, router as procurement_router
from .products import router as products_router
from .refunds import router as refunds_router
from .returns import router as returns_router
from .reviews import router as reviews_router
from .interactions import router as interactions_router
from .support import router as support_router
from .catalog import router as catalog_router
from .account_benefits import router as account_benefits_router
from .pickup_tracking import router as pickup_router
from .status_history import router as status_history_router


install_social_auth_access_log_filter()
app = FastAPI(title="Shupick API", version="0.1.0")
app.include_router(auth_router)
app.include_router(staff_registration_router)
app.include_router(staff_orders_router)
app.include_router(enrollment_router)
app.include_router(social_auth_router)
app.include_router(staff_work_router)
app.include_router(staff_returns_router)
app.include_router(staff_refunds_router)
app.include_router(branches_router)
app.include_router(benefits_router)
app.include_router(products_router)
app.include_router(refunds_router)
app.include_router(returns_router)
app.include_router(reviews_router)
app.include_router(interactions_router)
app.include_router(support_router)
app.include_router(catalog_router)
app.include_router(account_benefits_router)
app.include_router(pickup_router)
app.include_router(orders_router)
app.include_router(order_queries_router)
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
