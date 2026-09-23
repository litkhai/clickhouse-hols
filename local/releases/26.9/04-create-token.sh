#!/bin/bash

# Unlike the other runners in this directory, this one is not a thin pipe.
#
# Everything in 04-create-token.sql runs in a single session as `default`, and
# the interesting half of this feature is what happens on a *different*
# session: a credential authenticating and being refused. A refusal is a raised
# exception, which would stop a .sql file at that line, so those checks live
# here as separate connections instead.

CH="docker exec -i clickhouse-26-9 clickhouse-client"
PASSWORD='lab-password-not-a-secret'

echo "================================"
echo "ClickHouse 26.9: CREATE TOKEN and scoped credentials Test"
echo "================================"
echo ""

cat 04-create-token.sql | $CH --multiline --multiquery

echo ""
echo "════════ 9. Refusals, each on its own connection ════════"
echo ""

# 04-create-token.sql ends by revoking every method except the password, so
# issue a fresh scoped credential to work against.
$CH -q "ALTER USER app ADD IDENTIFIED WITH sha256_password BY 'scoped-credential-not-a-secret' \
        VALID UNTIL '2026-12-31 00:00:00' GRANTS (SELECT ON demo.events)"

echo "-- 9a. full password reads demo.secrets"
$CH --user app --password "$PASSWORD" -q "SELECT count() FROM demo.secrets" 2>&1 | head -2

echo ""
echo "-- 9b. the scoped credential is refused on the same table"
$CH --user app --password 'scoped-credential-not-a-secret' \
    -q "SELECT count() FROM demo.secrets" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1

echo ""
echo "-- 9c. ...while still reading the table its scope names"
$CH --user app --password 'scoped-credential-not-a-secret' \
    -q "SELECT count() FROM demo.events" 2>&1 | head -2

echo ""
echo "════════ 10. CREATE TOKEN itself, as a SQL-defined user ════════"
echo ""
echo "-- 10a. app mints its own token (default is read-only in users.xml and cannot)"
TOKEN=$($CH --user app --password "$PASSWORD" --format TSV \
        -q "CREATE TOKEN VALID FOR INTERVAL 30 DAY GRANTS (SELECT ON demo.events)" | cut -f1)
echo "   token issued, ${#TOKEN} characters"

echo ""
echo "-- 10b. the token authenticates in the password's place"
$CH --user app --password "$TOKEN" -q "SELECT count() FROM demo.events" 2>&1 | head -2

echo ""
echo "-- 10c. and carries the same scope, so demo.secrets is refused"
$CH --user app --password "$TOKEN" -q "SELECT count() FROM demo.secrets" 2>&1 \
    | grep -o 'Code: [0-9]*\..*' | head -1

echo ""
echo "-- 10d. a token session cannot mint another token"
$CH --user app --password "$TOKEN" \
    -q "CREATE TOKEN VALID FOR INTERVAL 1 DAY GRANTS (SELECT ON demo.events)" 2>&1 \
    | grep -o 'Code: [0-9]*\..*' | head -1

echo ""
echo "-- 10e. an already-expired token is issued happily and then refuses to log in"
EXPIRED=$($CH --user app --password "$PASSWORD" --format TSV \
          -q "CREATE TOKEN VALID UNTIL '2020-01-01 00:00:00' GRANTS (SELECT ON demo.events)" | cut -f1)
$CH --user app --password "$EXPIRED" -q "SELECT 1" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1

echo ""
echo "-- 10f. revoke everything but the password"
$CH -q "ALTER USER app IDENTIFIED WITH sha256_password BY '$PASSWORD'"
$CH --user app --password "$TOKEN" -q "SELECT 1" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
