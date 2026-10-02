from app.branches import DISTRICT_NAMES


def test_seongdong_district_name_mapping() -> None:
    assert DISTRICT_NAMES["SEOUL-SEONGDONG"] == "성동구"
