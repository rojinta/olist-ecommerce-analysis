-- 04_reviews.sql : Q3 Does a late delivery hurt reviews?
-- Delivered orders that have a review. Review = the most recent one per order.

create or replace table out_review_coverage as
select count(*) as delivered_orders, count(review_score) as with_review,
       round(100.0 * count(review_score) / count(*), 1) as pct_with_review
from order_facts where in_window and is_delivered;

create or replace table out_review_by_lateness as
with b as (
    select review_score,
           case when days_late <= -8 then 1 when days_late <= -1 then 2 when days_late = 0 then 3
                when days_late <= 3 then 4 when days_late <= 7 then 5 when days_late <= 14 then 6 else 7 end as ord,
           case when days_late <= -8 then 'More than 7 days early' when days_late <= -1 then '1 to 7 days early'
                when days_late = 0 then 'On the estimated day' when days_late <= 3 then '1 to 3 days late'
                when days_late <= 7 then '4 to 7 days late' when days_late <= 14 then '8 to 14 days late'
                else 'More than 14 days late' end as bucket
    from order_facts where in_window and is_delivered and review_score is not null
)
select ord, bucket, count(*) as reviewed_orders,
       round(avg(review_score), 2)                                          as avg_score,
       round(100.0 * count(*) filter (where review_score = 1) / count(*), 1) as pct_one_star,
       round(100.0 * count(*) filter (where review_score = 5) / count(*), 1) as pct_five_star
from b group by 1, 2 order by 1;

create or replace table out_review_late_vs_ontime as
select case when days_late > 0 then 'Late' else 'On time or early' end as delivery,
       review_score, count(*) as orders
from order_facts where in_window and is_delivered and review_score is not null
group by 1, 2 order by 1, 2;

-- Is it just a mix effect? Compare late and on-time orders inside each of the biggest states and categories.
create or replace table out_late_effect_by_state as
with s as (
    select state, count(*) as reviewed_orders,
           avg(review_score) filter (where days_late > 0)  as late_score,
           avg(review_score) filter (where days_late <= 0) as ontime_score,
           count(*) filter (where days_late > 0)           as late_orders
    from order_facts where in_window and is_delivered and review_score is not null
    group by 1
)
select state, reviewed_orders, late_orders, round(ontime_score, 2) as ontime_score, round(late_score, 2) as late_score,
       round(ontime_score - late_score, 2) as score_gap
from s where reviewed_orders >= 3000 order by reviewed_orders desc;

create or replace table out_late_effect_by_category as
with c as (
    select p.category, f.order_id, f.review_score, f.days_late
    from items i join order_facts f using (order_id) join products p using (product_id)
    where f.in_window and f.is_delivered and f.review_score is not null
    group by 1, 2, 3, 4
), s as (
    select category, count(*) as reviewed_orders,
           avg(review_score) filter (where days_late > 0)  as late_score,
           avg(review_score) filter (where days_late <= 0) as ontime_score,
           count(*) filter (where days_late > 0)           as late_orders
    from c group by 1
)
select category, reviewed_orders, late_orders, round(ontime_score, 2) as ontime_score, round(late_score, 2) as late_score,
       round(ontime_score - late_score, 2) as score_gap
from s where reviewed_orders >= 3000 order by reviewed_orders desc;
