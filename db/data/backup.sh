docker exec mva_db $(docker ps --filter label=foo=bar | awk '{print $11}') pg_dumpall -c -U app -U postgres > mva_db_`date +%d-%m-%Y"_"%H_%M_%S`.sql
