# Olist marketplace analysis: a late parcel costs two stars, and most customers never order twice

An analysis of about 99,000 orders from Olist, a Brazilian online marketplace, placed from January 2017 to August 2018. It asks one question: **where does the marketplace earn its money, and what hurts customer satisfaction and repeat buying?**

Dashboards: [Interactive web dashboard](https://rojinta.github.io/olist-ecommerce-analysis/) | [Tableau Public dashboard](https://public.tableau.com/app/profile/rojin.taheri/viz/OlistMarketplaceAnalysis/OlistMarketplaceAnalysis)

## The short answer

- **Orders usually arrive early.** The typical order is promised in 24 days and arrives in 10.2. 78.9% arrive at least a week before the estimated date, and 6.8% (6,531 orders) arrive late.
- **A late order costs about two stars.** Late orders average 2.27 stars against 4.29 for the rest. 53.8% of late orders get a one-star review, against 6.6% of the others. The drop is similar inside every large product category, so it is not just a category effect.
- **Most customers never order again.** Only 1.9% of customers (1,307 of 67,772) placed a second order on a later day within 180 days. The rate is low for every first-order group, so a bad first delivery does not explain why most customers do not come back.
- **A few sellers carry the marketplace.** The top 1% of the 2,945 sellers earn 25.9% of revenue and the top 10% earn 67.0%. Among sellers with at least 30 orders, a higher late share goes with a lower average score (correlation -0.49).
- **Delivery is slowest in the north and northeast.** Median delivery time is 7.2 days in Sao Paulo and 21.1 in Para. Maranhao has the highest late share (17.5%).
- **Revenue is concentrated in a few categories.** The ten biggest of 74 categories bring in 62.5% of revenue. Health and beauty is first (9.3%).

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) on Kaggle, released under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). It covers orders placed from September 2016 to October 2018. The raw files are not in this repository (see `data/README.md` for how to download them). Prices are in Brazilian reais.

## Method

1. **Cleaning** (`sql/01_clean.sql`). Eight raw tables are typed and joined into one analysis row per order. A customer is identified by `customer_unique_id`, because the marketplace gives every order a new `customer_id`. Orders with two or three reviews keep the most recent review. Two product categories missing from the translation file keep their original names.
2. **Window.** Orders placed from 1 January 2017 to 31 August 2018. September to December 2016 and September to October 2018 hold only a few hundred orders each and are left out.
3. **Late.** An order is late if it was delivered on a later calendar day than the estimated delivery date. The estimate is a date with no time of day, while delivery has a date and a time. Comparing exact moments would count 7,822 orders as late instead of 6,531, including orders delivered in the afternoon of the estimated day.
4. **Delivered orders only.** Delivery times, late shares, reviews and revenue use delivered orders. Revenue is the price of items, before shipping. 1.2% of orders were canceled or unavailable.
5. **Coming back** (`sql/05_retention.sql`). A customer came back if they ordered on a later calendar day than their first order, within 180 days. Several orders on one day count as one shopping trip (926 customer-days have more than one order). Only customers with a full 180 days of follow-up are counted.
6. **Sellers** (`sql/06_concentration.sql`). Revenue concentration uses all sellers with a delivered order. Late share against score uses sellers with at least 30 delivered orders. The correlation is the Pearson correlation across those 625 sellers.
7. **Verification.** `validate.py` recomputes the main result tables with pandas straight from the raw files, with no SQL, and compares them with the SQL results. All 71 comparisons match.

## Limits

- **Correlation, not proof.** Late orders go with low scores, but the data cannot show that lateness caused them. Late orders may also involve damaged goods or distant sellers.
- **Only reviewers.** Review scores come from customers who chose to write one. Customers with a bad experience may be more likely to review (99.3% of delivered orders have a review).
- **Return rate covers this marketplace only.** The data cannot see what customers bought elsewhere, and it ends in October 2018.
- **Small groups.** The sellers with more than 15% late orders are few (37), and the highest late-share group has only 5 sellers.
- **Old data.** Orders are from 2016 to 2018, so this describes that period.
- **Shipping.** The shipping fee (freight) is the delivery charge the customer pays on top of the item price. It is not included in revenue.

## Reproduce it

```bash
python3 -m pip install -r requirements.txt
# download the Kaggle files into data/raw/ (see data/README.md)
python3 build.py                   # loads the CSVs into DuckDB, runs sql/*.sql, writes results/out_*.csv
python3 export_dashboard_data.py   # writes the dashboard CSVs to dashboard_data/
python3 validate.py                # independent pandas check
```

## What is in here

| Path | Contents |
|---|---|
| `index.html`, `vendor/` | The dashboard page (open `index.html` through a web server, or publish it with GitHub Pages) and the d3 library it uses |
| `sql/` | Six SQL files, one per question: cleaning, sales, delivery, reviews, retention, concentration |
| `build.py` | Loads the raw files into DuckDB and runs the SQL |
| `export_dashboard_data.py` | Builds the small CSVs behind the dashboard |
| `validate.py` | Independent re-computation in pandas |
| `results/` | Every result table as CSV |
| `dashboard_data/` | The datasets behind the dashboard |

Built with SQL (DuckDB), Python (pandas) and d3. Data: Olist, CC BY-NC-SA 4.0. The licence has a share-alike condition, so check its terms before reusing the result tables.
