#./all_no_cl_rr --max_connections=1000  # or anc on regular instances
#sleep 20
#rm -Rf log2
#for ((i=0;i<990;i++)){
#  mkdir -p log2/${i}
#  if [ "${i}" -eq 0 -o "$(echo $[ ${RANDOM} % 2 ])" -eq 0 ]; then
#    ~/mariadb-qa/pquery/pquery2-md --infile=${HOME}/mariadb-qa/spiderpreload.sql --database=test --threads=1 --queries-per-thread=99999999 --logdir=${PWD}/log2/${i} --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=./socket.sock >> log2/pquery_preload_sql.log &
#  else
#    ~/mariadb-qa/pquery/pquery2-md --infile=${HOME}/mdev-28861.sql --database=test --threads=1 --queries-per-thread=99999999 --logdir=${PWD}/log2/${i} --log-all-queries --log-failed-queries --user=root --socket=./socket.sock >> log2/pquery_preload_sql.log &
#  fi
#}
