"""Configure one fictional SHOEPICK pickup branch in every Seoul district.

Default is read-only preview. --check rolls back all changes; --apply commits.
Existing branch IDs/codes, orders, stock and staff assignments are preserved.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

from app.branches import DISTRICT_NAMES
from app.config import settings
from app.database import mysql_connection


def branch_plan():
    aliases = {"SEOUL-GANGNAM": "SEL-GN", "SEOUL-SEONGDONG": "SEL-SD"}
    return [
        dict(
            district_code=code,
            branch_code=aliases.get(code, "SEL-" + code.removeprefix("SEOUL-")),
            branch_name="SHOEPICK " + (name if name == "중구" else name.removesuffix("구")) + "점",
            address=f"서울특별시 {name} 가상로 {100 + index}, 1층",
            phone=f"02-0000-{1000 + index:04d}",
        )
        for index, (code, name) in enumerate(DISTRICT_NAMES.items(), start=1)
    ]


def existing_branches(cursor, plan, *, lock=False):
    placeholders = ",".join(["%s"] * len(plan))
    cursor.execute(
        f"SELECT * FROM branches WHERE district_code IN ({placeholders}) "
        f"OR branch_code IN ({placeholders}) ORDER BY branch_id" + (" FOR UPDATE" if lock else ""),
        tuple(row["district_code"] for row in plan) + tuple(row["branch_code"] for row in plan),
    )
    rows = cursor.fetchall()
    selected = {}
    for target in plan:
        matches = [row for row in rows if row["district_code"] == target["district_code"]
                   or row["branch_code"] == target["branch_code"]]
        if len(matches) > 1:
            raise ValueError(f"Multiple existing branches in {target['district_code']}; no changes made")
        if matches:
            row = matches[0]
            if row["district_code"] not in {target["district_code"], "UNASSIGNED"}:
                raise ValueError(f"Branch code is assigned to another district: {row['branch_code']}")
            selected[target["district_code"]] = row
    return rows, selected


def configure(connection, plan, *, commit):
    with connection.cursor() as cursor:
        cursor.execute("SELECT GET_LOCK('shoepick.seoul_pickup_branches',5) AS acquired")
        if cursor.fetchone()["acquired"] != 1:
            raise RuntimeError("Another Seoul branch setup is running")
        try:
            connection.begin()
            rows, selected = existing_branches(cursor, plan, lock=True)
            backup_path = None
            if commit:
                cursor.execute("""SELECT h.* FROM branch_business_hours h JOIN branches b USING(branch_id)
                    WHERE b.district_code LIKE 'SEOUL-%%' OR b.branch_code IN ('SEL-SD','SEL-GN')
                    ORDER BY h.branch_id,h.day_of_week""")
                hours = cursor.fetchall()
                directory = Path(__file__).resolve().parent / ".local/branch-backups"
                directory.mkdir(parents=True, exist_ok=True)
                backup_path = directory / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
                with backup_path.open("x", encoding="utf-8") as file:
                    json.dump(dict(database=settings.mysql_database, branches=rows, business_hours=hours),
                              file, ensure_ascii=False, indent=2, default=str)
            identifiers = []
            for target in plan:
                old = selected.get(target["district_code"])
                if old:
                    identifier = old["branch_id"]
                    cursor.execute("""UPDATE branches SET branch_name=%s,district_code=%s,address=%s,phone=%s,
                        latitude=NULL,longitude=NULL,is_active=TRUE WHERE branch_id=%s""",
                        (target["branch_name"], target["district_code"], target["address"], target["phone"], identifier))
                else:
                    cursor.execute("""INSERT INTO branches
                        (branch_code,branch_name,district_code,address,phone,is_active) VALUES(%s,%s,%s,%s,%s,TRUE)""",
                        tuple(target[key] for key in ("branch_code", "branch_name", "district_code", "address", "phone")))
                    identifier = cursor.lastrowid
                identifiers.append(identifier)
                for day in range(1, 8):
                    opens = None if day == 7 else "10:30:00"
                    closes = None if day == 7 else "20:00:00"
                    cursor.execute("""INSERT INTO branch_business_hours
                        (branch_id,day_of_week,opens_at,closes_at,is_closed) VALUES(%s,%s,%s,%s,%s)
                        ON DUPLICATE KEY UPDATE opens_at=%s,closes_at=%s,is_closed=%s""",
                        (identifier, day, opens, closes, day == 7, opens, closes, day == 7))
            placeholders = ",".join(["%s"] * len(identifiers))
            cursor.execute(f"SELECT branch_id,day_of_week,opens_at,closes_at,is_closed "
                           f"FROM branch_business_hours WHERE branch_id IN ({placeholders})", tuple(identifiers))
            hours = cursor.fetchall()
            if len(identifiers) != 25 or len(set(identifiers)) != 25 or len(hours) != 175:
                raise ValueError("Expected 25 distinct branches and 175 business-hour records")
            for hour in hours:
                closed = hour["day_of_week"] == 7
                if bool(hour["is_closed"]) != closed or (
                    (hour["opens_at"] is not None or hour["closes_at"] is not None) if closed
                    else (str(hour["opens_at"]) != "10:30:00" or str(hour["closes_at"]) != "20:00:00")
                ):
                    raise ValueError("Business-hour validation failed")
            if commit:
                connection.commit()
            else:
                connection.rollback()
            return dict(status="applied" if commit else "checked_and_rolled_back", districts=25,
                        new_branches=25-len(selected), updated_branches=len(selected), business_hours=175,
                        backup=str(backup_path) if backup_path else None)
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.execute("SELECT RELEASE_LOCK('shoepick.seoul_pickup_branches')")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--check", action="store_true")
    parser.add_argument("--expect-host")
    parser.add_argument("--expect-database")
    args = parser.parse_args()
    if (args.apply or args.check) and (args.expect_host, args.expect_database) != (
        settings.mysql_host, settings.mysql_database,
    ):
        parser.error("Write/check requires matching --expect-host and --expect-database")
    plan = branch_plan()
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            _, selected = existing_branches(cursor, plan)
        print(json.dumps(dict(target=dict(host=settings.mysql_host, port=settings.mysql_port,
                                         database=settings.mysql_database),
                              districts=len(plan), new_branches=25-len(selected),
                              updated_branches=len(selected), branches=plan), ensure_ascii=False, indent=2))
        if args.apply or args.check:
            print(json.dumps(configure(connection, plan, commit=args.apply), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
