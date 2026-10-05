"""Customer-facing pickup branch queries."""

from fastapi import APIRouter, HTTPException
from pymysql import MySQLError

from .database import mysql_connection
from .schemas import PickupBranchResponse


router = APIRouter(prefix="/branches", tags=["branches"])

DISTRICT_NAMES = {
    "SEOUL-GANGNAM": "강남구",
    "SEOUL-GANGDONG": "강동구",
    "SEOUL-GANGBUK": "강북구",
    "SEOUL-GANGSEO": "강서구",
    "SEOUL-GWANAK": "관악구",
    "SEOUL-GWANGJIN": "광진구",
    "SEOUL-GURO": "구로구",
    "SEOUL-GEUMCHEON": "금천구",
    "SEOUL-NOWON": "노원구",
    "SEOUL-DOBONG": "도봉구",
    "SEOUL-DONGDAEMUN": "동대문구",
    "SEOUL-DONGJAK": "동작구",
    "SEOUL-MAPO": "마포구",
    "SEOUL-SEODAEMUN": "서대문구",
    "SEOUL-SEOCHO": "서초구",
    "SEOUL-SEONGDONG": "성동구",
    "SEOUL-SEONGBUK": "성북구",
    "SEOUL-SONGPA": "송파구",
    "SEOUL-YANGCHEON": "양천구",
    "SEOUL-YEONGDEUNGPO": "영등포구",
    "SEOUL-YONGSAN": "용산구",
    "SEOUL-EUNPYEONG": "은평구",
    "SEOUL-JONGNO": "종로구",
    "SEOUL-JUNG": "중구",
    "SEOUL-JUNGNANG": "중랑구",
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
