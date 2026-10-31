-- 05_retention.sql : Q4 Do customers come back?
-- A customer is the person (customer_unique_id). Orders that were canceled or unavailable are ignored.
-- "Came back" = placed another order on a LATER CALENDAR DAY within 180 days of the first order
-- (926 customer-days have several orders on one day; those are one shopping trip, not a return).
-- Only customers whose first order is early enough to have a full 180 days of follow-up are counted.

create or replace table cust_orders as
select customer_unique_id, order_id, purchase_ts, cast(purchase_ts as date) as purchase_date
from order_facts where status not in ('canceled', 'unavailable');

create or replace table cust_first as
select customer_unique_id, min(purchase_ts) as first_ts, cast(min(purchase_ts) as date) as first_date
from cust_orders group by 1;

create or replace table out_retention_summary as
with last_day as (select cast(max(purchase_ts) as date) as d from order_facts),
c as (
    select f.customer_unique_id, f.first_date,
           exists (select 1 from cust_orders o
                   where o.customer_unique_id = f.customer_unique_id
                     and o.purchase_date > f.first_date
                     and o.purchase_date <= f.first_date + 180) as came_back
    from cust_first f, last_day
    where f.first_date >= date '2017-01-01' and f.first_date + 180 <= last_day.d
)
select count(*) as customers, count(*) filter (where came_back) as came_back,
       round(100.0 * count(*) filter (where came_back) / count(*), 1) as pct_came_back,
       (select d from last_day) as data_ends,
       min(first_date) as first_cohort_date, max(first_date) as last_cohort_date
from c;

create or replace table out_retention_cohort as
with last_day as (select cast(max(purchase_ts) as date) as d from order_facts),
c as (
    select f.customer_unique_id, cast(date_trunc('month', f.first_date) as date) as cohort,
           exists (select 1 from cust_orders o
                   where o.customer_unique_id = f.customer_unique_id
                     and o.purchase_date > f.first_date
                     and o.purchase_date <= f.first_date + 180) as came_back
    from cust_first f, last_day
    where f.first_date >= date '2017-01-01' and f.first_date + 180 <= last_day.d
)
select cohort, count(*) as customers, count(*) filter (where came_back) as came_back,
       round(100.0 * count(*) filter (where came_back) / count(*), 2) as pct_came_back
from c group by 1 order by 1;

-- Does a bad first delivery or a bad first review predict not coming back?
create or replace table out_retention_by_first_experience as
with last_day as (select cast(max(purchase_ts) as date) as d from order_facts),
first_order as (
    select f.customer_unique_id, f.first_date, o.order_id
    from cust_first f join cust_orders o on o.customer_unique_id = f.customer_unique_id and o.purchase_ts = f.first_ts
    qualify row_number() over (partition by f.customer_unique_id order by o.order_id) = 1
),
c as (
    select fo.customer_unique_id, x.is_delivered, x.days_late, x.review_score,
           exists (select 1 from cust_orders o
                   where o.customer_unique_id = fo.customer_unique_id
                     and o.purchase_date > fo.first_date
                     and o.purchase_date <= fo.first_date + 180) as came_back
    from first_order fo join order_facts x using (order_id), last_day
    where fo.first_date >= date '2017-01-01' and fo.first_date + 180 <= last_day.d
      and x.is_delivered and x.review_score is not null
)
select case when review_score <= 2 then '1 to 2 stars' when review_score = 3 then '3 stars' else '4 to 5 stars' end as first_review,
       case when days_late > 0 then 'Late' else 'On time or early' end as first_delivery,
       count(*) as customers,
       round(100.0 * count(*) filter (where came_back) / count(*), 2) as pct_came_back
from c group by 1, 2 order by 1, 2;
