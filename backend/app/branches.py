"""Customer-facing pickup branch queries."""

from fastapi import APIRouter, HTTPException
from pymysql import MySQLError

from .database import mysql_connection
from .schemas import PickupBranchResponse


router = APIRouter(prefix="/branches", tags=["branches"])

DISTRICT_NAMES = {
    "SEOUL-SEONGDONG": "성동구",
}


@router.get("/pickup", response_model=list[PickupBranchResponse])
def list_pickup_branches() -> list[PickupBranchResponse]:
    """Return active branches that can be selected for pickup."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT branch_id,branch_code,branch_name,district_code,address,phone
                    FROM branches
                    WHERE is_active=TRUE
                    ORDER BY district_code,branch_name,branch_id
                    """
                )
                rows = cursor.fetchall()
                cursor.execute('SELECT bh.* FROM branch_business_hours bh JOIN branches b ON b.branch_id=bh.branch_id WHERE b.is_active=TRUE ORDER BY bh.branch_id,bh.day_of_week')
                hours = {}
                for hour in cursor.fetchall():
                    hours.setdefault(hour['branch_id'], []).append(dict(dayOfWeek=int(hour['day_of_week']), isClosed=bool(hour['is_closed']), opensAt=str(hour['opens_at']) if hour['opens_at'] is not None else None, closesAt=str(hour['closes_at']) if hour['closes_at'] is not None else None))
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error

    return [
        PickupBranchResponse(
            branchId=int(row["branch_id"]),
            branchCode=str(row["branch_code"]),
            branchName=str(row["branch_name"]),
            districtCode=str(row["district_code"]),
            districtName=DISTRICT_NAMES.get(str(row["district_code"]), str(row["district_code"])),
            address=row["address"] or '',
            phone=row["phone"] or '',
            businessHours=hours.get(row['branch_id'], []),
        )
        for row in rows
    ]
