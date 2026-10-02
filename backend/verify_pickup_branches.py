"""Read-only checks for the one-active-branch-per-district demo policy."""
from app.database import mysql_connection
from app.branches import DISTRICT_NAMES, list_pickup_branches


def run():
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT branch_id,branch_name,district_code,is_active FROM branches ORDER BY district_code,branch_id')
            rows=cursor.fetchall()
            cursor.execute('SELECT district_code,COUNT(*) AS count FROM branches WHERE is_active=TRUE GROUP BY district_code HAVING COUNT(*)>1')
            duplicates=cursor.fetchall()
            cursor.execute('SELECT b.branch_id,COUNT(bh.branch_business_hour_id) AS days FROM branches b LEFT JOIN branch_business_hours bh ON bh.branch_id=b.branch_id WHERE b.is_active=TRUE GROUP BY b.branch_id')
            hours=cursor.fetchall()
    branches=list_pickup_branches()
    unknown=[branch.districtCode for branch in branches if branch.districtCode not in DISTRICT_NAMES]
    assert not duplicates, f'Duplicate active districts: {duplicates}'
    assert not unknown, f'Unmapped district codes: {unknown}'
    assert len(branches)==sum(bool(row['is_active']) for row in rows)
    for branch in branches:
        assert branch.districtName==DISTRICT_NAMES[branch.districtCode]
        print(f'branch={branch.branchId}; district={branch.districtName}; name={branch.branchName}; hours={len(branch.businessHours)} days')
    print(f'active_branches={len(branches)}; active_districts={len(set(branch.districtCode for branch in branches))}')
    print(f'partial_or_missing_hours={[row["branch_id"] for row in hours if row["days"]!=7]}')
    print('duplicate_districts=none; district_mapping=ok; data_changes=none')


if __name__=='__main__':
    run()
