#!/bin/bash
# Start server with --max_connections=10000
# Set variables and ensure ramloc is a ramdisk or tmpfs (i.e. /dev/shm)
 
user="root"
socket="./socket.sock"
db="test"
client="./bin/mariadb"
errorlog="./log/master.err"
ramloc="/dev/shm"
threads=2000   # Number of concurrent threads
queries=100    # Number of t1/t2 INSERTs per thread/per test round
rounds=999999  # Number of max test rounds
 
# Setup
${client} -u ${user} -S ${socket} -D ${db} -e "
DROP TABLE IF EXISTS t1;
DROP TABLE IF EXISTS t2;
CREATE TABLE t1 (c1 INT NOT NULL AUTO_INCREMENT, c2 INT NOT NULL, PRIMARY KEY (c1), UNIQUE KEY u1 (c1,c2)) ENGINE=InnoDB AUTO_INCREMENT=1 ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=4; 
CREATE TABLE t2 (c1 DATETIME NOT NULL, c2 DOUBLE NOT NULL, t1_c1 INT NOT NULL, PRIMARY KEY (t1_c1,c1)) ENGINE=InnoDB ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=4;
"
 
insert_rows(){
  SQL=
  for ((i=0;i<${queries};i++)); do
    SQL="${SQL}INSERT INTO t1 (c2) VALUES (0); INSERT INTO t2 VALUES (CURRENT_TIMESTAMP, 0, (SELECT LAST_INSERT_ID()));"
  done
  ${client} -u ${user} -S ${socket} -D ${db} -e "${SQL}"
  rm -f ${ramloc}/${prefix}_md_proc_${1}  # Thread done
}
 
abort(){ jobs -p | xargs -P100 kill >/dev/null 2>&1; rm -Rf ${ramloc}/${prefix}_md_proc_*; exit 1; }
trap abort SIGINT
 
count=0
prefix="$(echo "${RANDOM}${RANDOM}${RANDOM}" | cut -b1-5)"
rm -f ${ramloc}/${prefix}_md_proc_*
for ((i=0;i<${rounds};i++)); do
  for ((i=0;i<${threads};i++)); do
    if [ ! -r ${ramloc}/${prefix}_md_proc_${i} ]; then  # Thread idle
      touch ${ramloc}/${prefix}_md_proc_${i}  # Thread busy
      insert_rows ${i} &
      count=$[ ${count} + 1 ]
      if [ $[ ${count} % 100 ] -eq 0 ]; then  # Limit disk I/O, check once every new 100 threads
        echo "Count: ${count}" | tee lastcount.log
        TAIL="$(tail -n10 ${errorlog} | tr -d '\n')"
        if [[ "${TAIL}" == *"ERROR"* ]]; then
          echo '*** Error found:'
          grep -i 'ERROR' log/master.err
          abort
        elif [[ "${TAIL}" == *"down complete"* ]]; then
          echo '*** Server shutdown'
          abort
        elif ! ${client}-admin ping -u ${user} -S ${socket} > /dev/null 2>&1; then
          echo '*** Server gone (killed/crashed)'
          abort
        fi
      fi
    fi
  done
done
