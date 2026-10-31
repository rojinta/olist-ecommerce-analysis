-- 02_sales.sql : Q1 What does the marketplace sell, and how fast is it growing?
-- Revenue = item price of delivered orders (freight excluded). Currency is Brazilian reais (BRL).

create or replace table out_headline as
select count(*)                                                      as orders_placed,
       count(*) filter (where is_delivered)                          as orders_delivered,
       count(*) filter (where status in ('canceled', 'unavailable')) as orders_canceled_or_unavailable,
       round(sum(items_price) filter (where is_delivered))           as revenue_brl,
       round(sum(freight)     filter (where is_delivered))           as freight_brl,
       count(distinct customer_unique_id)                            as customers,
       round(sum(items_price) filter (where is_delivered) / count(*) filter (where is_delivered), 1) as avg_order_value_brl
from order_facts where in_window;

create or replace table out_monthly as
select purchase_month                                                  as month,
       count(*)                                                        as orders,
       count(*) filter (where is_delivered)                            as delivered,
       round(sum(items_price) filter (where is_delivered))             as revenue_brl,
       round(100.0 * count(*) filter (where status in ('canceled', 'unavailable')) / count(*), 1) as pct_canceled_or_unavailable
from order_facts where in_window
group by 1 order by 1;

create or replace table out_category as
with s as (
    select p.category, count(distinct i.order_id) as orders, count(*) as items, sum(i.price) as revenue
    from items i
    join order_facts f using (order_id)
    join products p using (product_id)
    where f.in_window and f.is_delivered
    group by 1
)
select rank() over (order by revenue desc)                                  as rnk,
       category, orders, items, round(revenue)                              as revenue_brl,
       round(100.0 * revenue / sum(revenue) over (), 1)                     as pct_of_revenue,
       round(100.0 * sum(revenue) over (order by revenue desc) / sum(revenue) over (), 1) as cumulative_pct
from s order by revenue desc;
