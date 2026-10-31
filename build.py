"""Load the Olist CSV files into DuckDB, run sql/*.sql in order, write results/out_*.csv.
Usage: python3 build.py [raw_dir]   (default: data/raw)"""
import sys, pathlib, duckdb

root = pathlib.Path(__file__).parent
raw = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "raw"
db = root / "olist.duckdb"
if db.exists():
    db.unlink()
con = duckdb.connect(str(db))

files = {
    "orders_raw": "olist_orders_dataset.csv", "customers_raw": "olist_customers_dataset.csv",
    "items_raw": "olist_order_items_dataset.csv", "payments_raw": "olist_order_payments_dataset.csv",
    "reviews_raw": "olist_order_reviews_dataset.csv", "products_raw": "olist_products_dataset.csv",
    "sellers_raw": "olist_sellers_dataset.csv", "translation_raw": "product_category_name_translation.csv",
}
for t, f in files.items():
    # everything is read as text first; the SQL casts what it needs
    con.execute(f"create table {t} as select * from read_csv('{raw / f}', all_varchar=true, header=true, quote='\"', escape='\"')")

for sql in sorted((root / "sql").glob("*.sql")):
    con.execute(sql.read_text())
    print("ran", sql.name)

out = root / "results"
out.mkdir(exist_ok=True)
for (t,) in con.execute("select table_name from information_schema.tables where table_name like 'out_%' order by 1").fetchall():
    con.execute(f"copy {t} to '{out / (t + '.csv')}' (header)")
    print("wrote", t, con.execute(f"select count(*) from {t}").fetchone()[0], "rows")
