#!/bin/bash
# This script was originally developed in connection with testing https://jira.mariadb.org/browse/MDEV-25440
# It should howerver be easy to update/adapt for any SE SQL generation or variation (and it is quite powerful)

INPUT="${HOME}/mariadb-qa/pquery/main-ms-ps-md.sql"
BRANCH="/test/MDEV-25440-2-bb-10.5-release"
OUT="/tmp/gen_se.sql"
TMP="${OUT}.tmp"

if [ ! -r "${INPUT}" ]; then echo "Input (${INPUT}) not readable by this script!"; exit 1; fi
echo "Approx processing time (depending on hardware): 2-7 minutes..."

swap_out_tmp(){
  rm -f "${TMP}"
  if [ -r "${TMP}" ]; then echo "Assert: ${TMP} exists after delete"; exit 1; fi
  if [ ! -r "${OUT}" ]; then echo "Assert: ${OUT} does not exist before move"; exit 1; fi
  mv "${OUT}" "${TMP}"
  if [ -r "${OUT}" ]; then echo "Assert: ${OUT} exists after move"; exit 1; fi
  if [ ! -r "${TMP}" ]; then echo "Assert: ${TMP} does not exist after move"; exit 1; fi
}

# CREATE TABLE collection and unification, and remove duplicates
echo "Stage #1/3 processing..."
rm -f "${TMP}"
grep --binary-files=text -i 'create table' "${INPUT}" | \
 sed 's|engine[ =]*[^ ;]\+|ENGINE=DUMMY9000|gi;
      s|`||g;
      s|/\*.*\*/||g;
      s|row_format[ =]\+[^ ;]\+||gi;
      s|collate[ =]\+[^ ;]\+||gi;
      s|if not exists||gi;
      s|[\t ]\+| |g;
      s|eval[ ]\+||g
      s|^[ ]*create table [^ (;]\+|CREATE TABLE t1|gi;
      s|t1[ ]*([ ]*|t1 (|g;
     ' | \
 grep --binary-files=text -i '^[ ]*create[ ]*table[ ]*' | \
 sort -u > "${TMP}"

# Vary ROW_FORMAT's and set ENGINE. Data size increases x 5 (no ROW_FORMAT, 1 other SE, 2 ROW_FORMAT options)
echo "Stage #2/3 processing..."
rm -f "${OUT}"
touch "${OUT}"

# Actual SE changes, edit as needed
#sed 's|ENGINE=DUMMY9000|ENGINE=InnoDB|gi' "${TMP}" >> "${OUT}"
sed 's|ENGINE=DUMMY9000|ENGINE=Spider|gi' "${TMP}" >> "${OUT}"
#sed 's|ENGINE=DUMMY9000|ROW_FORMAT=DYNAMIC ENGINE=InnoDB|gi' "${TMP}" >> "${OUT}"
#sed 's|ENGINE=DUMMY9000|ROW_FORMAT=REDUNDANT ENGINE=InnoDB|gi' "${TMP}" >> "${OUT}"

# MDEV-25440 specific
# Add all possible nopad collations. Data size increases x 37 (there are 37 collations)
# Remove duplicates. Data size decreases approximately 2.7 fold (TODO: why?)
#echo "Stage #3A/3A processing (input: $(wc -l "${OUT}" | tr -d '\n' | awk '{print $1}') lines)..."
#swap_out_tmp
#cd "${BRANCH}"
#grep --binary-files=text 'charset_info.*nopad' include/m_ctype.h | \
# sed 's|.*my_charset_||;s|;||' | \
# xargs -I{} sed "s|ENGINE=|COLLATE={} ENGINE=|gi" "${TMP}" | \
# sort -u > "${OUT}"

# Interleave SQL with DROP TABLE statements. Note: do not add 'sort -u' to this command
echo "Stage #3/3 processing..."
swap_out_tmp
sed "s|$|\nDROP TABLE IF EXISTS t1;|" "${TMP}" > "${OUT}" 

# Cleanup
rm ${TMP}
echo "Preliminary done! ${OUT} ($(wc -l ${OUT} | tr -d '\n' | awk '{print $1}') lines)"
echo ''
echo 'Next step: cleanup SQL. Use something like:'
echo ''
echo 'cd /test/MD290122-mariadb-10.8.1-linux-x86_64-dbg'
echo './all'
echo "sql> INSTALL PLUGIN spider SONAME 'ha_spider.so';"
echo 'sql> quit'
echo 'rm -f default.node.tld*'
echo "~/mariadb-qa/pquery/pquery2-md --infile=${OUT} --threads=1 --queries-per-thread=99999999999 --logdir=\${PWD} --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=\${PWD}/socket.sock --database=test"
echo "grep --binary-files=text -vEi '^DROP TABLE|Unknown database|Unknown collation|error in your SQL syntax' default.node.tld_thread-0.sql > final.tmp && wc -l final.tmp"
echo "sed 's|$|\\nDROP TABLE IF EXISTS t1;|' final.tmp > final.sql && rm -f final.tmp"
echo ''
echo 'The resulting SQL is in final.sql'
echo ''
echo 'To monitor progress while queries are being checked:'
echo ''
echo './cl'
echo "sql> SHOW GLOBAL STATUS LIKE '%queries%';"
echo "sql> SYSTEM wc -l ${OUT}"
echo ''
echo 'And compare the two numbers'

