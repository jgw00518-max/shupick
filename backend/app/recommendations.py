"""Recommend in-stock products using aggregate co-views and catalog similarity."""

from fastapi import APIRouter, HTTPException, Path, Query
from pymysql import MySQLError

from .database import mysql_connection
from .products import PRODUCT_LIST_BASE_SQL, group_product_rows
from .schemas import ProductRecommendationsResponse


router = APIRouter(prefix="/products", tags=["products"])

# Count each customer once, even after repeat views. A co-view needs at least
# two customers, the same customer's session, and views within thirty minutes.
# No identities, sessions or individual view counts are exposed by the API.
RECOMMENDATIONS_SQL = """
WITH co_views AS (
  SELECT other.product_id, COUNT(DISTINCT seed.customer_id) AS viewers
  FROM customer_interaction_events seed
  JOIN customer_interaction_events other
    ON other.customer_id = seed.customer_id
   AND other.session_key = seed.session_key
   AND other.product_id <> seed.product_id
   AND other.event_type = 'VIEW'
   AND other.occurred_at BETWEEN seed.occurred_at - INTERVAL 30 MINUTE
                             AND seed.occurred_at + INTERVAL 30 MINUTE
  WHERE seed.product_id = %s
    AND seed.event_type = 'VIEW'
    AND seed.occurred_at BETWEEN UTC_TIMESTAMP(6) - INTERVAL 30 DAY AND UTC_TIMESTAMP(6)
    AND other.occurred_at BETWEEN UTC_TIMESTAMP(6) - INTERVAL 30 DAY AND UTC_TIMESTAMP(6)
  GROUP BY other.product_id
  HAVING COUNT(DISTINCT seed.customer_id) >= 2
)
SELECT candidate.product_id, COALESCE(cv.viewers, 0) AS co_viewers
FROM products source
JOIN categories source_category ON source_category.category_id = source.category_id
JOIN products candidate ON candidate.is_active = TRUE AND candidate.product_id <> source.product_id
JOIN categories candidate_category ON candidate_category.category_id = candidate.category_id
LEFT JOIN co_views cv ON cv.product_id = candidate.product_id
WHERE source.product_id = %s AND source.is_active = TRUE
  AND (
    (source.gender_code = 'K' AND candidate.gender_code = 'K')
    OR (source.gender_code = 'M' AND candidate.gender_code IN ('M', 'U'))
    OR (source.gender_code = 'W' AND candidate.gender_code IN ('W', 'U'))
    OR (source.gender_code = 'U' AND candidate.gender_code IN ('M', 'W', 'U'))
  )
  AND EXISTS (
    SELECT 1 FROM product_variants variant
    JOIN headquarters_inventory inventory USING (product_variant_id)
    WHERE variant.product_id = candidate.product_id AND variant.is_active = TRUE
      AND inventory.available_quantity > 0
  )
ORDER BY COALESCE(cv.viewers, 0) DESC,
         (candidate.category_id = source.category_id) DESC,
         (COALESCE(candidate_category.parent_category_id, candidate.category_id)
          = COALESCE(source_category.parent_category_id, source.category_id)) DESC,
         (candidate.gender_code = source.gender_code) DESC,
         (candidate.brand_id = source.brand_id) DESC,
         ABS(CAST(candidate.price AS SIGNED) - CAST(source.price AS SIGNED)), candidate.product_id
LIMIT %s
"""


@router.get("/{product_id}/recommendations", response_model=ProductRecommendationsResponse)
def product_recommendations(
    product_id: int = Path(gt=0), limit: int = Query(default=4, ge=1, le=10),
) -> ProductRecommendationsResponse:
    """Public catalog results; authentication is only needed for recording views."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT product_id FROM products WHERE product_id=%s AND is_active=TRUE",
                    (product_id,),
                )
                if cursor.fetchone() is None:
                    raise HTTPException(404, "Product not found")
                cursor.execute(RECOMMENDATIONS_SQL, (product_id, product_id, limit))
                ranked = cursor.fetchall()
                if not ranked:
                    return ProductRecommendationsResponse(products=[])
                ids = [int(row["product_id"]) for row in ranked]
                placeholders = ",".join(["%s"] * len(ids))
                cursor.execute(
                    PRODUCT_LIST_BASE_SQL
                    + f"\nAND p.product_id IN ({placeholders}) ORDER BY p.product_id, colors.color_code",
                    tuple(ids),
                )
                products = {product.id: product for product in group_product_rows(cursor.fetchall())}
    except MySQLError as error:
        raise HTTPException(503, "Database unavailable") from error
    return ProductRecommendationsResponse(
        products=[products[identifier] for identifier in ids if identifier in products],
        coViewedProductIds=[
            int(row["product_id"]) for row in ranked
            if row["co_viewers"] > 0 and int(row["product_id"]) in products
        ],
    )
