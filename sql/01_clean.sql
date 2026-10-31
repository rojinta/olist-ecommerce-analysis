-- 01_clean.sql : typed tables and one analysis row per order
-- Source: Olist Brazilian E-Commerce Public Dataset (Kaggle, CC BY-NC-SA 4.0). Orders placed Sep 2016 to Oct 2018.
-- The raw_* tables are the CSV files loaded as text by build.py.

create or replace table orders as
select order_id, customer_id, order_status as status,
       try_cast(order_purchase_timestamp       as timestamp) as purchase_ts,
       try_cast(order_delivered_carrier_date   as timestamp) as carrier_ts,
       try_cast(order_delivered_customer_date  as timestamp) as delivered_ts,
       try_cast(order_estimated_delivery_date  as timestamp) as estimated_ts
from orders_raw;

-- customer_id changes with every order; customer_unique_id identifies the person
create or replace table customers as
select customer_id, customer_unique_id, customer_state as state from customers_raw;

create or replace table items as
select order_id, cast(order_item_id as int) as item_no, product_id, seller_id,
       cast(price as double) as price, cast(freight_value as double) as freight
from items_raw;

-- Some orders have 2 or 3 reviews. Keep the most recent one per order.
create or replace table reviews as
select order_id, cast(review_score as int) as score
from reviews_raw
qualify row_number() over (partition by order_id
                           order by review_answer_timestamp desc, review_creation_date desc, review_id desc) = 1;

-- English category names; two categories are missing from the translation file and keep their original name
create or replace table products as
select p.product_id,
       coalesce(t.product_category_name_english, p.product_category_name, 'unknown') as category
from products_raw p left join translation_raw t using (product_category_name);

create or replace table sellers as
select seller_id, seller_state as state from sellers_raw;

create or replace table order_facts as
with it as (
    select order_id, count(*) as n_items, sum(price) as items_price, sum(freight) as freight,
           count(distinct seller_id) as n_sellers
    from items group by 1
)
select o.order_id, c.customer_unique_id, c.state, o.status,
       o.purchase_ts,
       cast(date_trunc('month', o.purchase_ts) as date)                          as purchase_month,
       (o.status = 'delivered' and o.delivered_ts is not null)                   as is_delivered,
       cast(o.delivered_ts as date)                                              as delivered_date,
       cast(o.estimated_ts as date)                                              as estimated_date,
       date_diff('second', o.purchase_ts, o.delivered_ts) / 86400.0              as delivery_days,
       -- the estimate is a date with no time, so lateness is compared by calendar day
       date_diff('day', cast(o.estimated_ts as date), cast(o.delivered_ts as date)) as days_late,
       r.score                                                                   as review_score,
       it.n_items, it.items_price, it.freight, it.n_sellers,
       -- Jan 2017 to Aug 2018: months with steady volume (Sep to Dec 2016 and Sep to Oct 2018 have a few hundred orders at most)
       (o.purchase_ts >= timestamp '2017-01-01' and o.purchase_ts < timestamp '2018-09-01') as in_window
from orders o
join customers c using (customer_id)
left join it using (order_id)
left join reviews r using (order_id);
