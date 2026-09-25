-- One query file set, four object mappings on pg-main. The runner sets
-- search_path to exactly one of these schemas before each query.
--   a_d1  path A, all-lake       a_d2  path A, dimensions from heap
--   c_d1  path C, all-lake       c_d2  path C, dimensions from heap
-- lineitem / orders are always the cold tier; *_all is the ILM view.
DO $$
DECLARE
  s text; lake text; dims text;
  d text;
BEGIN
  FOREACH s IN ARRAY ARRAY['a_d1','a_d2','c_d1','c_d2'] LOOP
    lake := CASE WHEN s LIKE 'a%' THEN 'tpch' ELSE 'ch' END;
    dims := CASE WHEN s LIKE '%d1' THEN lake ELSE 'hot' END;
    EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', s);
    EXECUTE format('CREATE SCHEMA %I', s);
    EXECUTE format('CREATE VIEW %I.lineitem AS SELECT * FROM %I.lineitem_cold', s, lake);
    EXECUTE format('CREATE VIEW %I.orders AS SELECT * FROM %I.orders_cold', s, lake);
    EXECUTE format('CREATE VIEW %I.lineitem_all AS SELECT * FROM hot.lineitem UNION ALL SELECT * FROM %I.lineitem_cold', s, lake);
    EXECUTE format('CREATE VIEW %I.orders_all AS SELECT * FROM hot.orders UNION ALL SELECT * FROM %I.orders_cold', s, lake);
    FOREACH d IN ARRAY ARRAY['customer','part','partsupp','supplier','nation','region'] LOOP
      EXECUTE format('CREATE VIEW %I.%I AS SELECT * FROM %I.%I', s, d, dims, d);
    END LOOP;
  END LOOP;
END $$;
