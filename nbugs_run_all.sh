#!/bin/bash
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "run_all" bash -c "$0;bash"
  sleep 1
  screen -d -r "run_all"
  return 2> /dev/null; exit 0
fi

O='/test/MD131124-mariadb-11.7.1-linux-x86_64-opt'
D='/test/MD131124-mariadb-11.7.1-linux-x86_64-dbg'
OS='/test/UBASAN_MD131124-mariadb-11.7.1-linux-x86_64-opt'
DS='/test/UBASAN_MD131124-mariadb-11.7.1-linux-x86_64-dbg'
CURDIR="${PWD}"
export O D OS DS CURDIR

ctrl-c(){
  echoit "CTRL+C Was pressed. Attempting to terminate running processes..."
  ps -ef | grep -E 'btest|run_all' | grep -v grep | awk '{print $2}' | xargs -I{timeout -k30 -s9 30s bash -c "./kill" -9 {}
}
trap ctrl-c SIGINT

setup(){
  cd ${O}; ${HOME}/start
  cd ${D}; ${HOME}/start
  cd ${OS}; ${HOME}/start
  cd ${DS}; ${HOME}/start
  cd ${CURDIR}
}

btest(){
  COUNTER=$[ ${COUNTER} + 1 ]
  echo "Testing ${COUNTER}/${COUNT}: ${1}..."
  OPT="$(head -n1 "${1}" 2>/dev/null | grep --binary-files=text -io 'mysqld options required for replay.*' | sed 's|mysqld options required for replay[: ]*||' | tr '\t' ' ' | sed 's| [ ]*| |;s|^[ ]*||;s|[ ]*$||')"
  if [ ! -z "${OPT}" ]; then
    echo "  > Options used: ${OPT}"
  fi
  cd ${CURDIR}
  rm -f ${O}/in.sql ${D}/in.sql ${OS}/in.sql ${DS}/in.sql
  cp "${1}" ${O}/in.sql
  cp "${1}" ${D}/in.sql
  cp "${1}" ${OS}/in.sql
  cp "${1}" ${DS}/in.sql
  cd ${CURDIR}; cd ${O}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.O'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${D}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.D'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${OS}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.OS'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${DS}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.DS'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  OPT="${OPT} --sql_mode= --log-bin"
  cd ${CURDIR}; cd ${O}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.O_s'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${D}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.D_s'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${OS}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.OS_s'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}; cd ${DS}; timeout -k30 -s9 30s bash -c "./anc ${OPT}"; timeout -k90 -s9 90s bash -c "./test_pquery; sleep 1; ${HOME}/tt 2>&1 | grep -v 'Assert.*yielded a non-0 exit code' | tee '${CURDIR}/${1}.DS_s'"; timeout -k30 -s9 30s bash -c "./stop"; timeout -k30 -s9 30s bash -c "./kill"
  cd ${CURDIR}
}
export -f btest

COUNT=$(ls --color=never *.sql | wc -l)
COUNTER=0
#rm *.O *.D *.DS *.DS_s
setup
ls --color=never *.sql | xargs -P1 -I{} bash -c 'btest {}'  # -P1 as each dir is re-used, can be improved to use /dev/shm etca

export -n btest O D OS DS CURDIR
