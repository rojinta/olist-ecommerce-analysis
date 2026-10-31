-- 06_concentration.sql : Q5 Where does the money and the pain concentrate?
-- Window orders that were delivered. Revenue = item price.

create or replace table seller_stats as
select i.seller_id, s.state,
       count(distinct i.order_id)                                                as orders,
       sum(i.price)                                                              as revenue,
       count(distinct i.order_id) filter (where f.days_late > 0)                 as late_orders,
       avg(f.review_score)                                                       as avg_score
from items i
join order_facts f using (order_id)
join sellers s using (seller_id)
where f.in_window and f.is_delivered
group by 1, 2;

create or replace table out_seller_concentration as
with r as (
    select *, row_number() over (order by revenue desc) as rk, count(*) over () as n,
           sum(revenue) over () as total from seller_stats
)
select max(n) as sellers,
       round(100.0 * sum(revenue) filter (where rk <= 10)              / max(total), 1) as top_10_sellers_pct,
       round(100.0 * sum(revenue) filter (where rk <= ceil(n * 0.01))  / max(total), 1) as top_1pct_pct,
       round(100.0 * sum(revenue) filter (where rk <= ceil(n * 0.10))  / max(total), 1) as top_10pct_pct,
       round(100.0 * sum(revenue) filter (where rk <= ceil(n * 0.50))  / max(total), 1) as top_half_pct,
       count(*) filter (where orders = 1) as sellers_with_one_order
from r;

-- Share of revenue held by the top k percent of sellers, k = 0 to 100
create or replace table out_seller_curve as
with r as (
    select revenue, row_number() over (order by revenue desc) as rk, count(*) over () as n from seller_stats
), k as (select unnest(range(0, 101)) as pct_sellers)
select k.pct_sellers,
       round(100.0 * coalesce(sum(r.revenue) filter (where r.rk <= ceil(r.n * k.pct_sellers / 100.0)), 0) / sum(r.revenue), 1) as pct_revenue
from k cross join r group by 1 order by 1;

-- Sellers with at least 30 delivered orders: how do late rate and review score vary?
create or replace table out_seller_quality as
select seller_id, state, orders, round(revenue) as revenue_brl,
       round(100.0 * late_orders / orders, 1) as pct_late, round(avg_score, 2) as avg_score
from seller_stats where orders >= 30 order by revenue desc;

create or replace table out_seller_quality_summary as
select count(*) as sellers_with_30_plus_orders,
       round(corr(100.0 * late_orders / orders, avg_score), 2) as corr_late_vs_score,
       round(median(100.0 * late_orders / orders), 1) as median_pct_late,
       count(*) filter (where 100.0 * late_orders / orders > 15) as sellers_over_15pct_late
from seller_stats where orders >= 30;

-- Categories: revenue, late rate and review score side by side
create or replace table out_category_quality as
with c as (
    select p.category, f.order_id, any_value(f.days_late) as days_late, any_value(f.review_score) as review_score,
           sum(i.price) as revenue, sum(i.freight) as freight
    from items i join order_facts f using (order_id) join products p using (product_id)
    where f.in_window and f.is_delivered
    group by 1, 2
)
select category, count(*) as orders, round(sum(revenue)) as revenue_brl,
       round(100.0 * count(*) filter (where days_late > 0) / count(*), 1) as pct_late,
       round(avg(review_score), 2) as avg_score,
       round(100.0 * sum(freight) / sum(revenue), 1) as freight_pct_of_price
from c group by 1 having count(*) >= 300 order by revenue_brl desc;
