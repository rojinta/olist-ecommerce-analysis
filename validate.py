"""Independent check: recompute the main result tables with pandas straight from the raw CSV files (no SQL)
and compare them with results/out_*.csv. Usage: python3 validate.py [raw_dir]"""
import sys, pathlib, numpy as np, pandas as pd

root = pathlib.Path(__file__).parent
raw = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "raw"
res = root / "results"
rd = lambda f, **k: pd.read_csv(raw / f, encoding="utf-8-sig", **k)

o = rd("olist_orders_dataset.csv", parse_dates=["order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date"])
c = rd("olist_customers_dataset.csv")
it = rd("olist_order_items_dataset.csv")
rv = rd("olist_order_reviews_dataset.csv", parse_dates=["review_answer_timestamp", "review_creation_date"])
p = rd("olist_products_dataset.csv")
tr = rd("product_category_name_translation.csv")
se = rd("olist_sellers_dataset.csv")

# review: latest per order
rv = rv.sort_values(["order_id", "review_answer_timestamp", "review_creation_date", "review_id"]).groupby("order_id").tail(1)[["order_id", "review_score"]]
p = p.merge(tr, on="product_category_name", how="left")
p["category"] = p["product_category_name_english"].fillna(p["product_category_name"]).fillna("unknown")

o = o.merge(c[["customer_id", "customer_unique_id", "customer_state"]], on="customer_id").merge(rv, on="order_id", how="left")
agg = it.groupby("order_id").agg(price=("price", "sum"), freight=("freight_value", "sum")).reset_index()
o = o.merge(agg, on="order_id", how="left")
o["win"] = (o.order_purchase_timestamp >= "2017-01-01") & (o.order_purchase_timestamp < "2018-09-01")
o["deliv"] = (o.order_status == "delivered") & o.order_delivered_customer_date.notna()
o["days"] = (o.order_delivered_customer_date - o.order_purchase_timestamp).dt.total_seconds() / 86400
o["late_days"] = (o.order_delivered_customer_date.dt.normalize() - o.order_estimated_delivery_date.dt.normalize()).dt.days

bad = 0
def check(name, got, want, tol=0.051):
    global bad
    ok = abs(float(got) - float(want)) <= tol
    bad += not ok
    print(("ok   " if ok else "FAIL ") + f"{name}: pandas={got} sql={want}")

w = o[o.win]; d = w[w.deliv]
h = pd.read_csv(res / "out_headline.csv").iloc[0]
check("orders placed", len(w), h.orders_placed, 0)
check("delivered", len(d), h.orders_delivered, 0)
check("canceled/unavailable", w.order_status.isin(["canceled", "unavailable"]).sum(), h.orders_canceled_or_unavailable, 0)
check("revenue", round(d.price.sum()), h.revenue_brl, 1)
check("freight", round(d.freight.sum()), h.freight_brl, 1)
check("customers", w.customer_unique_id.nunique(), h.customers, 0)
check("avg order value", round(d.price.sum() / len(d), 1), h.avg_order_value_brl)

s = pd.read_csv(res / "out_delivery_summary.csv").iloc[0]
check("median delivery days", round(d.days.median(), 1), s.median_delivery_days)
check("p90 delivery days", round(d.days.quantile(0.9), 1), s.p90_delivery_days)
check("late orders", (d.late_days > 0).sum(), s.late_orders, 0)
check("pct late", round(100 * (d.late_days > 0).mean(), 1), s.pct_late)
check("late by timestamp", (d.order_delivered_customer_date > d.order_estimated_delivery_date).sum(), s.late_by_timestamp, 0)
check("median days vs estimate", d.late_days.median(), s.median_days_vs_estimate)

m = pd.read_csv(res / "out_monthly.csv", parse_dates=["month"])
g = w.assign(month=w.order_purchase_timestamp.dt.to_period("M").dt.to_timestamp()).groupby("month")
mo = pd.DataFrame({"n": g.size(), "rev": w[w.deliv].assign(month=w.order_purchase_timestamp.dt.to_period("M").dt.to_timestamp()).groupby("month").price.sum().round()})
mm = m.set_index("month").join(mo)
check("monthly orders max diff", (mm.orders - mm.n).abs().max(), 0, 0)
check("monthly revenue max diff", (mm.revenue_brl - mm.rev).abs().max(), 0, 1)

# review by lateness
r = d.dropna(subset=["review_score"])
bins = [(-999, -8), (-7, -1), (0, 0), (1, 3), (4, 7), (8, 14), (15, 999)]
rb = pd.read_csv(res / "out_review_by_lateness.csv").sort_values("ord")
for (lo, hi), (_, row) in zip(bins, rb.iterrows()):
    x = r[(r.late_days >= lo) & (r.late_days <= hi)]
    check(f"review bucket {row.bucket} n", len(x), row.reviewed_orders, 0)
    check(f"review bucket {row.bucket} avg", round(x.review_score.mean(), 2), row.avg_score, 0.006)

# category revenue
pc = it.merge(p[["product_id", "category"]], on="product_id").merge(d[["order_id"]], on="order_id")
cat = pc.groupby("category").price.sum().sort_values(ascending=False)
oc = pd.read_csv(res / "out_category.csv")
check("categories", len(cat), len(oc), 0)
check("top category revenue", round(cat.iloc[0]), oc.revenue_brl.iloc[0], 1)
check("top-10 cumulative pct", round(100 * cat.iloc[:10].sum() / cat.sum(), 1), oc.cumulative_pct.iloc[9])

# state delivery
sd = pd.read_csv(res / "out_state_delivery.csv")
for _, row in sd.iterrows():
    x = d[d.customer_state == row.state]
    check(f"state {row.state} median days", round(x.days.median(), 1), row.median_delivery_days)
    check(f"state {row.state} pct late", round(100 * (x.late_days > 0).mean(), 1), row.pct_late)

# retention: ignore canceled/unavailable; return = later calendar day within 180 days
co = o[~o.order_status.isin(["canceled", "unavailable"])].copy()
co["day"] = co.order_purchase_timestamp.dt.normalize()
first = co.groupby("customer_unique_id").day.min().rename("first").reset_index()
end = o.order_purchase_timestamp.max().normalize()
first = first[(first["first"] >= "2017-01-01") & (first["first"] + pd.Timedelta(days=180) <= end)]
x = co.merge(first, on="customer_unique_id")
back = x[(x.day > x["first"]) & (x.day <= x["first"] + pd.Timedelta(days=180))].customer_unique_id.nunique()
rs = pd.read_csv(res / "out_retention_summary.csv").iloc[0]
check("retention customers", len(first), rs.customers, 0)
check("retention came back", back, rs.came_back, 0)

# seller concentration
sx = it.merge(d[["order_id"]], on="order_id").groupby("seller_id").price.sum().sort_values(ascending=False)
sc = pd.read_csv(res / "out_seller_concentration.csv").iloc[0]
check("sellers", len(sx), sc.sellers, 0)
check("top 10 sellers pct", round(100 * sx.iloc[:10].sum() / sx.sum(), 1), sc.top_10_sellers_pct)
check("top 10% sellers pct", round(100 * sx.iloc[:int(np.ceil(len(sx) * .1))].sum() / sx.sum(), 1), sc.top_10pct_pct)

print("\nALL MATCH" if not bad else f"\n{bad} MISMATCHES")
sys.exit(1 if bad else 0)
