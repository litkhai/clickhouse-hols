-- 04-audit-report.sql — what a reviewer runs as `auditor` (04-audit-report.sh passes {since}).
-- Sources: the service's audit.decrypt_events, and OpenBao's audit file read in place with file().

-- 1. Decryptions per user and key
SELECT user, key_name, count() AS decrypted, uniqExact(trace_id) AS traces, max(event_time) AS last
FROM audit.decrypt_events
WHERE outcome = 'success' AND event_time >= parseDateTimeBestEffort({since:String})
GROUP BY user, key_name
ORDER BY decrypted DESC;

-- 2. Refusals: who tried, and why the service or OpenBao said no
SELECT outcome, if(user = '', concat(claimed_user, ' (claimed)'), user) AS who, key_name, count() AS n, any(detail) AS example
FROM audit.decrypt_events
WHERE outcome NOT IN ('success', 'attempt') AND event_time >= parseDateTimeBestEffort({since:String})
GROUP BY outcome, who, key_name
ORDER BY n DESC;

-- 3. Reconciliation: decryptions OpenBao performed with no attempt row from the service
--    (someone with the right went to OpenBao directly, or the service lost a row)
SELECT JSONExtractString(json, 'time') AS time,
       JSONExtractString(json, 'auth', 'metadata', 'username') AS user,
       JSONExtractString(json, 'request', 'path') AS path,
       JSONExtract(json, 'request', 'headers', 'x-request-id', 'Array(String)')[1] AS request_id
FROM file('openbao/audit.log', 'JSONAsString')
WHERE JSONExtractString(json, 'type') = 'response'
  AND startsWith(JSONExtractString(json, 'request', 'path'), 'transit/decrypt/')
  AND NOT JSONHas(json, 'response', 'data', 'error')
  AND JSONExtractString(json, 'time') >= {since:String}
  AND request_id NOT IN (SELECT toString(request_id) FROM audit.decrypt_events WHERE outcome = 'attempt')
ORDER BY time;

-- 4. Attempts with no outcome row (decrypted at OpenBao, but the answer was never recorded)
SELECT a.event_time, a.user, a.trace_id, a.key_name
FROM audit.decrypt_events AS a
WHERE a.outcome = 'attempt' AND a.event_time >= parseDateTimeBestEffort({since:String})
  AND a.request_id NOT IN (SELECT request_id FROM audit.decrypt_events WHERE outcome != 'attempt')
ORDER BY a.event_time;
