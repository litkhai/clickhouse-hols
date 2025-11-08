# TPC-DS Query Templates

This directory should contain the TPC-DS query SQL files.

## Getting Query Templates

You can obtain TPC-DS queries from several sources:

### Option 1: Official TPC-DS Specification
Download from: http://www.tpc.org/tpcds/

### Option 2: TPC-DS Kit
The queries are included in the TPC-DS toolkit:
```bash
git clone https://github.com/gregrahn/tpcds-kit.git
cd tpcds-kit/query_templates
```

### Option 3: ClickHouse Examples
ClickHouse provides adapted TPC-DS queries:
- Visit: https://clickhouse.com/docs/en/getting-started/example-datasets/tpcds

## Query File Naming Convention

Query files should be named using the pattern: `query[NN].sql`

Examples:
- query01.sql
- query02.sql
- query03.sql
- ...
- query99.sql

## Adapting Queries for ClickHouse

Some TPC-DS queries may need minor adjustments for ClickHouse:

1. **Date functions**: Convert standard SQL date functions to ClickHouse equivalents
2. **Casting**: Use ClickHouse casting syntax
3. **Window functions**: Ensure compatibility with ClickHouse window function syntax
4. **String functions**: Adapt to ClickHouse string function names

## Example Query Structure

```sql
-- Query 01: Return customers with high return rates

SELECT
    c_customer_id,
    c_first_name,
    c_last_name,
    c_email_address,
    sum(cr_return_amount) as total_returns
FROM
    customer,
    catalog_returns,
    date_dim
WHERE
    cr_returning_customer_sk = c_customer_sk
    AND cr_returned_date_sk = d_date_sk
    AND d_year = 2001
GROUP BY
    c_customer_id,
    c_first_name,
    c_last_name,
    c_email_address
HAVING
    sum(cr_return_amount) > 1000
ORDER BY
    total_returns DESC
LIMIT 100;
```

## Query Parameters

TPC-DS queries use substitution parameters. You can either:
1. Pre-substitute values before saving the .sql files
2. Use the dsqgen tool from tpcds-kit to generate queries with random parameters
3. Create a parameter substitution script

## Testing Individual Queries

Test a query directly:
```bash
clickhouse-client --database tpcds --queries-file queries/query01.sql
```

Or use the benchmark scripts:
```bash
./04-run-queries-sequential.sh --queries query01
```
