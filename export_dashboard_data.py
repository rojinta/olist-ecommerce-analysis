"""Write the small CSV files behind the dashboard from results/out_*.csv."""
import pathlib, pandas as pd

root = pathlib.Path(__file__).parent
res, out = root / "results", root / "dashboard_data"
out.mkdir(exist_ok=True)
r = lambda n: pd.read_csv(res / f"out_{n}.csv")

h, d, rs = r("headline").iloc[0], r("delivery_summary").iloc[0], r("retention_summary").iloc[0]
lv = r("review_late_vs_ontime")
def score(group):
    x = lv[lv.delivery == group]; return (x.review_score * x.orders).sum() / x.orders.sum()
def one_star(group):
    x = lv[lv.delivery == group]; return 100 * x[x.review_score == 1].orders.sum() / x.orders.sum()
sc, sq, cat = r("seller_concentration").iloc[0], r("seller_quality_summary").iloc[0], r("category")
cov = r("review_coverage").iloc[0]
head = {
    "window_label": "January 2017 to August 2018",
    "orders_placed": h.orders_placed, "orders_delivered": h.orders_delivered, "revenue_brl": h.revenue_brl,
    "freight_brl": h.freight_brl, "customers": h.customers, "avg_order_value_brl": h.avg_order_value_brl,
    "pct_canceled_or_unavailable": round(100 * h.orders_canceled_or_unavailable / h.orders_placed, 1),
    "median_delivery_days": d.median_delivery_days, "p90_delivery_days": d.p90_delivery_days,
    "median_promised_days": d.median_promised_days, "pct_late": d.pct_late, "late_orders": d.late_orders,
    "late_by_timestamp": d.late_by_timestamp, "pct_week_early": d.pct_a_week_early_or_more,
    "pct_with_review": cov.pct_with_review,
    "score_ontime": round(score("On time or early"), 2), "score_late": round(score("Late"), 2),
    "pct_one_star_ontime": round(one_star("On time or early"), 1), "pct_one_star_late": round(one_star("Late"), 1),
    "pct_came_back": rs.pct_came_back, "retention_customers": rs.customers, "came_back": rs.came_back,
    "n_categories": len(cat), "top10_categories_pct": cat.cumulative_pct.iloc[9],
    "sellers": sc.sellers, "top_1pct_sellers_pct": sc.top_1pct_pct, "top_10pct_sellers_pct": sc.top_10pct_pct,
    "top_half_sellers_pct": sc.top_half_pct, "sellers_30plus": sq.sellers_with_30_plus_orders,
    "corr_late_score": sq.corr_late_vs_score, "sellers_over_15pct_late": sq.sellers_over_15pct_late,
}
pd.DataFrame([head]).to_csv(out / "headline.csv", index=False)

m = r("monthly"); m["month"] = m["month"].astype(str).str[:7]; m.to_csv(out / "monthly.csv", index=False)
cq = r("category_quality"); total = cat.revenue_brl.sum()
cq["pct_of_revenue"] = (100 * cq.revenue_brl / total).round(1)
cq.to_csv(out / "categories.csv", index=False)
r("state_delivery").to_csv(out / "states.csv", index=False)
r("days_vs_estimate").to_csv(out / "days_vs_estimate.csv", index=False)
r("review_by_lateness").to_csv(out / "review_by_lateness.csv", index=False)
r("late_effect_by_category").to_csv(out / "late_effect.csv", index=False)
c = r("retention_cohort"); c["cohort"] = c["cohort"].astype(str).str[:7]; c.to_csv(out / "retention_cohorts.csv", index=False)
r("retention_by_first_experience").to_csv(out / "retention_first.csv", index=False)
r("seller_curve").to_csv(out / "seller_curve.csv", index=False)
r("seller_quality")[["seller_id", "state", "orders", "revenue_brl", "pct_late", "avg_score"]].to_csv(out / "sellers.csv", index=False)
print({p.name: p.stat().st_size for p in sorted(out.glob("*.csv"))})
