from app.products import PRODUCT_OPTIONS_SQL, group_product_rows


def test_group_product_rows_combines_color_images() -> None:
    rows = [
        {
            "product_id": 1,
            "product_name": "Silver Current",
            "category_name": "신발",
            "middle_category": "운동화",
            "subcategory": "운동화",
            "price": 129000,
            "gender_name": "남성",
            "color_code": "BLK",
            "color_name": "블랙",
            "image_url": "https://example.com/black.jpg",
            "review_count": 1,
            "sales_count": 1,
        },
        {
            "product_id": 1,
            "product_name": "Silver Current",
            "category_name": "신발",
            "middle_category": "운동화",
            "subcategory": "운동화",
            "price": 129000,
            "gender_name": "남성",
            "color_code": "WHT",
            "color_name": "화이트",
            "image_url": "https://example.com/white.jpg",
            "review_count": 1,
            "sales_count": 1,
        },
    ]

    products = group_product_rows(rows)

    assert len(products) == 1
    assert products[0].id == 1
    assert products[0].color == "블랙"
    assert products[0].images == {
        "블랙": "https://example.com/black.jpg",
        "화이트": "https://example.com/white.jpg",
    }


def test_product_options_use_only_headquarters_inventory() -> None:
    normalized_sql = " ".join(PRODUCT_OPTIONS_SQL.lower().split())

    assert "headquarters_inventory" in normalized_sql
    assert " left join stocks " not in normalized_sql
