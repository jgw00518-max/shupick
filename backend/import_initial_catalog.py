"""Load the ten-product SHOEPICK catalog without deleting historical products.

Default: read-only preview. --check exercises all writes then rolls them back.
--apply commits one transaction; repeated application does not reset stock.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from app.config import settings
from app.database import mysql_connection


MANIFEST = Path(__file__).resolve().parents[1] / "database/catalog/shoepick_initial_catalog.json"
BACKUPS = Path(__file__).resolve().parent / ".local/catalog-backups"


def load_manifest(path=MANIFEST):
    data = json.loads(path.read_text(encoding="utf-8"))
    products = data["products"]
    models = [p["model"] for p in products]
    if len(products) != 10 or len(set(models)) != 10:
        raise ValueError("Catalog must contain ten distinct model codes")
    if set(models) & set(data["retire_model_codes"]):
        raise ValueError("New and retired products overlap")
    categories = set()
    for category in data["categories"]:
        if category["parent"] is not None and category["parent"] not in categories:
            raise ValueError("Parent categories must come first")
        if category["code"] in categories:
            raise ValueError("Duplicate category code")
        categories.add(category["code"])
    for product in products:
        if (product["gender"] not in {"M", "W", "U", "K"}
                or product["price"] <= 0 or product["stock"] <= 0
                or not product["sizes"] or len(set(product["sizes"])) != len(product["sizes"])
                or any(not isinstance(size, int) or size <= 0 for size in product["sizes"])
                or product["category"] not in categories
                or not data["images"][product["image"]].startswith("https://")):
            raise ValueError(f"Invalid product: {product['model']}")
    return data


def select_models(cursor, models, *, lock=False):
    placeholders = ",".join(["%s"] * len(models))
    cursor.execute(
        f"SELECT * FROM products WHERE model_code IN ({placeholders}) ORDER BY product_id"
        + (" FOR UPDATE" if lock else ""), tuple(models),
    )
    return cursor.fetchall()


def preview(cursor, data):
    models = [p["model"] for p in data["products"]]
    return {
        "target": {"host": settings.mysql_host, "port": settings.mysql_port, "database": settings.mysql_database},
        "products": len(models),
        "options": sum(len(p["sizes"]) for p in data["products"]),
        "initial_units": sum(len(p["sizes"]) * p["stock"] for p in data["products"]),
        "existing_models": [p["model_code"] for p in select_models(cursor, models)],
        "retire_models": [p["model_code"] for p in select_models(cursor, data["retire_model_codes"]) if p["is_active"]],
    }


def insert_catalog(cursor, data):
    brand = data["brand"]
    cursor.execute("SELECT brand_id,brand_name FROM brands WHERE brand_code=%s", (brand["code"],))
    row = cursor.fetchone()
    if row:
        if row["brand_name"] != brand["name"]:
            raise ValueError("Brand code already belongs to a different brand")
        brand_id = row["brand_id"]
    else:
        cursor.execute("INSERT INTO brands(brand_code,brand_name) VALUES(%s,%s)", (brand["code"], brand["name"]))
        brand_id = cursor.lastrowid
    category_ids = {}
    for category in data["categories"]:
        parent_id = category_ids.get(category["parent"])
        cursor.execute("SELECT category_id,parent_category_id,category_name FROM categories WHERE category_code=%s", (category["code"],))
        row = cursor.fetchone()
        if row:
            if row["category_name"] != category["name"] or row["parent_category_id"] != parent_id:
                raise ValueError(f"Category collision: {category['code']}")
            category_ids[category["code"]] = row["category_id"]
        else:
            cursor.execute("INSERT INTO categories(parent_category_id,category_code,category_name) VALUES(%s,%s,%s)",
                           (parent_id, category["code"], category["name"]))
            category_ids[category["code"]] = cursor.lastrowid
    for product in data["products"]:
        cursor.execute("""INSERT INTO products(brand_id,category_id,model_code,product_name,
                       gender_code,product_description,price,is_active) VALUES(%s,%s,%s,%s,%s,%s,%s,1)""",
                       (brand_id, category_ids[product["category"]], product["model"], product["name"],
                        product["gender"], product["description"], product["price"]))
        product_id = cursor.lastrowid
        cursor.execute("INSERT INTO product_images(product_id,color_code,image_url,sort_order,is_primary) VALUES(%s,%s,%s,0,1)",
                       (product_id, product["color_code"], data["images"][product["image"]]))
        for size in product["sizes"]:
            sku = f"{product['model']}-{product['color_code']}-{size}"
            cursor.execute("""INSERT INTO product_variants(product_id,product_code,color_code,color_name,size_mm,
                           additional_price,is_active) VALUES(%s,%s,%s,%s,%s,0,1)""",
                           (product_id, sku, product["color_code"], product["color"], size))
            variant_id = cursor.lastrowid
            quantity = product["stock"]
            cursor.execute("INSERT INTO headquarters_inventory(product_variant_id,on_hand_quantity,reserved_quantity,defective_quantity) VALUES(%s,%s,0,0)",
                           (variant_id, quantity))
            cursor.execute("INSERT INTO inventory_policies(product_variant_id,initial_stock_quantity,reorder_threshold_percent,reorder_quantity) VALUES(%s,%s,30,10)",
                           (variant_id, quantity))
            cursor.execute("""INSERT INTO inventory_movements(product_variant_id,movement_type,on_hand_delta,
                           on_hand_after,reserved_after,defective_after,idempotency_key,reason)
                           VALUES(%s,'INITIAL_STOCK',%s,%s,0,0,%s,%s)""",
                           (variant_id, quantity, quantity, f"shoepick-initial-{sku}", "SHOEPICK 초기 상품 카탈로그 재고"))


def validate_existing(cursor, data, *, initial=False):
    products = select_models(cursor, [p["model"] for p in data["products"]])
    if len(products) != len(data["products"]):
        raise ValueError("Incomplete catalog; no existing records were overwritten")
    by_model = {p["model_code"]: p for p in products}
    for p in data["products"]:
        row = by_model[p["model"]]
        if row["product_name"] != p["name"] or row["price"] != p["price"]:
            raise ValueError(f"Existing catalog differs: {p['model']}; no overwrite")
        cursor.execute("""SELECT v.product_code,hi.on_hand_quantity,hi.reserved_quantity,hi.defective_quantity
                       FROM product_variants v JOIN headquarters_inventory hi USING(product_variant_id)
                       JOIN inventory_policies ip USING(product_variant_id)
                       WHERE v.product_id=%s ORDER BY v.size_mm""", (row["product_id"],))
        options = cursor.fetchall()
        if {v["product_code"] for v in options} != {f"{p['model']}-{p['color_code']}-{size}" for size in p["sizes"]}:
            raise ValueError(f"Option/inventory mismatch: {p['model']}")
        if initial and any(v["on_hand_quantity"] != p["stock"] or v["reserved_quantity"] or v["defective_quantity"] for v in options):
            raise ValueError("Initial inventory validation failed")
        cursor.execute("SELECT COUNT(*) AS count FROM product_images WHERE product_id=%s AND color_code=%s", (row["product_id"], p["color_code"]))
        if cursor.fetchone()["count"] != 1:
            raise ValueError("Product image validation failed")


def apply_catalog(connection, data, *, commit):
    with connection.cursor() as cursor:
        cursor.execute("SELECT GET_LOCK('shoepick.initial_catalog',5) AS acquired")
        if cursor.fetchone()["acquired"] != 1:
            raise RuntimeError("Another catalog import is running")
        try:
            connection.begin()
            existing = select_models(cursor, [p["model"] for p in data["products"]], lock=True)
            if existing:
                validate_existing(cursor, data)
                connection.rollback()
                return {"status": "already_present", "changed": False}
            retired = select_models(cursor, data["retire_model_codes"], lock=True)
            # Capture only catalog metadata. Customer records and credentials are excluded.
            backup_path = None
            if commit:
                BACKUPS.mkdir(parents=True, exist_ok=True)
                backup_path = BACKUPS / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
                with backup_path.open("x", encoding="utf-8") as backup:
                    json.dump({"database": settings.mysql_database, "retired_products": retired,
                               "new_model_codes": [p["model"] for p in data["products"]]}, backup,
                              ensure_ascii=False, indent=2, default=str)
            insert_catalog(cursor, data)
            for row in retired:
                cursor.execute("UPDATE products SET is_active=0 WHERE product_id=%s", (row["product_id"],))
            validate_existing(cursor, data, initial=True)
            if commit:
                connection.commit()
            else:
                connection.rollback()
            return {"status": "applied" if commit else "checked_and_rolled_back", "products": 10,
                    "options": sum(len(p["sizes"]) for p in data["products"]),
                    "hidden_products": len(retired), "backup": str(backup_path) if backup_path else None}
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.execute("SELECT RELEASE_LOCK('shoepick.initial_catalog')")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--check", action="store_true")
    parser.add_argument("--expect-host")
    parser.add_argument("--expect-database")
    args = parser.parse_args()
    if args.apply or args.check:
        if (args.expect_host, args.expect_database) != (settings.mysql_host, settings.mysql_database):
            parser.error("Write/check requires matching --expect-host and --expect-database")
    data = load_manifest()
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            result = preview(cursor, data)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if args.apply or args.check:
            print(json.dumps(apply_catalog(connection, data, commit=args.apply), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
