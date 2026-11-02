"""Write one CSV with one row per order (January 2017 to August 2018) for the Tableau dashboard.
Run after build.py. Usage: python3 export_tableau_data.py"""
import pathlib, duckdb

root = pathlib.Path(__file__).parent
out = root / "tableau_data"
out.mkdir(exist_ok=True)
con = duckdb.connect(str(root / "olist.duckdb"), read_only=True)

STATES = {"AC": "Acre", "AL": "Alagoas", "AP": "Amapá", "AM": "Amazonas", "BA": "Bahia", "CE": "Ceará", "DF": "Distrito Federal",
          "ES": "Espírito Santo", "GO": "Goiás", "MA": "Maranhão", "MT": "Mato Grosso", "MS": "Mato Grosso do Sul", "MG": "Minas Gerais",
          "PA": "Pará", "PB": "Paraíba", "PR": "Paraná", "PE": "Pernambuco", "PI": "Piauí", "RJ": "Rio de Janeiro",
          "RN": "Rio Grande do Norte", "RS": "Rio Grande do Sul", "RO": "Rondônia", "RR": "Roraima", "SC": "Santa Catarina",
          "SP": "São Paulo", "SE": "Sergipe", "TO": "Tocantins"}
con.execute("create or replace temp table state_names(code varchar, name varchar)")
con.executemany("insert into state_names values (?, ?)", list(STATES.items()))

con.execute("""
copy (
  with main_cat as (
      -- the category of the most expensive item in the order
      select i.order_id, p.category
      from items i join products p using (product_id)
      qualify row_number() over (partition by i.order_id order by i.price desc, i.item_no) = 1
  )
  select f.order_id,
         f.purchase_month                                         as purchase_month,
         cast(f.purchase_ts as date)                              as purchase_date,
         f.state                                                  as state_code,
         s.name                                                   as state_name,
         f.status                                                 as order_status,
         case when f.is_delivered then 'Delivered' else 'Not delivered' end as delivery_status,
         case when f.is_delivered then 1 else 0 end               as delivered_flag,
         case when f.is_delivered then round(f.delivery_days, 2) end as delivery_days,
         case when f.is_delivered then f.days_late end            as days_vs_estimate,
         case when f.is_delivered then (case when f.days_late > 0 then 'Late' else 'On time or early' end) end as delivery_outcome,
         case when f.is_delivered then (case when f.days_late > 0 then 1 else 0 end) end as late_flag,
         case when not f.is_delivered then null
              when f.days_late <= -8 then '1. More than 7 days early' when f.days_late <= -1 then '2. 1 to 7 days early'
              when f.days_late = 0 then '3. On the estimated day' when f.days_late <= 3 then '4. 1 to 3 days late'
              when f.days_late <= 7 then '5. 4 to 7 days late' when f.days_late <= 14 then '6. 8 to 14 days late'
              else '7. More than 14 days late' end                as lateness_group,
         f.review_score                                           as review_score,
         case when f.is_delivered then coalesce(f.items_price, 0) else 0 end as revenue_brl,
         case when f.is_delivered then coalesce(f.freight, 0) else 0 end     as shipping_fee_brl,
         upper(substr(replace(coalesce(m.category, 'unknown'), '_', ' '), 1, 1)) || substr(replace(coalesce(m.category, 'unknown'), '_', ' '), 2) as main_category
  from order_facts f
  left join main_cat m using (order_id)
  left join state_names s on s.code = f.state
  where f.in_window
  order by f.purchase_ts
) to 'tableau_data/olist_orders_for_tableau.csv' (header)
""")
print(con.execute("""select count(*) orders, sum(delivered_flag) delivered, round(sum(revenue_brl)) revenue, round(100*avg(late_flag),1) pct_late,
  round(avg(review_score) filter (where late_flag=0),2) ontime_score, round(avg(review_score) filter (where late_flag=1),2) late_score,
  count(distinct state_name) states, count(distinct main_category) cats
  from read_csv('tableau_data/olist_orders_for_tableau.csv')""").fetchall())
