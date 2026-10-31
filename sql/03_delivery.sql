-- 03_delivery.sql : Q2 How well does delivery work?
-- Delivered orders only (status delivered with a delivery date). Late = delivered on a later calendar day than the estimate.

create or replace table out_delivery_summary as
select count(*)                                                         as delivered_orders,
       round(median(delivery_days), 1)                                  as median_delivery_days,
       round(quantile_cont(delivery_days, 0.9), 1)                      as p90_delivery_days,
       round(median(date_diff('day', cast(purchase_ts as date), estimated_date)), 1) as median_promised_days,
       count(*) filter (where days_late > 0)                            as late_orders,
       round(100.0 * count(*) filter (where days_late > 0) / count(*), 1) as pct_late,
       round(median(days_late), 1)                                      as median_days_vs_estimate,
       round(100.0 * count(*) filter (where days_late <= -7) / count(*), 1) as pct_a_week_early_or_more,
       -- sensitivity: lateness measured by timestamp instead of calendar day
       (select count(*) from orders o join order_facts f using (order_id)
        where f.in_window and f.is_delivered and o.delivered_ts > o.estimated_ts)           as late_by_timestamp
from order_facts where in_window and is_delivered;

-- days relative to the estimate, in one-day steps from 30 days early to 30 days late (outer values grouped)
create or replace table out_days_vs_estimate as
select greatest(-30, least(30, days_late)) as days_vs_estimate, count(*) as orders
from order_facts where in_window and is_delivered
group by 1 order by 1;

create or replace table out_state_delivery as
select state, count(*) as orders,
       round(median(delivery_days), 1)                                    as median_delivery_days,
       round(100.0 * count(*) filter (where days_late > 0) / count(*), 1) as pct_late,
       round(100.0 * sum(freight) / sum(items_price), 1)                  as freight_pct_of_price
from order_facts where in_window and is_delivered
group by 1 having count(*) >= 500
order by median_delivery_days desc;
