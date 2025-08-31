
INSERT INTO call_center
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/call_center.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO catalog_page
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/catalog_page.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';






INSERT INTO catalog_returns
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/catalog_returns.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO catalog_sales
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/catalog_sales.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO customer_address
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/customer_address.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO customer
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/customer.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO customer_demographics
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/customer_demographics.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO date_dim
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/date_dim.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO dbgen_version
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/dbgen_version.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO household_demographics
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/household_demographics.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO income_band
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/income_band.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO inventory
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/inventory.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO item
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/item.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO promotion
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/promotion.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO reason
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/reason.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO ship_mode
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/ship_mode.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO store
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/store.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO store_returns
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/store_returns.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO store_sales
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/store_sales.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO time_dim
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/time_dim.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO warehouse
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/warehouse.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO web_page
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/web_page.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO web_returns
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/web_returns.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';


INSERT INTO web_sales
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/web_sales.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';

INSERT INTO web_site
SELECT *
FROM s3(
    'https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data/web_site.dat',
    'CSV'
) SETTINGS format_csv_delimiter='|';
