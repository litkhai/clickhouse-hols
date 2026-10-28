#!/bin/bash

echo "================================"
echo "ClickHouse 26.10: LogsQL dialect Test"
echo "================================"
echo ""

# fields _time prints 3,620 timestamps; the lab is in the other lines.
cat 04-logsql.sql | docker exec -i clickhouse-26-10 clickhouse-client --multiline --multiquery \
    | grep -v '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9:]*$'

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
