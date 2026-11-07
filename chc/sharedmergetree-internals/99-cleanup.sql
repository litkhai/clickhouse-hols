-- 99 — Drop the lab database (the system log rows it produced stay until their TTL)
DROP DATABASE IF EXISTS smt_lab SYNC;
