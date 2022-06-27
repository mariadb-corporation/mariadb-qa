#!/bin/bash
BASEDIR=/test/MD310522-mariadb-10.10.0-linux-x86_64-dbg
HOME=/home/$(whoami)

if [ ! -r ./list_unique_bugs -o ! -r ${BASEDIR}/bin/mysqld -o ! -r ${HOME}/t -o ! -r /test/gendirs.sh -o ! -r ${BASEDIR}/reducer_new_text_string.sh -o "${PWD}" != "${HOME}/fuzzing" ]; then
  echo 'Check setup!'
  exit 1
fi

echo "Computing runtime size..."
BUGS=$(./list_unique_bugs)
COUNT="$(printf "%s\n" "${BUGS}" | wc -l)"

echo "Processing ${COUNT} bugs..."
for ((i=1;i<=${COUNT};i++)); do
#for ((i=1;i<=1;i++)); do  # Testing
  BUG="$(printf "%s\n" "${BUGS}" | head -n${i} | tail -n1)"
  echo '-----------------------------------------------------------------------------------------'
  echo "BUG ${i}/${COUNT}: ${BUG}"
  echo '-----------------------------------------------------------------------------------------'
  TC=$(grep -F "${BUG}" */crashes/*.string | head -n1 | sed 's|\.string:.*||')
  echo "Testcase used: '${TC}'"
  if [ -r "${TC}.report" ]; then
    echo "There already is a report for this testcase ('${TC}.report'), skipping..."
    continue;
  fi
  cp "${TC}" "${BASEDIR}/in.sql"
  cd ${BASEDIR}
  echo "Running reducer for testcase..."
  timeout --signal=9 75m ./reducer_new_text_string.sh "./in.sql" "${BUG}"
  mv in.sql_out in.sql
  echo "Running ~/b for testcase..."
  timeout --signal=9 15m ${HOME}/b
  cd ${HOME}/fuzzing
  echo "Copying report..."
  mv ${BASEDIR}/report.log "${TC}.report"
  echo "${TC} completed..."
done
