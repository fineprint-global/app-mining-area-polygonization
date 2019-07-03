docker exec mva_db $(docker ps --filter label=foo=bar | awk '{print $11}') pg_dumpall -c -U app -U postgres > pg_dump.sql
