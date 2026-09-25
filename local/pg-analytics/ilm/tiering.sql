-- ILM tiering: move one month of a fact table from PG heap (hot.*) to its
-- Iceberg cold table (tpch.*_cold), in ONE Postgres transaction.
--
--   SELECT ilm.tier_month('lineitem', date '1995-03-01');   -- rows moved
--
-- Idempotent by construction, which is what makes it safe against the
-- failure Phase 1 injects: with an external REST catalog, pg_lake commits
-- the Iceberg snapshot to Polaris as part of the PG commit, so a crash in
-- between can leave a month in the lake while the heap copy survives.
--   * hot rows still present  -> clear that month in the lake, then move it
--   * hot rows already gone   -> the month was fully tiered; do nothing
-- A rerun therefore never duplicates and never loses a month.
CREATE SCHEMA IF NOT EXISTS ilm;

CREATE OR REPLACE FUNCTION ilm.tier_month(p_table text, p_month date)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  col text := CASE WHEN p_table LIKE '%lineitem' THEN 'l_shipdate'
                   WHEN p_table LIKE '%orders'   THEN 'o_orderdate' END;
  lo  date := date_trunc('month', p_month)::date;
  hi  date := (date_trunc('month', p_month) + interval '1 month')::date;
  moved bigint;
  pending boolean;
BEGIN
  IF col IS NULL THEN
    RAISE EXCEPTION 'unknown fact table %', p_table;
  END IF;
  IF lo >= current_setting('ilm.hot_cutoff')::date THEN
    RAISE EXCEPTION 'month % is inside the hot window', lo;
  END IF;

  EXECUTE format('SELECT EXISTS (SELECT 1 FROM hot.%I WHERE %I >= $1 AND %I < $2)',
                 p_table, col, col) INTO pending USING lo, hi;
  IF NOT pending THEN
    RETURN 0;
  END IF;

  EXECUTE format('DELETE FROM tpch.%I WHERE %I >= $1 AND %I < $2',
                 p_table || '_cold', col, col) USING lo, hi;
  EXECUTE format('INSERT INTO tpch.%I SELECT * FROM hot.%I WHERE %I >= $1 AND %I < $2',
                 p_table || '_cold', p_table, col, col) USING lo, hi;
  GET DIAGNOSTICS moved = ROW_COUNT;
  EXECUTE format('DELETE FROM hot.%I WHERE %I >= $1 AND %I < $2',
                 p_table, col, col) USING lo, hi;
  RETURN moved;
END $$;

-- months of p_table that still have rows in heap and are old enough to move
CREATE OR REPLACE FUNCTION ilm.pending_months(p_table text)
RETURNS SETOF date
LANGUAGE plpgsql AS $$
DECLARE
  col text := CASE WHEN p_table LIKE '%lineitem' THEN 'l_shipdate'
                   WHEN p_table LIKE '%orders'   THEN 'o_orderdate' END;
BEGIN
  RETURN QUERY EXECUTE format(
    'SELECT DISTINCT date_trunc(''month'', %I)::date AS m FROM hot.%I
      WHERE %I < $1 ORDER BY 1', col, p_table, col)
    USING current_setting('ilm.hot_cutoff')::date;
END $$;
