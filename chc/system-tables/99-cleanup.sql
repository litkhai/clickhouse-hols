-- 99 — Drop the lab database (the system log rows it produced stay until their TTL)
DROP DATABASE IF EXISTS systables_lab SYNC;
