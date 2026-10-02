"""Product queries and API response mapping."""

from collections.abc import Mapping, Sequence
from typing import Any

from fastapi import APIRouter, HTTPException
from pymysql import MySQLError

from .database import mysql_connection
from .schemas import ProductOptionResponse, ProductResponse


router = APIRouter(prefix="/products", tags=["products"])


PRODUCT_LIST_SQL = """
SELECT
  p.product_id,
  p.product_name,
  CASE WHEN parent.parent_category_id IS NOT NULL THEN parent.category_name ELSE c.category_name END AS category_name,
  CASE WHEN parent.parent_category_id IS NOT NULL THEN parent.category_name ELSE c.category_name END AS middle_category,
  c.category_name AS subcategory,
  p.price,
  CASE p.gender_code
    WHEN 'M' THEN '남성'
    WHEN 'W' THEN '여성'
    WHEN 'U' THEN '공용'
    WHEN 'K' THEN '키즈'
    ELSE p.gender_code
  END AS gender_name,
  colors.color_code,
  colors.color_name,
  COALESCE(
    (
      SELECT pi.image_url
      FROM product_images pi
      WHERE pi.product_id = p.product_id
        AND pi.color_code = colors.color_code
      ORDER BY pi.is_primary DESC, pi.sort_order, pi.product_image_id
      LIMIT 1
    ),
    (
      SELECT pi.image_url
      FROM product_images pi
      WHERE pi.product_id = p.product_id
      ORDER BY pi.is_primary DESC, pi.sort_order, pi.product_image_id
      LIMIT 1
    ),
    ''
  ) AS image_url,
  (
    SELECT COUNT(*)
    FROM reviews r
    JOIN order_items oi ON oi.order_item_id = r.order_item_id
    JOIN product_variants rv ON rv.product_variant_id = oi.product_variant_id
    WHERE rv.product_id = p.product_id AND r.deleted_at IS NULL
  ) AS review_count,
  (
    SELECT COALESCE(SUM(oi.quantity), 0)
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN product_variants sv ON sv.product_variant_id = oi.product_variant_id
    WHERE sv.product_id = p.product_id
      AND o.order_status IN ('PAID', 'PREPARING', 'SHIPPING', 'READY_FOR_PICKUP', 'COMPLETED')
  ) AS sales_count
FROM products p
JOIN categories c ON c.category_id = p.category_id
LEFT JOIN categories parent ON parent.category_id = c.parent_category_id
JOIN (
  SELECT DISTINCT product_id, color_code, color_name
  FROM product_variants
  WHERE is_active = TRUE
) colors ON colors.product_id = p.product_id
WHERE p.is_active = TRUE
ORDER BY p.product_id, colors.color_code
"""

PRODUCT_OPTIONS_SQL = """
SELECT
  v.product_variant_id,
  v.product_code,
  v.color_name,
  v.size_mm,
  COALESCE(hi.available_quantity, 0) AS available_quantity,
  CASE
    WHEN COALESCE(hi.available_quantity, 0) > 0 THEN 'AVAILABLE'
    WHEN COALESCE(hi.defective_quantity, 0) > 0 THEN 'DEFECTIVE'
    ELSE 'UNAVAILABLE'
  END AS inventory_status
FROM product_variants v
LEFT JOIN headquarters_inventory hi ON hi.product_variant_id = v.product_variant_id
WHERE v.product_id = %s
  AND v.is_active = TRUE
ORDER BY v.color_name, v.size_mm
"""


def group_product_rows(rows: Sequence[Mapping[str, Any]]) -> list[ProductResponse]:
    """Combine one SQL row per color into one Flutter product."""

    grouped: dict[int, dict[str, Any]] = {}
    for row in rows:
        product_id = int(row["product_id"])
        color_name = str(row["color_name"])
        image_url = str(row["image_url"])
        product = grouped.setdefault(
            product_id,
            {
                "id": product_id,
                "name": str(row["product_name"]),
                "category": str(row["category_name"]),
                "price": int(row["price"]),
                "imageUrl": image_url,
                "color": color_name,
                "gender": str(row["gender_name"]),
                "middleCategory": str(row["middle_category"]),
                "subcategory": str(row["subcategory"]),
                "images": {},
                "reviewCount": int(row["review_count"]),
                "salesCount": int(row["sales_count"]),
            },
        )
        product["images"][color_name] = image_url

    return [ProductResponse(**product) for product in grouped.values()]


@router.get("", response_model=list[ProductResponse])
def list_products() -> list[ProductResponse]:
    """Return active products with their color images and summary counts."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(PRODUCT_LIST_SQL)
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return group_product_rows(rows)


@router.get("/{product_id}/options", response_model=list[ProductOptionResponse])
def list_product_options(product_id: int) -> list[ProductOptionResponse]:
    """Return sellable headquarters stock for each active color-size option."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(PRODUCT_OPTIONS_SQL, (product_id,))
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error

    return [
        ProductOptionResponse(
            productVariantId=int(row["product_variant_id"]),
            productCode=str(row["product_code"]),
            color=str(row["color_name"]),
            size=str(row["size_mm"]),
            availableQuantity=int(row["available_quantity"]),
            inventoryStatus=str(row["inventory_status"]),
        )
        for row in rows
    ]
