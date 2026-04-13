#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
#echo "MyPID: $$"    # Debug

# ====== User Variables
OUTPUT_FILE=out      # Output file. Do NOT add .sql suffix, it will be automaticaly added
MYSQL_VERSION=57     # Valid options: 56, 57
THREADS=25           # Number of SQL generation threads (default:4). Do not set the default >4 as pquery-run.sh also uses this script (avoids server overload with multiple runs)
SHEDULING_ENABLED=0  # On/Off (1/0). Enables/disables using mysql EVENTs .When using this, please note that testcases need to be reduced using PQUERY_MULTI=1 in reducer.sh (as they are effectively multi-threaded due to sheduler threads), and that issue reproducibility may be significantly lower (sheduling may not match original OS slicing, other running queries etc.). Still, using PQUERY_MULTI=1 a good number of issues are likely reproducibile and thus reducable given reducer.sh's random replay functionality.

# ====== Notes
# * This version uses REPLY variables from functions instead of backtick subshells, for example table() sets REPLY and the caller uses $REPLY
# * To debug the syntax of generated SQL, use a set of commands like these:
#   $ ./bin/mysql -A -uroot -S${PWD}/socket.sock --force --binary-mode test < ~/percona-qa/generator/out.sql > ${PWD}/mysql.out 2>&1; grep "You have an error in your SQL syntax" mysql.out
#   There may be other errors then the ones shown here (see full mysql.out output), but this will highlight the main SQL syntax errors
#   The syntax failure rate should be well below 1 in 50 statements, and most of those should be due to semi-unfixable logic issues
#   Add things like; HEX(), UNCOMPRESSED_LENGTH() etc.

# ====== Internal variables; do not modify
START=$(date +%s)
RANDOM=$(( 10#$(date +%s%N | cut -b13-19) ))  # Random entropy pool init (10# forces base-10)
MYSQL_VERSION="${MYSQL_VERSION//.}"
SUBWHEREACTIVE=0

if [ "" == "$1" -o "$2" != "" ]; then
  echo "Please specify the number of queries to generate as the first (and only) option to this script"
  exit 1
else
  QUERIES=$1
fi

if [ $QUERIES -lt $THREADS ]; then
  THREADS=$QUERIES
fi

# Check if pwgen is installed, and pre-generate a pool of random strings for speed
PWGEN=0
pwgen -ycns 1 1 >/dev/null 2>&1
if [ $? -eq 1 -o $? -eq 127 ]; then
  echo "NOTE: pwgen is not installed. Installing it may create additional complexity in some random data."
  echo "Install it with: sudo apt-get install pwgen  # or use yum instead of apt-get on yum packaging manager based systems"
else
  PWGEN=1
  # Pre-generate random strings (avoids forking pwgen per data() call - major speedup)
  _pwgen_tmpfile="/tmp/generator_pwgen_$$"
  pwgen -ycnsr "|\'\\\"\\\`" 1027 500 > "$_pwgen_tmpfile" 2>/dev/null
  mapfile -t _pwgen_pool < "$_pwgen_tmpfile"
  rm -f "$_pwgen_tmpfile"
  _PWGEN_POOL_SIZE=${#_pwgen_pool[*]}
  # If pool generation failed, _PWGEN_POOL_SIZE=0 and data() will fall back to per-call pwgen
fi

# ====== Check all needed data files are present
if [ ! -r tables.txt ]; then echo "Assert: tables.txt not found!"; exit 1; fi
if [ ! -r views.txt ]; then echo "Assert: views.txt not found!"; exit 1; fi
if [ ! -r pk.txt ]; then echo "Assert: pk.txt not found!"; exit 1; fi
if [ ! -r types.txt ]; then echo "Assert: types.txt not found!"; exit 1; fi
if [ ! -r data.txt ]; then echo "Assert: data.txt not found!"; exit 1; fi
if [ ! -r blns/blns2.txt ]; then echo "Assert: blns/blns2.txt not found!"; exit 1; fi
if [ ! -r engines.txt ]; then echo "Assert: engines.txt not found!"; exit 1; fi
if [ ! -r a-z.txt ]; then echo "Assert: a-z.txt not found!"; exit 1; fi
if [ ! -r 0-6.txt ]; then echo "Assert: 0-6.txt not found!"; exit 1; fi
if [ ! -r 0-9.txt ]; then echo "Assert: 0-9.txt not found!"; exit 1; fi
if [ ! -r 1-3.txt ]; then echo "Assert: 1-3.txt not found!"; exit 1; fi
if [ ! -r 1-10.txt ]; then echo "Assert: 1-10.txt not found!"; exit 1; fi
if [ ! -r 1-100.txt ]; then echo "Assert: 1-100.txt not found!"; exit 1; fi
if [ ! -r 1-1000.txt ]; then echo "Assert: 1-1000.txt not found!"; exit 1; fi
if [ ! -r n1000-1000.txt ]; then echo "Assert: n1000-1000.txt not found!"; exit 1; fi
if [ ! -r flush.txt ]; then echo "Assert: flush.txt not found!"; exit 1; fi
if [ ! -r lock.txt ]; then echo "Assert: lock.txt not found!"; exit 1; fi
if [ ! -r reset.txt ]; then echo "Assert: reset.txt not found!"; exit 1; fi
if [ ! -r charsetcol_$MYSQL_VERSION.txt ]; then echo "Assert: charsetcol_$MYSQL_VERSION.txt not found! Please run getallsetoptions.sh after setting VERSION=$MYSQL_VERSION inside the same, and copy the resulting files here"; exit 1; fi
if [ ! -r session_$MYSQL_VERSION.txt ]; then echo "Assert: session_$MYSQL_VERSION.txt not found! Please run getallsetoptions.sh after setting VERSION=$MYSQL_VERSION inside the same, and copy the resulting files here"; exit 1; fi
if [ ! -r global_$MYSQL_VERSION.txt ]; then echo "Assert: global_$MYSQL_VERSION.txt not found! Please run getallsetoptions.sh after setting VERSION=$MYSQL_VERSION inside the same, and copy the resulting files here"; exit 1; fi
if [ ! -r pstables_$MYSQL_VERSION.txt ]; then echo "Assert: pstables_$MYSQL_VERSION.txt not found!"; exit 1; fi
if [ ! -r setvalues.txt ]; then echo "Assert: setvalues.txt not found!"; exit 1; fi
if [ ! -r sqlmode.txt ]; then echo "Assert: sqlmode.txt not found!"; exit 1; fi
if [ ! -r optimizersw.txt ]; then echo "Assert: optimizersw.txt not found!"; exit 1; fi
if [ ! -r inmetrics.txt ]; then echo "Assert: inmetrics.txt not found!"; exit 1; fi
if [ ! -r event.txt ]; then echo "Assert: event.txt not found!"; exit 1; fi
if [ ! -r timefunc.txt ]; then echo "Assert: timefunc.txt not found!"; exit 1; fi
if [ ! -r timezone.txt ]; then echo "Assert: timezone.txt not found!"; exit 1; fi
if [ ! -r timeunit.txt ]; then echo "Assert: timeunit.txt not found!"; exit 1; fi
if [ ! -r func.txt ]; then echo "Assert: func.txt not found!"; exit 1; fi
if [ ! -r proc.txt ]; then echo "Assert: proc.txt not found!"; exit 1; fi
if [ ! -r trigger.txt ]; then echo "Assert: trigger.txt not found!"; exit 1; fi
if [ ! -r users.txt ]; then echo "Assert: users.txt not found!"; exit 1; fi
if [ ! -r profiletypes.txt ]; then echo "Assert: profiletypes.txt not found!"; exit 1; fi
if [ ! -r intervals.txt ]; then echo "Assert: intervals.txt not found!"; exit 1; fi
if [ ! -r lctimenames.txt ]; then echo "Assert: lctimenames.txt not found!"; exit 1; fi
if [ ! -r character.txt ]; then echo "Assert: character.txt not found!"; exit 1; fi
if [ ! -r numsimple.txt ]; then echo "Assert: numsimple.txt not found!"; exit 1; fi
if [ ! -r numeric.txt ]; then echo "Assert: numeric.txt not found!"; exit 1; fi
if [ ! -r aggregate.txt ]; then echo "Assert: aggregate.txt not found!"; exit 1; fi
if [ ! -r month.txt ]; then echo "Assert: month.txt not found!"; exit 1; fi
if [ ! -r day.txt ]; then echo "Assert: day.txt not found!"; exit 1; fi
if [ ! -r hour.txt ]; then echo "Assert: hour.txt not found!"; exit 1; fi
if [ ! -r minsec.txt ]; then echo "Assert: minsec.txt not found!"; exit 1; fi

# ====== Read data files into arrays                                            # ====== Usable functions to read from those arrays
mapfile -t tables    < tables.txt       ; TABLES=${#tables[*]}                  ; table()      { REPLY="${tables[$((RANDOM % TABLES))]}"; }
mapfile -t views     < views.txt        ; VIEWS=${#views[*]}                    ; view()       { REPLY="${views[$((RANDOM % VIEWS))]}"; }
mapfile -t pk        < pk.txt           ; PK=${#pk[*]}                          ; pk()         { REPLY="${pk[$((RANDOM % PK))]}"; }
mapfile -t types     < types.txt        ; TYPES=${#types[*]}                    ; ctype()      { REPLY="${types[$((RANDOM % TYPES))]}"; }
mapfile -t datafile  < data.txt                                                                                                                 # Load data.txt
mapfile -t datafile2 < blns/blns2.txt   ; datafile+=("${datafile2[@]}")         # Append blns2.txt
unset datafile2                         ; DATAFILE=${#datafile[*]}              ; datafile()   { REPLY="${datafile[$((RANDOM % DATAFILE))]}"; }
mapfile -t engines   < engines.txt      ; ENGINES=${#engines[*]}                ; engine()     { REPLY="${engines[$((RANDOM % ENGINES))]}"; }
mapfile -t az        < a-z.txt          ; AZ=${#az[*]}                          ; az()         { REPLY="${az[$((RANDOM % AZ))]}"; }
mapfile -t n9        < 0-9.txt          ; N9=${#n9[*]}                          ; n9()         { REPLY="${n9[$((RANDOM % N9))]}"; }
mapfile -t n3        < 1-3.txt          ; N3=${#n3[*]}                          ; n3()         { REPLY="${n3[$((RANDOM % N3))]}"; }
mapfile -t n6        < 0-6.txt          ; N6=${#n6[*]}                          ; n6()         { REPLY="${n6[$((RANDOM % N6))]}"; }
mapfile -t n10       < 1-10.txt         ; N10=${#n10[*]}                        ; n10()        { REPLY="${n10[$((RANDOM % N10))]}"; }
mapfile -t n100      < 1-100.txt        ; N100=${#n100[*]}                      ; n100()       { REPLY="${n100[$((RANDOM % N100))]}"; }
mapfile -t n1000     < 1-1000.txt       ; N1000=${#n1000[*]}                    ; n1000()      { REPLY="${n1000[$((RANDOM % N1000))]}"; }
mapfile -t nn1000    < n1000-1000.txt   ; NN1000=${#nn1000[*]}                  ; nn1000()     { REPLY="${nn1000[$((RANDOM % NN1000))]}"; }
mapfile -t flush     < flush.txt        ; FLUSH=${#flush[*]}                    ; flush()      { REPLY="${flush[$((RANDOM % FLUSH))]}"; }
mapfile -t lock      < lock.txt         ; LOCK=${#lock[*]}                      ; lock()       { REPLY="${lock[$((RANDOM % LOCK))]}"; }
mapfile -t reset     < reset.txt        ; RESET=${#reset[*]}                    ; reset()      { REPLY="${reset[$((RANDOM % RESET))]}"; }
mapfile -t charcol   < charsetcol_$MYSQL_VERSION.txt; CHARCOL=${#charcol[*]}    ; charcol()    { REPLY="${charcol[$((RANDOM % CHARCOL))]}"; }
mapfile -t setvars   < session_$MYSQL_VERSION.txt   ; SETVARS=${#setvars[*]}    ; setvars()    { REPLY="${setvars[$((RANDOM % SETVARS))]}"; }   # S(ession)
mapfile -t setvarg   < global_$MYSQL_VERSION.txt    ; SETVARG=${#setvarg[*]}    ; setvarg()    { REPLY="${setvarg[$((RANDOM % SETVARG))]}"; }   # G(lobal)
mapfile -t pstables  < pstables_$MYSQL_VERSION.txt  ; PSTABLES=${#pstables[*]}  ; pstable()    { REPLY="${pstables[$((RANDOM % PSTABLES))]}"; }
mapfile -t setvals   < setvalues.txt    ; SETVALUES=${#setvals[*]}              ; setval()     { REPLY="${setvals[$((RANDOM % SETVALUES))]}"; }
mapfile -t sqlmode   < sqlmode.txt      ; SQLMODE=${#sqlmode[*]}                ; sqlmode()    { REPLY="${sqlmode[$((RANDOM % SQLMODE))]}"; }
mapfile -t optsw     < optimizersw.txt  ; OPTSW=${#optsw[*]}                    ; optsw()      { REPLY="${optsw[$((RANDOM % OPTSW))]}"; }
mapfile -t inmetrics < inmetrics.txt    ; INMETRICS=${#inmetrics[*]}            ; inmetrics()  { REPLY="${inmetrics[$((RANDOM % INMETRICS))]}"; }
mapfile -t event     < event.txt        ; EVENT=${#event[*]}                    ; event()      { REPLY="${event[$((RANDOM % EVENT))]}"; }
mapfile -t timefunc  < timefunc.txt     ; TIMEFUNC=${#timefunc[*]}              ; timefuncpr() { REPLY="${timefunc[$((RANDOM % TIMEFUNC))]}"; }  # pr: prepare
mapfile -t timezone  < timezone.txt     ; TIMEZONE=${#timezone[*]}              ; timezone()   { REPLY="${timezone[$((RANDOM % TIMEZONE))]}"; }
mapfile -t timeunit  < timeunit.txt     ; TIMEUNIT=${#timeunit[*]}              ; timeunit()   { REPLY="${timeunit[$((RANDOM % TIMEUNIT))]}"; }
mapfile -t func      < func.txt         ; FUNC=${#func[*]}                      ; func()       { REPLY="${func[$((RANDOM % FUNC))]}"; }
mapfile -t proc      < proc.txt         ; PROC=${#proc[*]}                      ; proc()       { REPLY="${proc[$((RANDOM % PROC))]}"; }
mapfile -t trigger   < trigger.txt      ; TRIGGER=${#trigger[*]}                ; trigger()    { REPLY="${trigger[$((RANDOM % TRIGGER))]}"; }
mapfile -t users     < users.txt        ; USERS=${#users[*]}                    ; user()       { REPLY="${users[$((RANDOM % USERS))]}"; }
mapfile -t proftypes < profiletypes.txt ; PROFTYPES=${#proftypes[*]}            ; proftype()   { REPLY="${proftypes[$((RANDOM % PROFTYPES))]}"; }
mapfile -t intervals < intervals.txt    ; INTERVALS=${#intervals[*]}            ; intervalpr() { REPLY="${intervals[$((RANDOM % INTERVALS))]}"; }  # pr: prepare
mapfile -t lctimenms < lctimenames.txt  ; LCTIMENMS=${#lctimenms[*]}            ; lctimename() { REPLY="${lctimenms[$((RANDOM % LCTIMENMS))]}"; }
mapfile -t character < character.txt    ; CHARACTER=${#character[*]}            ; character()  { REPLY="${character[$((RANDOM % CHARACTER))]}"; }
mapfile -t numsimple < numsimple.txt    ; NUMSIMPLE=${#numsimple[*]}            ; numsimple()  { REPLY="${numsimple[$((RANDOM % NUMSIMPLE))]}"; }
mapfile -t numeric   < numeric.txt      ; NUMERIC=${#numeric[*]}                ; numeric()    { REPLY="${numeric[$((RANDOM % NUMERIC))]}"; }
mapfile -t aggregate < aggregate.txt    ; AGGREGATE=${#aggregate[*]}            ; aggregate()  { REPLY="${aggregate[$((RANDOM % AGGREGATE))]}"; }
mapfile -t month     < month.txt        ; MONTH=${#month[*]}                    ; month()      { REPLY="${month[$((RANDOM % MONTH))]}"; }
mapfile -t day       < day.txt          ; DAY=${#day[*]}                        ; day()        { REPLY="${day[$((RANDOM % DAY))]}"; }
mapfile -t hour      < hour.txt         ; HOUR=${#hour[*]}                      ; hour()       { REPLY="${hour[$((RANDOM % HOUR))]}"; }
mapfile -t minsec    < minsec.txt       ; MINSEC=${#minsec[*]}                  ; minsec()     { REPLY="${minsec[$((RANDOM % MINSEC))]}"; }

if [ ${TABLES} -lt 2 ]; then echo "Assert: number of table names is less then 2. A minimum of two tables is required for proper operation. Please ensure tables.txt has at least two table names"; exit 1; fi

# All functions are declared first, then called at the end of the script. This allows mutual recursion (e.g. data->timefunc->data). Ref handy_gnu.txt
# ========================================= Single, fixed
alias2()     { n2; REPLY="a${REPLY}"; }
alias3()     { n3; REPLY="a${REPLY}"; }
asalias2()   { n2; REPLY="AS a${REPLY}"; }
asalias3()   { n3; REPLY="AS a${REPLY}"; }
numericop()  { numeric; local _v=$REPLY; danrorfull; local _d3=$REPLY; danrorfull; local _d2=$REPLY; danrorfull; local _d1=$REPLY; _v=${_v/DUMMY3/$_d3}; _v=${_v/DUMMY2/$_d2}; _v=${_v/DUMMY/$_d1}; REPLY="$_v"; }  # NUMERIC FUNCTION with data (includes numbers) or -1000 to 1000 as options, for example ABS(nr)
joinlron()   { leftright; local _v1=$REPLY; outer; REPLY="${_v1} ${REPLY} JOIN"; }
joinlronla() { natural; local _v1=$REPLY; leftright; local _v2=$REPLY; outer; REPLY="${_v1} ${_v2} ${REPLY} JOIN"; }
interval()   { intervalpr; local _v=$REPLY; neg; local _n=$REPLY; dataornum2; _v=${_v/DUMMY/${_n}${REPLY}}; neg; _n=$REPLY; dataornum2; _v=${_v/DUMMY/${_n}${REPLY}}; neg; _n=$REPLY; dataornum2; _v=${_v/DUMMY/${_n}${REPLY}}; neg; _n=$REPLY; dataornum2; _v=${_v/DUMMY/${_n}${REPLY}}; neg; _n=$REPLY; dataornum2; _v=${_v/DUMMY/${_n}${REPLY}}; REPLY="$_v"; }
intervaln()  { interval; REPLY="INTERVAL ${REPLY}"; }
dategenpr()  { n9; local _v1=$REPLY; n9; local _v2=$REPLY; n9; local _v3=$REPLY; n9; local _v4=$REPLY; month; local _v5=$REPLY; day; local _v6=$REPLY; hour; local _v7=$REPLY; minsec; local _v8=$REPLY; minsec; REPLY="${_v1}${_v2}${_v3}${_v4}-${_v5}-${_v6} ${_v7}:${_v8}:${REPLY}"; }
timefunc()   { timefuncpr; local _v=$REPLY; dategen; _v=${_v/DUMMY_DATE/$REPLY}; dategen; _v=${_v//DUMMY_DATE/$REPLY}; dataornum2; _v=${_v/DUMMY_NR/$REPLY}; dataornum2; _v=${_v/DUMMY_NR/$REPLY}; dataornum2; _v=${_v//DUMMY_NR/$REPLY}; intervaln; _v=${_v/DUMMY_INTERVAL/$REPLY}; timezone; _v=${_v/DUMMY_TIMEZONE/$REPLY}; timezone; _v=${_v//DUMMY_TIMEZONE/$REPLY}; n6; _v=${_v//DUMMY_N6/$REPLY}; data; _v=${_v//DUMMY_DATA/$REPLY}; timeunit; _v=${_v//DUMMY_UNIT/$REPLY}; REPLY="$_v"; }
timefunccol(){ timefuncpr; local _v=$REPLY; n3; _v=${_v/DUMMY_DATE/c${REPLY}}; n3; _v=${_v//DUMMY_DATE/c${REPLY}}; dataornum2; _v=${_v/DUMMY_NR/$REPLY}; dataornum2; _v=${_v/DUMMY_NR/$REPLY}; dataornum2; _v=${_v//DUMMY_NR/$REPLY}; intervaln; _v=${_v/DUMMY_INTERVAL/$REPLY}; timezone; _v=${_v/DUMMY_TIMEZONE/$REPLY}; timezone; _v=${_v//DUMMY_TIMEZONE/$REPLY}; n6; _v=${_v//DUMMY_N6/$REPLY}; data; _v=${_v//DUMMY_DATA/$REPLY}; timeunit; _v=${_v//DUMMY_UNIT/$REPLY}; REPLY="$_v"; }
partnum()    { n1000; REPLY="PARTITIONS ${REPLY}"; }
partnumsub() { n1000; REPLY="SUBPARTITIONS ${REPLY}"; }
partdef1()   { INC1=0; partdef1b; REPLY="(${REPLY})"; }
partdef2()   { INC1=0; INC2=0; partdef2b; REPLY="(${REPLY})"; }
partdef3()   { INC1=0; partdef3b; REPLY="(${REPLY})"; }
partdef4()   { INC1=0; INC2=0; partdef4b; REPLY="(${REPLY})"; }
partdef1b()  { INC1=$(( INC1 + (RANDOM % 100 + 1) )); partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; local _v4=$REPLY; partdefar1; REPLY="PARTITION p${INC1} VALUES LESS THAN (${INC1}) ${_v1} ${_v2} ${_v3} ${_v4} ${REPLY}"; }
partdef2b()  { INC1=$(( INC1 + (RANDOM % 100 + 1) )); INC2=$(( INC2 + (RANDOM % 100 + 1) )); partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; local _v4=$REPLY; partdefar2; REPLY="PARTITION p${INC1} VALUES LESS THAN (${INC1},${INC2}) ${_v1} ${_v2} ${_v3} ${_v4} ${REPLY}"; }
partdef3b()  { INC1=$(( INC1 + 5 + (RANDOM % 10 + 1) )); partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; local _v4=$REPLY; partdefar3; REPLY="PARTITION p${INC1} VALUES IN (${INC1},$(( INC1 + 1 )),$(( INC1 + 2 )),$(( INC1 + 3 )),$(( INC1 + 4 )),$(( INC1 + 5 ))) ${_v1} ${_v2} ${_v3} ${_v4} ${REPLY}"; }
partdef4b()  { INC1=$(( INC1 + 5 + (RANDOM % 10 + 1) )); INC2=$(( INC2 + 5 + (RANDOM % 10 + 1) )); partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; local _v4=$REPLY; partdefar4; REPLY="PARTITION p${INC1} VALUES IN ((${INC1},${INC2}),($(( INC1 + 1 )),$(( INC2 + 1 ))),($(( INC1 + 2 )),$(( INC2 + 2 ))),($(( INC1 + 3 )),$(( INC2 + 3 ))),($(( INC1 + 4 )),$(( INC2 + 4 ))),($(( INC1 + 5 )),$(( INC2 + 5 )))) ${_v1} ${_v2} ${_v3} ${_v4} ${REPLY}"; }
parthash()   { linear; local _v1=$REPLY; collist1; local _v2=$REPLY; partnum; REPLY="${_v1} HASH(${_v2}) ${REPLY}"; }
partkey()    { linear; local _v1=$REPLY; algorithm; local _v2=$REPLY; collist1; local _v3=$REPLY; partnum; REPLY="${_v1} KEY ${_v2} (${_v3}) ${REPLY}"; }
# ========================================= Single, random
neg()        { if (( RANDOM % 20 + 1 <= 1  )); then REPLY="-"; else REPLY=""; fi }                            #  5% - (negative number)
storage()    { if (( RANDOM % 20 + 1 <= 3  )); then REPLY="STORAGE"; else REPLY=""; fi }                      # 15% STORAGE
temp()       { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="TEMPORARY "; else REPLY=""; fi }                   # 20% TEMPORARY
ignore()     { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="IGNORE"; else REPLY=""; fi }                       # 20% IGNORE
linear()     { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="LINEAR"; else REPLY=""; fi }                       # 50% LINEAR
lowprio()    { if (( RANDOM % 20 + 1 <= 5  )); then REPLY="LOW_PRIORITY"; else REPLY=""; fi }                 # 25% LOW_PRIORITY
quick()      { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="QUICK"; else REPLY=""; fi }                        # 20% QUICK
limit()      { if (( RANDOM % 20 + 1 <= 10 )); then n9; REPLY="LIMIT $REPLY"; else REPLY=""; fi }             # 50% LIMIT 0-9
limoffset()  { if (( RANDOM % 20 + 1 <= 2  )); then n3; REPLY="$REPLY,"; else REPLY=""; fi }                  # 10% 0-3 offset (for LIMITs)
ofslimit()   { if (( RANDOM % 20 + 1 <= 10 )); then limoffset; local _v1=$REPLY; n9; REPLY="LIMIT ${_v1}$REPLY"; else REPLY=""; fi }  # 50% LIMIT 0-9, with potential offset
natural()    { if (( RANDOM % 20 + 1 <= 2  )); then REPLY="NATURAL"; else REPLY=""; fi }                      # 10% NATURAL (for JOINs)
outer()      { if (( RANDOM % 20 + 1 <= 8  )); then REPLY="OUTER"; else REPLY=""; fi }                        # 40% OUTER (for JOINs)
partition()  { if (( RANDOM % 20 + 1 <= 4  )); then n3; REPLY="PARTITION p$REPLY"; else REPLY=""; fi }        # 20% PARTITION p1-3
partitionby(){ if (( RANDOM % 20 + 1 <= 5  )); then partdecl; REPLY="PARTITION BY $REPLY"; else REPLY=""; fi }  # 25% PARTITION BY
partse()     { if (( RANDOM % 20 + 1 <= 3  )); then storage; local _v1=$REPLY; equals; local _v2=$REPLY; engine; REPLY="${_v1} ENGINE${_v2}$REPLY"; else REPLY=""; fi }  # 15% ENGINE (for partitioning)
partcomment(){ if (( RANDOM % 20 + 1 <= 2  )); then equals; local _v1=$REPLY; data; REPLY="COMMENT${_v1}$REPLY"; else REPLY=""; fi }  # 10% COMMENT (for partitioning)
partmax()    { if (( RANDOM % 20 + 1 <= 2  )); then equals; local _v1=$REPLY; n1000; REPLY="MAX_ROWS${_v1}$REPLY"; else REPLY=""; fi }  # 10% MAX_ROWS (for partitioning)
partmin()    { if (( RANDOM % 20 + 1 <= 2  )); then equals; local _v1=$REPLY; n1000; REPLY="MIN_ROWS${_v1}$REPLY"; else REPLY=""; fi }  # 10% MIN_ROWS (for partitioning)
pc()         { if (( RANDOM % 20 + 1 <= 2  )); then REPLY="AS(c1) PERSISTENT"; else REPLY=""; fi }            # 10% PERSISTENT column
vc()         { if (( RANDOM % 20 + 1 <= 2  )); then REPLY="AS(c1) VIRTUAL"; else REPLY=""; fi }               # 10% VIRTUAL column
sv()         { if (( RANDOM % 20 + 1 <= 2  )); then REPLY="WITH SYSTEM VERSIONING"; else REPLY=""; fi }       # 10% WITH SYSTEM VERSIONING table
full()       { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="FULL"; else REPLY=""; fi }                         # 20% FULL
not()        { if (( RANDOM % 20 + 1 <= 5  )); then REPLY="NOT"; else REPLY=""; fi }                          # 25% NOT
no()         { if (( RANDOM % 20 + 1 <= 8  )); then REPLY="NO"; else REPLY=""; fi }                           # 40% NO (for transactions)
fromdb()     { if (( RANDOM % 20 + 1 <= 2  )); then REPLY="FROM test"; else REPLY=""; fi }                    # 10% FROM test
offset()     { if (( RANDOM % 20 + 1 <= 4  )); then n9; REPLY="OFFSET $REPLY"; else REPLY=""; fi }            # 20% OFFSET 0-9
forquery()   { if (( RANDOM % 20 + 1 <= 4  )); then n9; REPLY="FORQUERY $REPLY"; else REPLY=""; fi }          # 20% QUERY 0-9
onephase()   { if (( RANDOM % 20 + 1 <= 16 )); then REPLY="ONE PHASE"; else REPLY=""; fi }                    # 80% ONE PHASE
convertxid() { if (( RANDOM % 20 + 1 <= 3  )); then REPLY="CONVERT XID"; else REPLY=""; fi }                  # 15% CONVERT XID
ifnotexist() { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="IF NOT EXISTS"; else REPLY=""; fi }                # 50% IF NOT EXISTS
ifexist()    { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="IF EXISTS"; else REPLY=""; fi }                    # 50% IF EXISTS
completion() { if (( RANDOM % 20 + 1 <= 5  )); then not; REPLY="ON COMPLETION $REPLY PRESERVE"; else REPLY=""; fi }  # 25% ON COMPLETION [NOT] PRESERVE
comment()    { if (( RANDOM % 20 + 1 <= 5  )); then data; REPLY="COMMENT $REPLY'"; else REPLY=""; fi }        # 25% COMMENT
intervaladd(){ if (( RANDOM % 20 + 1 <= 4  )); then interval; REPLY="+ INTERVAL $REPLY"; else REPLY=""; fi }  # 20% + 0-9 INTERVAL
work()       { if (( RANDOM % 20 + 1 <= 5  )); then REPLY="WORK"; else REPLY=""; fi }                         # 25% WORK
savepoint()  { if (( RANDOM % 20 + 1 <= 5  )); then REPLY="SAVEPOINT"; else REPLY=""; fi }                    # 25% SAVEPOINT
chain()      { if (( RANDOM % 20 + 1 <= 7  )); then no; REPLY="AND $REPLY CHAIN"; else REPLY=""; fi }         # 35% AND [NO] CHAIN
release()    { if (( RANDOM % 20 + 1 <= 7  )); then REPLY="NO RELEASE"; else REPLY=""; fi }                   # 35% NO RELEASE
quick()      { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="QUICK"; else REPLY=""; fi }                        # 20% QUICK
extended()   { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="EXTENDED"; else REPLY=""; fi }                     # 20% EXTENDED
usefrm()     { if (( RANDOM % 20 + 1 <= 4  )); then REPLY="USE_FRM"; else REPLY=""; fi }                      # 20% USE_FRM
localonly()  { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="LOCAL"; else REPLY=""; fi }                        # 50% LOCAL
# ========================================= Dual
n2()         { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="1"; else REPLY="2"; fi }                       # 50% 1, 50% 2
onoff()      { if (( RANDOM % 20 + 1 <= 15 )); then REPLY="ON"; else REPLY="OFF"; fi }                    # 75% ON, 25% OFF
onoff01()    { if (( RANDOM % 20 + 1 <= 15 )); then REPLY="1"; else REPLY="0"; fi }                       # 75% 1 (on), 25% 0 (off)
equals()     { if (( RANDOM % 20 + 1 <= 3  )); then REPLY="="; else REPLY=" "; fi }                       # 15% =, 85% space
allor1()     { if (( RANDOM % 20 + 1 <= 16 )); then REPLY="*"; else REPLY="1"; fi }                       # 80% *, 20% 1
startsends() { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="STARTS"; else REPLY="ENDS"; fi }               # 50% STARTS, 50% ENDS
globses()    { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="GLOBAL"; else REPLY="SESSION"; fi }            # 50% GLOBAL, 50% SESSION
andor()      { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="AND"; else REPLY="OR"; fi }                    # 50% AND, 50% OR
leftright()  { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="LEFT"; else REPLY="RIGHT"; fi }                # 50% LEFT, 50% RIGHT (for JOINs)
# xid() moved to XA helpers section below (expanded with branches/format IDs)
disenable()  { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="ENABLE"; else REPLY="DISABLE"; fi }            # 50% ENABLE, 50% DISABLE
sdisenable() { if (( RANDOM % 20 + 1 <= 16 )); then disenable; else REPLY="DISABLE ON SLAVE"; fi }        # 40% ENABLE, 40% DISALBE, 20% DISABLE ON SLAVE
schedule()   { if (( RANDOM % 20 + 1 <= 10 )); then timestamp; local _v1=$REPLY; intervaladd; REPLY="AT $_v1 $REPLY"; else interval; local _v1=$REPLY; opstend; REPLY="EVERY $_v1 $REPLY"; fi }  # 50% AT, 50% EVERY (for EVENTs)
readwrite()  { if (( RANDOM % 30 + 1 <= 10 )); then REPLY='READ ONLY'; else REPLY='READ WRITE'; fi }      # 50% READ ONLY, 50% WRITE ONLY
binmaster()  { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="BINARY"; else REPLY="MASTER"; fi }             # 50% BINARY, 50% MASTER
nowblocal()  { if (( RANDOM % 20 + 1 <= 10 )); then REPLY="NO_WRITE_TO_BINLOG"; else REPLY="LOCAL"; fi }  # 50% NO_WRITE_TO_BINLOG, 50% LOCAL
locktype()   { if (( RANDOM % 20 + 1 <= 10 )); then localonly; REPLY="READ $REPLY"; else lowprio; REPLY="$REPLY WRITE"; fi }  # 50% READ [LOCAL], 50% [LOW_PRIORITY] WRITE
charactert() { if (( RANDOM % 20 + 1 <= 8  )); then character; local _v1=$REPLY; charactert; REPLY="$_v1 $REPLY"; else character; fi }  # 40% NESTED, 60% SINGLE
danrorfull() { if (( RANDOM % 20 + 1 <= 19 )); then dataornum; else fullnrfunc; fi }                      # 95% data, 5% nested full nr function
numericadd() { if (( RANDOM % 20 + 1 <= 8  )); then numsimple; local _v1=$REPLY; eitherornn; local _v2=$REPLY; numericadd; REPLY="$_v1 $_v2 $REPLY"; else numsimple; local _v1=$REPLY; eitherornn; REPLY="$_v1 $REPLY"; fi }  # 40% NESTED, 60% SINGLE
dataornum()  { if (( RANDOM % 20 + 1 <= 4  )); then data; else nn1000; fi }                               # 20% data, 80% -1000 to 1000
dataornum2() { if (( RANDOM % 20 + 1 <= 2  )); then data; else n100; fi }                                 # 10% data, 90% 0 to 100
fullnrfunc() { if (( RANDOM % 20 + 1 <= 15 )); then eitherornn; local _v1=$REPLY; numsimple; local _v2=$REPLY; eitherornn; REPLY="$_v1 $_v2 $REPLY"; else eitherornn; local _v1=$REPLY; numsimple; local _v2=$REPLY; eitherornn; local _v3=$REPLY; numericadd; REPLY="$_v1 $_v2 $_v3 $REPLY"; fi }
aggregated() { if (( RANDOM % 20 + 1 <= 16 )); then aggregate; local _v1=$REPLY; data; REPLY=${_v1/DUMMY/$REPLY}; else aggregate; local _v1=$REPLY; danrorfull; REPLY=${_v1/DUMMY/$REPLY}; fi }
aggregatec() { if (( RANDOM % 20 + 1 <= 16 )); then aggregate; local _v1=$REPLY; n3; REPLY=${_v1/DUMMY/c$REPLY}; else aggregate; local _v1=$REPLY; aggregated; REPLY=${_v1/DUMMY/$REPLY}; fi }
azn9()       { if (( RANDOM % 36 + 1 <= 26 )); then az; else n9; fi }
dategen()    { if (( RANDOM % 20 + 1 <= 19 )); then dategenpr; else timefuncpr; fi }
# ========================================= Triple
eitherornn() { if (( RANDOM % 20 + 1 <= 8 )); then dataornum; else if (( RANDOM % 20 + 1 <= 13 )); then numericop; else timefunc; fi; fi }  # 40% data, 39% NUMERIC FUNCTION, 21% time function
subpart()    { if (( RANDOM % 20 + 1 <= 4 )); then if (( RANDOM % 20 + 1 <= 10 )); then linear; local _v1=$REPLY; collist2; local _v2=$REPLY; partnumsub; REPLY="SUBPARTITION BY ${_v1} HASH(${_v2}) ${REPLY}"; else linear; local _v1=$REPLY; algorithm; local _v2=$REPLY; collist2; local _v3=$REPLY; partnumsub; REPLY="SUBPARTITION BY ${_v1} KEY ${_v2} (${_v3}) ${REPLY}"; fi; else REPLY=""; fi }  # 10% HASH, 10% KEY, 80% EMPTY
partdefar1() { if (( RANDOM % 20 + 1 <= 4 )); then partdef1b; REPLY=", ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; REPLY=", PARTITION pMAX VALUES LESS THAN MAXVALUE ${_v1} ${_v2} ${_v3} ${REPLY}"; else REPLY=""; fi; fi }
partdefar2() { if (( RANDOM % 20 + 1 <= 4 )); then partdef2b; REPLY=", ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; REPLY=", PARTITION pMAX VALUES LESS THAN (MAXVALUE,MAXVALUE) ${_v1} ${_v2} ${_v3} ${REPLY}"; else REPLY=""; fi; fi }
partdefar3() { if (( RANDOM % 20 + 1 <= 4 )); then partdef3b; REPLY=", ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; REPLY=", PARTITION pNEG VALUES IN (-1,-2,-3,-4,-5) ${_v1} ${_v2} ${_v3} ${REPLY}"; else REPLY=""; fi; fi }
partdefar4() { if (( RANDOM % 20 + 1 <= 4 )); then partdef4b; REPLY=", ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then partse; local _v1=$REPLY; partcomment; local _v2=$REPLY; partmax; local _v3=$REPLY; partmin; REPLY=", PARTITION pNEG VALUES IN ((NULL,NULL),(-2,-2),(-3,-3),(-4,-4),(-5,-5)) ${_v1} ${_v2} ${_v3} ${REPLY}"; else REPLY=""; fi; fi }
ac()         { if (( RANDOM % 20 + 1 <= 8 )); then REPLY="a"; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="b"; else REPLY="c"; fi; fi }
algorithm()  { if (( RANDOM % 20 + 1 <= 6 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="ALGORITHM=1"; else REPLY="ALGORITHM=2"; fi; else REPLY=""; fi }
trxopt()     { if (( RANDOM % 20 + 1 <= 10 )); then readwrite; else if (( RANDOM % 20 + 1 <= 10 )); then readwrite; REPLY="WITH CONSISTENT SNAPSHOT, ${REPLY}"; else REPLY="WITH CONSISTENT SNAPSHOT"; fi; fi }
definer()    { if (( RANDOM % 20 + 1 <= 6 )); then if (( RANDOM % 20 + 1 <= 10 )); then user; REPLY="DEFINER=${REPLY}"; else REPLY="DEFINER=CURRENT_USER"; fi; else REPLY=""; fi }
suspendfm()  { if (( RANDOM % 20 + 1 <= 2 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="SUSPEND"; else REPLY="SUSPEND FOR MIGRATE"; fi; else REPLY=""; fi }
joinresume() { if (( RANDOM % 20 + 1 <= 6 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="JOIN"; else REPLY="RESUME"; fi; else REPLY=""; fi }
emglobses()  { if (( RANDOM % 20 + 1 <= 14 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="GLOBAL"; else REPLY="SESSION"; fi; else REPLY=""; fi }
emascdesc()  { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="ASC"; else REPLY="DESC"; fi; else REPLY=""; fi }
bincharco()  { if (( RANDOM % 30 + 1 <= 10 )); then REPLY='CHARACTER SET "Binary" COLLATE "Binary"'; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY='CHARACTER SET "utf8" COLLATE "utf8_bin"'; else REPLY='CHARACTER SET "latin1" COLLATE "latin1_bin"'; fi; fi }
inout()      { if (( RANDOM % 20 + 1 <= 8 )); then REPLY="INOUT"; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="IN"; else REPLY="OUT"; fi; fi }
nowriteloc() { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="NO_WRITE_TO_BINLOG"; else REPLY="LOCAL"; fi; else REPLY=""; fi }
partrange()  { if (( RANDOM % 20 + 1 <= 7 )); then n3; local _v1=$REPLY; partdef1; REPLY="RANGE(c${_v1}) ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then n3; local _v1=$REPLY; subpart; local _v2=$REPLY; partdef1; REPLY="RANGE(c${_v1}) ${_v2} ${REPLY}"; else collist2; local _v1=$REPLY; partdef2; REPLY="RANGE COLUMNS(${_v1}) ${REPLY}"; fi; fi }
partlist()   { if (( RANDOM % 20 + 1 <= 7 )); then n3; local _v1=$REPLY; partdef3; REPLY="LIST(c${_v1}) ${REPLY}"; else if (( RANDOM % 20 + 1 <= 10 )); then n3; local _v1=$REPLY; subpart; local _v2=$REPLY; partdef3; REPLY="LIST(c${_v1}) ${_v2} ${REPLY}"; else collist2; local _v1=$REPLY; partdef4; REPLY="LIST COLUMNS(${_v1}) ${REPLY}"; fi; fi }
# ========================================= Quadruple
collist1()   { if (( RANDOM % 20 + 1 <= 8 )); then if (( RANDOM % 20 + 1 <= 12 )); then n3; REPLY="(c${REPLY})"; else n3; local _v1=$REPLY; n3; REPLY="(c${_v1},c${REPLY})"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="(c1,c2)"; else REPLY="(c3,c1)"; fi; fi }
collist2()   { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="(c1,c2)"; else REPLY="(c2,c3)"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="(c1,c3)"; else REPLY="(c3,c1)"; fi; fi }
like()       { if (( RANDOM % 20 + 1 <= 8 )); then if (( RANDOM % 20 + 1 <= 5 )); then azn9; REPLY="LIKE '${REPLY}'"; else azn9; REPLY="LIKE '${REPLY}%'"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then azn9; REPLY="LIKE '%${REPLY}'"; else azn9; REPLY="LIKE '%${REPLY}%'"; fi; fi }
isolation()  { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="READ COMMITTED"; else REPLY="REPEATABLE READ"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="READ UNCOMMITTED"; else REPLY="SERIALIZABLE"; fi; fi }
timestamp()  { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="CURRENT_TIMESTAMP"; else REPLY="CURRENT_TIMESTAMP()"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="NOW()"; else data; fi; fi }
partdecl()   { if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then parthash; else partkey; fi; else if (( RANDOM % 20 + 1 <= 10 )); then partrange; else partlist; fi; fi }
data()       { if (( RANDOM % 20 + 1 <= 16 )); then if (( RANDOM % 20 + 1 <= 10 )); then if (( PWGEN == 1 )); then if (( _PWGEN_POOL_SIZE > 0 )); then local _len=$((RANDOM % 1027 + 1)); REPLY="'${_pwgen_pool[$((RANDOM % _PWGEN_POOL_SIZE))]:0:_len}'"; else REPLY="'$(pwgen -ycnsr "|\'\\\"\\\`" $(($RANDOM % 1027 + 1)) 1)'"; fi; else datafile; fi; else datafile; fi; else if (( RANDOM % 20 + 1 <= 10 )); then timefunc; else fullnrfunc; local _v1=$REPLY; numsimple; local _v2=$REPLY; fullnrfunc; REPLY="(${_v1}) ${_v2} (${REPLY})"; fi; fi }
# ========================================= Quintuple
operator()   { if (( RANDOM % 20 + 1 <= 8 )); then REPLY="="; else if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY=">"; else REPLY=">="; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="<"; else REPLY="<="; fi; fi; fi }
pstimer()    { if (( RANDOM % 20 + 1 <= 4 )); then REPLY="idle"; else if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="wait"; else REPLY="stage"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="statement"; else REPLY="statement"; fi; fi; fi }
pstimernm()  { if (( RANDOM % 20 + 1 <= 4 )); then REPLY="CYCLE"; else if (( RANDOM % 20 + 1 <= 10 )); then if (( RANDOM % 20 + 1 <= 10 )); then REPLY="NANOSECOND"; else REPLY="MICROSECOND"; fi; else if (( RANDOM % 20 + 1 <= 10 )); then REPLY="MILLISECOND"; else REPLY="TICK"; fi; fi; fi }
# ========================================= JSON, String, Cast, Case, Coalesce, Names, Alter helpers
jsonfunc()   {
  case $(( RANDOM % 8 + 1 )) in
    1) n3; REPLY="JSON_OBJECT('key', c${REPLY})";;
    2) REPLY="JSON_ARRAY(c1, c2, c3)";;
    3) n3; REPLY="JSON_EXTRACT(c${REPLY}, '\$.key')";;
    4) n3; REPLY="JSON_CONTAINS(c${REPLY}, '\"value\"')";;
    5) n3; REPLY="JSON_VALUE(c${REPLY}, '\$.key')";;
    6) n3; local _v1=$REPLY; data; REPLY="JSON_SET(c${_v1}, '\$.key', ${REPLY})";;
    7) n3; REPLY="JSON_TYPE(c${REPLY})";;
    8) n3; local _v1=$REPLY; n3; REPLY="JSON_MERGE_PATCH(c${_v1}, c${REPLY})";;
    *) REPLY="Assert: invalid random case selection in jsonfunc() case";;
  esac
}
stringfunc() {
  case $(( RANDOM % 10 + 1 )) in
    1) n3; local _v1=$REPLY; data; REPLY="CONCAT(c${_v1}, ${REPLY})";;
    2) n3; local _v1=$REPLY; n10; local _v2=$REPLY; n10; REPLY="SUBSTRING(c${_v1}, ${_v2}, ${REPLY})";;
    3) n3; REPLY="UPPER(c${REPLY})";;
    4) n3; REPLY="LOWER(c${REPLY})";;
    5) n3; REPLY="TRIM(c${REPLY})";;
    6) n3; REPLY="LENGTH(c${REPLY})";;
    7) n3; REPLY="REVERSE(c${REPLY})";;
    8) n3; local _v1=$REPLY; data; local _v2=$REPLY; data; REPLY="REPLACE(c${_v1}, ${_v2}, ${REPLY})";;
    9) n3; local _v1=$REPLY; n3; REPLY="CONCAT_WS(',', c${_v1}, c${REPLY})";;
   10) n3; REPLY="CHAR_LENGTH(c${REPLY})";;
    *) REPLY="Assert: invalid random case selection in stringfunc() case";;
  esac
}
castexpr()   {
  case $(( RANDOM % 6 + 1 )) in
    1) n3; REPLY="CAST(c${REPLY} AS CHAR)";;
    2) n3; REPLY="CAST(c${REPLY} AS SIGNED)";;
    3) n3; REPLY="CAST(c${REPLY} AS UNSIGNED)";;
    4) n3; REPLY="CAST(c${REPLY} AS DATE)";;
    5) n3; REPLY="CAST(c${REPLY} AS DECIMAL(10,2))";;
    6) n3; REPLY="CONVERT(c${REPLY}, CHAR)";;
    *) REPLY="Assert: invalid random case selection in castexpr() case";;
  esac
}
caseexpr()   { n3; local _v1=$REPLY; data; local _v2=$REPLY; data; local _v3=$REPLY; data; REPLY="CASE WHEN c${_v1} IS NULL THEN ${_v2} WHEN c${_v1} = ${_v3} THEN ${REPLY} ELSE c${_v1} END"; }
coalesceexpr() {
  case $(( RANDOM % 4 + 1 )) in
    1) n3; local _v1=$REPLY; data; REPLY="COALESCE(c${_v1},${REPLY})";;
    2) n3; local _v1=$REPLY; data; REPLY="NULLIF(c${_v1},${REPLY})";;
    3) n3; local _v1=$REPLY; data; REPLY="IFNULL(c${_v1},${REPLY})";;
    4) n3; local _v1=$REPLY; data; local _v2=$REPLY; data; REPLY="IF(c${_v1} IS NOT NULL,${_v2},${REPLY})";;
    *) REPLY="Assert: invalid random case selection in coalesceexpr() case";;
  esac
}
seqname()    {
  case $(( RANDOM % 3 + 1 )) in
    1) REPLY="s1";;
    2) REPLY="s2";;
    3) REPLY="s3";;
    *) REPLY="Assert: invalid random case selection in seqname() case";;
  esac
}
idxname()    {
  case $(( RANDOM % 3 + 1 )) in
    1) REPLY="idx1";;
    2) REPLY="idx2";;
    3) REPLY="idx3";;
    *) REPLY="Assert: invalid random case selection in idxname() case";;
  esac
}
checkopt()   {
  case $(( RANDOM % 5 + 1 )) in
    1) REPLY="QUICK";;
    2) REPLY="FAST";;
    3) REPLY="MEDIUM";;
    4) REPLY="EXTENDED";;
    5) REPLY="CHANGED";;
    *) REPLY="Assert: invalid random case selection in checkopt() case";;
  esac
}
algolock()   { if (( RANDOM % 20 + 1 <= 10 )); then REPLY=""; else case $(( RANDOM % 4 + 1 )) in 1) REPLY="ALGORITHM=INPLACE";; 2) REPLY="ALGORITHM=COPY";; 3) REPLY="LOCK=NONE";; 4) REPLY="LOCK=SHARED";; *) REPLY="Assert: invalid random case selection in algolock() case";; esac; fi }
withcheckoption() { if (( RANDOM % 10 + 1 <= 3 )); then REPLY="WITH CHECK OPTION"; else if (( RANDOM % 10 + 1 <= 2 )); then REPLY="WITH CASCADED CHECK OPTION"; else REPLY=""; fi; fi }  # 30% WITH CHECK OPTION, 20% WITH CASCADED CHECK OPTION, 50% empty
# ========================================= Subcalls
subwhact()   { if (( SUBWHEREACTIVE == 0 )); then REPLY="WHERE "; else REPLY=""; fi }  # Only use 'WHERE' if this is not a sub-WHERE
subwhere()   { SUBWHEREACTIVE=1; if (( RANDOM % 20 + 1 <= 4 )); then andor; local _v1=$REPLY; whereal; REPLY="$_v1 $REPLY"; else REPLY=""; fi }  # 20% sub-WHERE
subordby()   { if (( RANDOM % 20 + 1 <= 4 )); then n3; local _v1=$REPLY; emascdesc; REPLY=",c$_v1 $REPLY"; else REPLY=""; fi }                    # 20% sub-ORDER BY
# ========================================= Special/Complex
opstend()    { if (( RANDOM % 20 + 1 <= 4 )); then startsends; local _v1=$REPLY; timestamp; local _v2=$REPLY; intervaladd; REPLY="$_v1 $_v2 $REPLY"; else REPLY=""; fi } # 20% optional START/STOP
where()      { whereal; REPLY="${REPLY//a1./}"; REPLY="${REPLY//a2./}"; REPLY="${REPLY//a3./}"; }             # where():    e.g. WHERE    c1==c2    etc.
wheretbl()   { where; local _w=$REPLY; table; local _t=$REPLY; _w="${_w//c1/$_t.c1}"; _w="${_w//c2/$_t.c2}"; _w="${_w//c3/$_t.c3}"; REPLY="$_w"; }   # wheretbl(): e.g. WHERE t1.c1==t2.c2 etc.
whereal()    {                                                         # whereal():  e.g. WHERE a1.c1==a2.c2 etc.
  WHERE_RND=4; if (( SUBWHEREACTIVE == 1 )); then WHERE_RND=2; fi
  case $(( RANDOM % WHERE_RND + 1 )) in
    1) subwhact; local _v1=$REPLY; alias3; local _v2=$REPLY; n3; local _v3=$REPLY; operator; local _v4=$REPLY; data; local _v5=$REPLY; subwhere; REPLY="$_v1$_v2.c$_v3$_v4$_v5 $REPLY";;
    2) subwhact; local _v1=$REPLY; alias3; local _v2=$REPLY; n3; local _v3=$REPLY; operator; local _v4=$REPLY; alias3; local _v5=$REPLY; n3; local _v6=$REPLY; subwhere; REPLY="$_v1$_v2.c$_v3$_v4$_v5.c$_v6 $REPLY";;
[3-4]) REPLY="";;  # 50% No WHERE clause
    *) REPLY="Assert: invalid random case selection in where() case";;
  esac
  SUBWHEREACTIVE=0
}
orderby()   {
  case $(( RANDOM % 2 + 1 )) in
    1) REPLY="";;  # 50% No ORDER BY clause
    2) n3; local _v1=$REPLY; emascdesc; local _v2=$REPLY; subordby; REPLY="ORDER BY c$_v1 $_v2 $REPLY";;
    *) REPLY="Assert: invalid random case selection in orderby() case";;
  esac
}
winfuncname(){  # Random window function name
  case $(( RANDOM % 10 + 1 )) in
     1) REPLY="ROW_NUMBER()";;
     2) REPLY="RANK()";;
     3) REPLY="DENSE_RANK()";;
     4) n10; REPLY="NTILE(${REPLY})";;
     5) n3; REPLY="LAG(c${REPLY})";;
     6) n3; REPLY="LEAD(c${REPLY})";;
     7) n3; REPLY="FIRST_VALUE(c${REPLY})";;
     8) n3; REPLY="LAST_VALUE(c${REPLY})";;
     9) n3; REPLY="SUM(c${REPLY})";;
    10) REPLY="COUNT(*)";;
     *) REPLY="Assert: invalid random case selection in winfuncname() case";;
  esac
}
winover(){  # OVER clause for window functions
  case $(( RANDOM % 4 + 1 )) in
    1) n3; local _v1=$REPLY; emascdesc; REPLY="OVER (ORDER BY c${_v1} ${REPLY})";;
    2) n3; local _v1=$REPLY; n3; local _v2=$REPLY; emascdesc; REPLY="OVER (PARTITION BY c${_v1} ORDER BY c${_v2} ${REPLY})";;
    3) n3; REPLY="OVER (PARTITION BY c${REPLY})";;
    4) REPLY="OVER ()";;
    *) REPLY="Assert: invalid random case selection in winover() case";;
  esac
}
groupby(){  # 50% empty, 50% GROUP BY c<n> [with 20% chance of WITH ROLLUP]
  case $(( RANDOM % 2 + 1 )) in
    1) REPLY="";;
    2) n3; local _v1=$REPLY; if (( RANDOM % 5 + 1 <= 1 )); then REPLY="GROUP BY c${_v1} WITH ROLLUP"; else REPLY="GROUP BY c${_v1}"; fi;;
    *) REPLY="Assert: invalid random case selection in groupby() case";;
  esac
}
having(){  # 70% empty, 30% HAVING clause
  if (( RANDOM % 10 + 1 <= 3 )); then
    case $(( RANDOM % 3 + 1 )) in
      1) n100; REPLY="HAVING COUNT(*)>${REPLY}";;
      2) n3; local _v1=$REPLY; n100; REPLY="HAVING SUM(c${_v1})>${REPLY}";;
      3) n3; REPLY="HAVING c${REPLY} IS NOT NULL";;
      *) REPLY="Assert: invalid random case selection in having() case";;
    esac
  else
    REPLY=""
  fi
}
distinct(){  # 20% DISTINCT, 80% empty
  if (( RANDOM % 5 + 1 <= 1 )); then REPLY="DISTINCT"; else REPLY=""; fi
}
forupdate(){  # 5 equal variants for locking reads
  case $(( RANDOM % 5 + 1 )) in
    1) REPLY="FOR UPDATE";;
    2) REPLY="FOR UPDATE NOWAIT";;
    3) REPLY="FOR UPDATE SKIP LOCKED";;
    4) REPLY="LOCK IN SHARE MODE";;
    5) REPLY="";;
    *) REPLY="Assert: invalid random case selection in forupdate() case";;
  esac
}
returning(){  # 50% RETURNING *, 50% RETURNING c<n>
  case $(( RANDOM % 2 + 1 )) in
    1) REPLY="RETURNING *";;
    2) n3; REPLY="RETURNING c${REPLY}";;
    *) REPLY="Assert: invalid random case selection in returning() case";;
  esac
}
forsystemtime(){  # FOR SYSTEM_TIME variants (4 equal)
  case $(( RANDOM % 4 + 1 )) in
    1) REPLY="FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP";;
    2) dategen; local _v1=$REPLY; dategen; REPLY="FOR SYSTEM_TIME BETWEEN '${_v1}' AND '${REPLY}'";;
    3) dategen; local _v1=$REPLY; dategen; REPLY="FOR SYSTEM_TIME FROM '${_v1}' TO '${REPLY}'";;
    4) REPLY="FOR SYSTEM_TIME ALL";;
    *) REPLY="Assert: invalid random case selection in forsystemtime() case";;
  esac
}
existsq(){  # EXISTS (SELECT 1 FROM <table> WHERE c<n> = <data>)
  table; local _v1=$REPLY; n3; local _v2=$REPLY; data; REPLY="EXISTS (SELECT 1 FROM ${_v1} WHERE c${_v2} = ${REPLY})"
}
orreplace(){  # 33% OR REPLACE, 67% empty
  if (( RANDOM % 3 + 1 <= 1 )); then REPLY="OR REPLACE"; else REPLY=""; fi
}
beforeafter(){  # 50% BEFORE, 50% AFTER
  if (( RANDOM % 2 + 1 <= 1 )); then REPLY="BEFORE"; else REPLY="AFTER"; fi
}
triggerop(){  # 33% INSERT, 33% UPDATE, 33% DELETE
  case $(( RANDOM % 3 + 1 )) in
    1) REPLY="INSERT";;
    2) REPLY="UPDATE";;
    3) REPLY="DELETE";;
    *) REPLY="Assert: invalid random case selection in triggerop() case";;
  esac
}
installsoname() {  # Random INSTALL SONAME for storage engine plugins
  case $(( RANDOM % 10 + 1 )) in
    1) REPLY="INSTALL SONAME 'ha_spider'";;
    2) REPLY="INSTALL SONAME 'ha_rocksdb'";;
    3) REPLY="INSTALL SONAME 'ha_mroonga'";;
    4) REPLY="INSTALL SONAME 'ha_oqgraph'";;
    5) REPLY="INSTALL SONAME 'ha_archive'";;
    6) REPLY="INSTALL SONAME 'ha_federated'";;
    7) REPLY="INSTALL SONAME 'ha_blackhole'";;
    8) REPLY="INSTALL SONAME 'ha_connect'";;
    9) REPLY="INSTALL SONAME 'ha_s3'";;
   10) REPLY="INSTALL SONAME 'ha_spider'";;
    *) REPLY="Assert: invalid random case selection in installsoname() case";;
  esac
}
uninstallsoname() {  # Random UNINSTALL SONAME for storage engine plugins
  case $(( RANDOM % 10 + 1 )) in
    1) REPLY="UNINSTALL SONAME 'ha_spider'";;
    2) REPLY="UNINSTALL SONAME 'ha_rocksdb'";;
    3) REPLY="UNINSTALL SONAME 'ha_mroonga'";;
    4) REPLY="UNINSTALL SONAME 'ha_oqgraph'";;
    5) REPLY="UNINSTALL SONAME 'ha_archive'";;
    6) REPLY="UNINSTALL SONAME 'ha_federated'";;
    7) REPLY="UNINSTALL SONAME 'ha_blackhole'";;
    8) REPLY="UNINSTALL SONAME 'ha_connect'";;
    9) REPLY="UNINSTALL SONAME 'ha_s3'";;
   10) REPLY="UNINSTALL SONAME 'ha_spider'";;
    *) REPLY="Assert: invalid random case selection in uninstallsoname() case";;
  esac
}
onclause() {  # ON clause for JOINs  - 50% ON col=col, 30% USING(col), 20% ON col<operator>data
  n3; local _c1=$REPLY
  case $(( RANDOM % 5 + 1 )) in
    [1-2]) n3; REPLY="ON a1.c${_c1}=a2.c${REPLY}";;
    [3-4]) REPLY="USING (c${_c1})";;
       5) operator; local _op=$REPLY; data; REPLY="ON a1.c${_c1}${_op}${REPLY}";;
       *) REPLY="Assert: invalid random case selection in onclause() case";;
  esac
}
# ========================================= CREATE TABLE clause helpers
rowformat()  { case $(( RANDOM % 5 + 1 )) in 1) REPLY="ROW_FORMAT=DYNAMIC";; 2) REPLY="ROW_FORMAT=COMPACT";; 3) REPLY="ROW_FORMAT=COMPRESSED";; 4) REPLY="ROW_FORMAT=REDUNDANT";; 5) REPLY="ROW_FORMAT=PAGE";; *) REPLY="";; esac }
tableopts()  {  # Additional CREATE TABLE options (each ~15% chance, can combine)
  local _r=""
  if (( RANDOM % 7 == 0 )); then rowformat; _r="${_r} ${REPLY}"; fi
  if (( RANDOM % 7 == 0 )); then n1000; _r="${_r} AUTO_INCREMENT=${REPLY}"; fi
  if (( RANDOM % 7 == 0 )); then n1000; _r="${_r} AVG_ROW_LENGTH=${REPLY}"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} CHECKSUM=1"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} DELAY_KEY_WRITE=1"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} PACK_KEYS=1"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} STATS_PERSISTENT=1"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} STATS_AUTO_RECALC=1"; fi
  if (( RANDOM % 8 == 0 )); then _r="${_r} PAGE_COMPRESSED=1"; fi
  if (( RANDOM % 8 == 0 )); then _r="${_r} PAGE_COMPRESSION_LEVEL=5"; fi
  if (( RANDOM % 7 == 0 )); then n100; _r="${_r} KEY_BLOCK_SIZE=${REPLY}"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} ENCRYPTED=YES"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} ENCRYPTION_KEY_ID=1"; fi
  if (( RANDOM % 10 == 0 )); then _r="${_r} TRANSACTIONAL=1"; fi
  REPLY="$_r"
}
coldefault() {  # Column DEFAULT clause (30% chance)
  if (( RANDOM % 10 + 1 <= 3 )); then
    case $(( RANDOM % 6 + 1 )) in
      1) REPLY="DEFAULT NULL";; 2) REPLY="DEFAULT 0";; 3) REPLY="DEFAULT ''";; 4) REPLY="DEFAULT 1";;
      5) REPLY="DEFAULT CURRENT_TIMESTAMP";; 6) data; REPLY="DEFAULT ${REPLY}";;
      *) REPLY="";;
    esac
  else REPLY=""; fi
}
colnull()    { case $(( RANDOM % 3 + 1 )) in 1) REPLY="NOT NULL";; 2) REPLY="NULL";; 3) REPLY="";; *) REPLY="";; esac }
# ========================================= XA helpers
xid()        { case $(( RANDOM % 6 + 1 )) in 1) REPLY="'xid1'";; 2) REPLY="'xid2'";; 3) REPLY="'xid3'";; 4) REPLY="'xid1','branch1'";; 5) REPLY="'xid2','branch2'";; 6) REPLY="'xid1','',1";; *) REPLY="'xid1'";; esac }
# ========================================= Server-state-affecting SET helpers
importantvar() {  # Variables that significantly affect server behavior
  case $(( RANDOM % 30 + 1 )) in
    1) REPLY="SET @@GLOBAL.innodb_flush_log_at_trx_commit=$((RANDOM % 3))";;
    2) REPLY="SET @@GLOBAL.sync_binlog=$((RANDOM % 2))";;
    3) globses; REPLY="SET @@${REPLY}.foreign_key_checks=$((RANDOM % 2))";;
    4) globses; REPLY="SET @@${REPLY}.unique_checks=$((RANDOM % 2))";;
    5) REPLY="SET @@GLOBAL.innodb_lock_wait_timeout=$((RANDOM % 50 + 1))";;
    6) REPLY="SET @@GLOBAL.lock_wait_timeout=$((RANDOM % 50 + 1))";;
    7) REPLY="SET @@GLOBAL.max_connections=$((RANDOM % 500 + 10))";;
    8) REPLY="SET @@GLOBAL.table_open_cache=$((RANDOM % 2000 + 100))";;
    9) REPLY="SET @@GLOBAL.query_cache_size=$((RANDOM % 67108864))";;
   10) REPLY="SET @@GLOBAL.query_cache_type=$((RANDOM % 3))";;
   11) globses; REPLY="SET @@${REPLY}.join_buffer_size=$((RANDOM % 1048576 + 128))";;
   12) globses; REPLY="SET @@${REPLY}.sort_buffer_size=$((RANDOM % 1048576 + 32768))";;
   13) globses; REPLY="SET @@${REPLY}.tmp_table_size=$((RANDOM % 67108864 + 1024))";;
   14) globses; REPLY="SET @@${REPLY}.max_heap_table_size=$((RANDOM % 67108864 + 16384))";;
   15) REPLY="SET @@GLOBAL.innodb_buffer_pool_size=$((RANDOM % 268435456 + 5242880))";;
   16) REPLY="SET @@GLOBAL.innodb_adaptive_hash_index=$((RANDOM % 2))";;
   17) REPLY="SET @@GLOBAL.innodb_change_buffering='all'";;
   18) REPLY="SET @@GLOBAL.innodb_file_per_table=$((RANDOM % 2))";;
   19) globses; REPLY="SET @@${REPLY}.optimizer_use_condition_selectivity=$((RANDOM % 6 + 1))";;
   20) globses; REPLY="SET @@${REPLY}.optimizer_search_depth=$((RANDOM % 63))";;
   21) globses; REPLY="SET @@${REPLY}.optimizer_prune_level=$((RANDOM % 2))";;
   22) globses; REPLY="SET @@${REPLY}.max_length_for_sort_data=$((RANDOM % 8388608 + 4))";;
   23) globses; REPLY="SET @@${REPLY}.max_sort_length=$((RANDOM % 8388608 + 4))";;
   24) globses; REPLY="SET @@${REPLY}.group_concat_max_len=$((RANDOM % 1048576 + 4))";;
   25) REPLY="SET @@GLOBAL.innodb_stats_persistent_sample_pages=$((RANDOM % 100 + 1))";;
   26) REPLY="SET @@GLOBAL.innodb_compression_level=$((RANDOM % 10))";;
   27) globses; REPLY="SET @@${REPLY}.eq_range_index_dive_limit=$((RANDOM % 200))";;
   28) globses; REPLY="SET @@${REPLY}.histogram_size=$((RANDOM % 255))";;
   29) globses; REPLY="SET @@${REPLY}.histogram_type='SINGLE_PREC_HB'";;
   30) globses; REPLY="SET @@${REPLY}.use_stat_tables='PREFERABLY_FOR_QUERIES'";;
    *) REPLY="SET @@GLOBAL.innodb_flush_log_at_trx_commit=1";;
  esac
}
# ========================================= Lock helpers
lockwait()   { if (( RANDOM % 5 == 0 )); then n9; REPLY="WAIT ${REPLY}"; else REPLY=""; fi }  # 20% WAIT N
# ========================================= Complex join helpers
seljoincol() {  # SELECT column list for complex joins: *, a1.col, a1.col+a2.col, etc.
  case $(( RANDOM % 5 + 1 )) in
    1) REPLY="*";;
    2) n3; REPLY="a1.c${REPLY}";;
    3) n3; local _c1=$REPLY; n3; REPLY="a1.c${_c1}, a2.c${REPLY}";;
    4) n3; local _c=$REPLY; REPLY="a1.c${_c}, a2.c${_c}, COUNT(*)";;
    5) n3; local _c=$REPLY; REPLY="COALESCE(a1.c${_c}, a2.c${_c})";;
    *) REPLY="*";;
  esac
}
join()      {
  case $(( RANDOM % 8 + 1 )) in
    1) REPLY=",";;
    2) REPLY="JOIN";;
    3) REPLY="INNER JOIN";;
    4) REPLY="CROSS JOIN";;
    5) REPLY="STRAIGHT_JOIN";;
    6) REPLY="LEFT JOIN";;
    7) REPLY="RIGHT JOIN";;
    8) REPLY="LEFT OUTER JOIN";;
    *) REPLY="Assert: invalid random case selection in join() case";;
  esac
}
lastjoin()  {
  join; local _j=$REPLY
  if [[ "$_j" == "JOIN" ]]; then natural; REPLY="$REPLY JOIN"; else REPLY="$_j"; fi
}
selectq()   {  # Select Query. Do not use 'select' as select is a reserved system command, use 'selectq' instead
  case $(( RANDOM % 16 + 1 )) in  # Select (needs further work: JOIN syntax + SELECT options)
    1) table; REPLY="SELECT * FROM $REPLY";;
    2) aggregatec; local _v1=$REPLY; table; REPLY="SELECT $_v1 FROM $REPLY";;
    3) aggregated; REPLY="SELECT $REPLY";;
    4) case $(( RANDOM % 2 + 1 )) in
        1) selectq; REPLY="SELECT * FROM ($REPLY) AS a1";;
        2) query; REPLY="SELECT * FROM ($REPLY) AS a1";;
        *) REPLY="Assert: invalid random case selection in SELECT FROM (subquery) case";;
       esac;;
    5) n3; local _v1=$REPLY; table; REPLY="SELECT c$_v1 FROM $REPLY";;
    6) n3; local _v1=$REPLY; n3; local _v2=$REPLY; table; REPLY="SELECT c$_v1,c$_v2 FROM $REPLY";;
    7) n3; local _v1=$REPLY; n3; local _v2=$REPLY; table; local _v3=$REPLY; lastjoin; local _v4=$REPLY; table; local _v5=$REPLY; whereal; REPLY="SELECT c$_v1,c$_v2 FROM $_v3 AS a1 $_v4 $_v5 AS a2 $REPLY";;
    8) n3; local _v1=$REPLY; table; local _v2=$REPLY; join; local _v3=$REPLY; table; local _v4=$REPLY; lastjoin; local _v5=$REPLY; table; local _v6=$REPLY; whereal; REPLY="SELECT c$_v1 FROM $_v2 AS a1 $_v3 $_v4 AS a2 $_v5 $_v6 AS a3 $REPLY";;
    9) case $(( RANDOM % 2 + 1 )) in
        1) table; local _ft=$REPLY; n3; local _v1=$REPLY; joinlronla; local _v2=$REPLY; table; local _v3=$REPLY; n3; local _v4=$REPLY; REPLY="SELECT $_ft.c$_v1 FROM $_ft $_v2 $_v3 ON $_ft.c$_v4";;
        2) table; local _ft=$REPLY; n3; local _v1=$REPLY; table; local _v2=$REPLY; joinlronla; local _v3=$REPLY; n3; local _v4=$REPLY; REPLY="SELECT $_ft.c$_v1 FROM $_v2 $_v3 $_ft ON $_ft.c$_v4";;
        *) REPLY="Assert: invalid random case selection in FIXEDTABLE1 join case";;
       esac;;
   10) case $(( RANDOM % 2 + 1 )) in
        1) table; local _ft=$REPLY; n3; local _v1=$REPLY; joinlronla; local _v2=$REPLY; table; local _v3=$REPLY; n3; local _v4=$REPLY; data; local _v5=$REPLY; REPLY="SELECT $_ft.c$_v1 FROM $_ft $_v2 $_v3 ON $_ft.c$_v4=$_v5";;
        2) table; local _ft=$REPLY; n3; local _v1=$REPLY; table; local _v2=$REPLY; joinlronla; local _v3=$REPLY; n3; local _v4=$REPLY; data; local _v5=$REPLY; REPLY="SELECT $_ft.c$_v1 FROM $_v2 $_v3 $_ft ON $_ft.c$_v4=$_v5";;
        *) REPLY="Assert: invalid random case selection in FIXEDTABLE2 join case";;
       esac;;
   11) n3; local _v1=$REPLY; table; REPLY="SELECT DISTINCT c$_v1, COUNT(*) FROM $REPLY GROUP BY c$_v1";;
   12) n3; local _v1=$REPLY; winfuncname; local _v2=$REPLY; winover; local _v3=$REPLY; table; REPLY="SELECT c$_v1, $_v2 $_v3 FROM $REPLY";;
   13) table; local _v1=$REPLY; where; local _v2=$REPLY; forupdate; local _v3=$REPLY; REPLY="SELECT * FROM $_v1 $_v2 $_v3";;
   14) table; local _v1=$REPLY; existsq; local _v2=$REPLY; REPLY="SELECT * FROM $_v1 WHERE $_v2";;
   15) case $(( RANDOM % 4 + 1 )) in
        1) stringfunc; local _v1=$REPLY; table; REPLY="SELECT $_v1 FROM $REPLY";;
        2) castexpr; local _v1=$REPLY; table; REPLY="SELECT $_v1 FROM $REPLY";;
        3) coalesceexpr; local _v1=$REPLY; table; REPLY="SELECT $_v1 FROM $REPLY";;
        4) jsonfunc; local _v1=$REPLY; table; REPLY="SELECT $_v1 FROM $REPLY";;
        *) REPLY="Assert: invalid random case selection in expression functions case";;
       esac;;
   16) table; local _v1=$REPLY; table; local _v2=$REPLY; n3; local _v3=$REPLY; REPLY="SELECT * FROM $_v1 AS a1, LATERAL (SELECT * FROM $_v2 WHERE c$_v3 = a1.c$_v3 LIMIT 1) AS a2";;
    *) REPLY="Assert: invalid random case selection in SELECT case";;
  esac
}

query(){
  case $(($RANDOM % 72 + 1)) in
    # Frequencies for CREATE (1-3), INSERT (4-7), and DROP (8) statements are well tuned, please do not change these case ranges
    [1-3]) case $(($RANDOM % 10 + 1)) in  # CREATE
        1) temp; local _temp=$REPLY; ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct1=$REPLY; pc; local _pc=$REPLY; ctype; local _ct2=$REPLY; vc; local _vc=$REPLY; sv; local _sv=$REPLY; engine; local _eng=$REPLY; partitionby; local _part=$REPLY; tableopts; local _to=$REPLY
           REPLY="CREATE ${_temp}TABLE ${_ine} ${_tbl} (c1 ${_pk},c2 ${_ct1} ${_pc} ,c3 ${_ct2} ${_vc} ) ${_sv} ENGINE=${_eng} ${_to} ${_part}";;
        2) temp; local _temp=$REPLY; ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; pc; local _pc=$REPLY; ctype; local _ct3=$REPLY; vc; local _vc=$REPLY; sv; local _sv=$REPLY; engine; local _eng=$REPLY; partitionby; local _part=$REPLY; tableopts; local _to=$REPLY
           REPLY="CREATE ${_temp}TABLE ${_ine} ${_tbl} (c1 ${_ct1},c2 ${_ct2} ${_pc} ,c3 ${_ct3} ${_vc}) ${_sv} ENGINE=${_eng} ${_to} ${_part}";;
        3) ctype; local C1TYPE=$REPLY
           if [[ "$C1TYPE" == *CHAR* || "$C1TYPE" == *BLOB* || "$C1TYPE" == *TEXT* ]]; then
             temp; local _temp=$REPLY; ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; ctype; local _ct2=$REPLY; vc; local _vc=$REPLY; ctype; local _ct3=$REPLY; pc; local _pc=$REPLY; n10; local _n10=$REPLY; sv; local _sv=$REPLY; engine; local _eng=$REPLY; partitionby; local _part=$REPLY; tableopts; local _to=$REPLY
             REPLY="CREATE ${_temp}TABLE ${_ine} ${_tbl} (c1 ${C1TYPE},c2 ${_ct2} ${_vc},c3 ${_ct3} ${_pc}, PRIMARY KEY(c1(${_n10}))) ${_sv} ENGINE=${_eng} ${_to} ${_part}"
           else
             temp; local _temp=$REPLY; ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; ctype; local _ct2=$REPLY; pc; local _pc=$REPLY; ctype; local _ct3=$REPLY; vc; local _vc=$REPLY; sv; local _sv=$REPLY; engine; local _eng=$REPLY; partitionby; local _part=$REPLY; tableopts; local _to=$REPLY
             REPLY="CREATE ${_temp}TABLE ${_ine} ${_tbl} (c1 ${C1TYPE},c2 ${_ct2} ${_pc},c3 ${_ct3} ${_vc}, PRIMARY KEY(c1)) ${_sv} ENGINE=${_eng} ${_to} ${_part}"
           fi;;
        7) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct1=$REPLY; colnull; local _cn1=$REPLY; coldefault; local _cd1=$REPLY; ctype; local _ct2=$REPLY; colnull; local _cn2=$REPLY; coldefault; local _cd2=$REPLY; ctype; local _ct3=$REPLY; colnull; local _cn3=$REPLY; coldefault; local _cd3=$REPLY; engine; local _eng=$REPLY; tableopts; local _to=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk},c2 ${_ct1} ${_cn1} ${_cd1},c3 ${_ct2} ${_cn2} ${_cd2},c4 ${_ct3} ${_cn3} ${_cd3}) ENGINE=${_eng} ${_to}";;
        8) ifnotexist; local _ine=$REPLY; table; local _tbl1=$REPLY; table; local _tbl2=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl1} LIKE ${_tbl2}";;
        9) orreplace; local _or=$REPLY; table; local _tbl=$REPLY; engine; local _eng=$REPLY; selectq; local _sq=$REPLY
           REPLY="CREATE ${_or} TABLE ${_tbl} ENGINE=${_eng} AS ${_sq}";;
       10) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct1=$REPLY; n3; local _c=$REPLY; engine; local _eng=$REPLY; tableopts; local _to=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk},c2 ${_ct1},c3 INT, INDEX idx1(c${_c})) ENGINE=${_eng} ${_to}";;
        4) if (( SHEDULING_ENABLED == 1 )); then
             definer; local _def=$REPLY; ifnotexist; local _ine=$REPLY; event; local _evt=$REPLY; schedule; local _sched=$REPLY; completion; local _comp=$REPLY; sdisenable; local _sdis=$REPLY; comment; local _cmt=$REPLY; query; local _q=$REPLY
             REPLY="CREATE ${_def} EVENT ${_ine} ${_evt} ON SCHEDULE ${_sched} ${_comp} ${_sdis} ${_cmt} DO ${_q}"
           else
             query
           fi;;
        5) case $(($RANDOM % 19 + 1)) in
         [1-9]) definer; local _def=$REPLY; func; local _fn=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; charactert; local _char=$REPLY
                REPLY="CREATE ${_def} FUNCTION ${_fn} (i1 ${_ct1}) RETURNS ${_ct2} ${_char} RETURN CONCAT('function output:',i1)";;
        1[0-8]) definer; local _def=$REPLY; func; local _fn=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; ctype; local _ct3=$REPLY; charactert; local _char=$REPLY
                REPLY="CREATE ${_def} FUNCTION ${_fn} (i1 ${_ct1},i2 ${_ct2}) RETURNS ${_ct3} ${_char} RETURN CONCAT('function output:',i1)";;
            19) definer; local _def=$REPLY; func; local _fn=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; charactert; local _char=$REPLY; query; local _q=$REPLY
                REPLY="CREATE ${_def} FUNCTION ${_fn} (i1 ${_ct1}) RETURNS ${_ct2} ${_char} RETURN ${_q}";;
             *) REPLY="Assert: invalid random case selection in functions case";;
           esac;;
        6) case $(($RANDOM % 2 + 1)) in
             1) definer; local _def=$REPLY; proc; local _pr=$REPLY; inout; local _io=$REPLY; ctype; local _ct=$REPLY; charactert; local _char=$REPLY; query; local _q=$REPLY
                REPLY="CREATE ${_def} PROCEDURE ${_pr} (${_io} i1 ${_ct}) ${_char} ${_q}";;
             2) definer; local _def=$REPLY; proc; local _pr=$REPLY; inout; local _io1=$REPLY; ctype; local _ct1=$REPLY; inout; local _io2=$REPLY; ctype; local _ct2=$REPLY; charactert; local _char=$REPLY; query; local _q=$REPLY
                REPLY="CREATE ${_def} PROCEDURE ${_pr} (${_io1} i1 ${_ct1}, ${_io2} i2 ${_ct2}) ${_char} ${_q}";;
             *) REPLY="Assert: invalid random case selection in procedures case";;
           esac;;
        *) REPLY="Assert: invalid random case selection in CREATE case";;
      esac;;
    [4-7]) case $(($RANDOM % 2 + 1)) in  # Insert
        1) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY
           REPLY="INSERT INTO ${_tbl} VALUES (${_d1},${_d2},${_d3})";;
        2) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY
           REPLY="INSERT INTO ${_tbl1} SELECT * FROM ${_tbl2}";;
        *) REPLY="Assert: invalid random case selection in INSERT case";;
      esac;;
    8)  case $(($RANDOM % 11 + 1)) in  # Drop
    [1-5]) ifexist; local _ie=$REPLY; table; local _tbl=$REPLY
           REPLY="DROP TABLE ${_ie} ${_tbl}";;
    [6-7]) if (( SHEDULING_ENABLED == 1 )); then
             ifexist; local _ie=$REPLY; event; local _evt=$REPLY
             REPLY="DROP EVENT ${_ie} ${_evt}"
           else
             query
           fi;;
    [8-9]) ifexist; local _ie=$REPLY; func; local _fn=$REPLY
           REPLY="DROP FUNCTION ${_ie} ${_fn}";;
   1[0-1]) ifexist; local _ie=$REPLY; proc; local _pr=$REPLY
           REPLY="DROP PROCEDURE ${_ie} ${_pr}";;
        *) REPLY="Assert: invalid random case selection in DROP case";;
      esac;;
    9) case $(($RANDOM % 2 + 1)) in  # Load data infile/select into outfile
        1) n9; local _n9=$REPLY; table; local _tbl=$REPLY
           REPLY="LOAD DATA INFILE 'out${_n9}' INTO TABLE ${_tbl}";;
        2) table; local _tbl=$REPLY; n9; local _n9=$REPLY
           REPLY="SELECT * FROM ${_tbl} INTO OUTFILE 'out${_n9}'";;
        *) REPLY="Assert: invalid random case selection in load data infile/select into outfile case";;
      esac;;
    10) case $(($RANDOM % 7 + 1)) in  # Select
        1) selectq;;
        2) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} UNION ${REPLY}";;
        3) selectq; local _sq1=$REPLY; selectq; local _sq2=$REPLY; selectq; REPLY="${_sq1} UNION ${_sq2} UNION ${REPLY}";;
        4) table; local _tbl=$REPLY; selectq; REPLY="SELECT c1 FROM ${_tbl} WHERE (c1) IN (${REPLY})";;
        5) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY; operator; local _op=$REPLY; data; local _d=$REPLY
           REPLY="SELECT c1 FROM ${_tbl1} WHERE (c1) IN (SELECT c1 FROM ${_tbl2} WHERE c1 ${_op} ${_d})";;
        6) selectq; REPLY="SELECT (${REPLY})";;
        7) selectq; local _sq1=$REPLY; selectq; local _sq2=$REPLY; selectq; local _sq3=$REPLY; selectq; local _sq4=$REPLY; selectq; local _sq5=$REPLY; selectq; local _sq6=$REPLY; selectq
           REPLY="SELECT (SELECT (${_sq1}) OR (${_sq2})) AND (SELECT (SELECT (${_sq3}) AND (${_sq4}))) OR ((${_sq5}) AND (${_sq6})) OR (${REPLY})";;
        *) REPLY="Assert: invalid random case selection in main select case";;
      esac;;
    11) case $(($RANDOM % 9 + 1)) in  # Delete
        1) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; table; local _tbl=$REPLY; partition; local _part=$REPLY; where; local _wh=$REPLY; orderby; local _ob=$REPLY; limit
           REPLY="DELETE ${_lp} ${_qk} ${_ig} FROM ${_tbl} ${_part} ${_wh} ${_ob} ${REPLY}";;
        2) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} ${_al} FROM ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        3) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} FROM ${_al} USING ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        4) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} ${_al1},${_al2} FROM ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        5) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} FROM ${_al1},${_al2} USING ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        6) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; alias3; local _al3=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} ${_al1},${_al2},${_al3} FROM ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        7) lowprio; local _lp=$REPLY; quick; local _qk=$REPLY; ignore; local _ig=$REPLY; alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; alias3; local _al3=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_lp} ${_qk} ${_ig} FROM ${_al1},${_al2},${_al3} USING ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        8) alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE ${_al1},${_al2} FROM ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        9) alias3; local _al1=$REPLY; alias3; local _al2=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; lastjoin; local _lj=$REPLY; table; local _tbl3=$REPLY; whereal
           REPLY="DELETE FROM ${_al1},${_al2} USING ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${_lj} ${_tbl3} AS a3 ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in DELETE case";;
      esac;;
    12) table; REPLY="TRUNCATE ${REPLY}";;
    13) case $(($RANDOM % 3 + 1)) in  # UPDATE
        1) table; local _tbl=$REPLY; data; REPLY="UPDATE ${_tbl} SET c1=${REPLY}";;
        2) table; local _tbl=$REPLY; data; local _d=$REPLY; where; REPLY="UPDATE ${_tbl} SET c1=${_d} ${REPLY}";;
        3) table; local _tbl=$REPLY; data; local _d=$REPLY; where; local _wh=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="UPDATE ${_tbl} SET c1=${_d} ${_wh} ${_ob} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in UPDATE case";;
      esac;;
    1[4-6]) case $(($RANDOM % 12 + 1)) in  # Generic statements
      [1-4]) REPLY="UNLOCK TABLES";;
      [5-6]) REPLY="SET AUTOCOMMIT=ON";;
        7) nowriteloc; local _nwl=$REPLY; flush; local _fl=$REPLY; table; local _tbl=$REPLY
           local _str="FLUSH ${_nwl} ${_fl}"; REPLY="${_str/DUMMY/$_tbl}";;
        8) reset;;
        9) binmaster; local _bm=$REPLY; data; local _d=$REPLY
           local _str="PURGE ${_bm} LOGS TO '${_d}'"; REPLY="${_str//\'\'/\'}";;
       10) binmaster; REPLY="PURGE ${REPLY} LOGS BEFORE CURRENT_TIMESTAMP()";;
       11) REPLY="SET SQL_BIG_SELECTS=1";;
       12) REPLY="SET MAX_JOIN_SIZE=1000000";;
        *) REPLY="Assert: invalid random case selection in generic statements case";;
      esac;;
    17) emglobses; local _egs=$REPLY; isolation; REPLY="SET ${_egs} TRANSACTION ISOLATION LEVEL ${REPLY}";;  # Transaction isolation level (complete)
    1[8-9]) case $(($RANDOM % 37 + 1)) in  # SET statements (complete)
        [1-5]) globses; local _gs=$REPLY; sqlmode; REPLY="SET @@${_gs}.SQL_MODE=(SELECT CONCAT(@@SQL_MODE,',${REPLY}'))";;
        [6-9]) globses; local _gs=$REPLY; sqlmode; REPLY="SET @@${_gs}.SQL_MODE=(SELECT REPLACE(@@SQL_MODE,',${REPLY}',''))";;
       1[0-4]) setvars; local _sv=$REPLY; setval; local _val=$REPLY; local _str="SET @@SESSION.${_sv}"; REPLY="${_str/DUMMY/$_val}";;
       1[5-9]) setvarg; local _sg=$REPLY; setval; local _val=$REPLY; local _str="SET @@GLOBAL.${_sg}"; REPLY="${_str/DUMMY/$_val}";;
       2[0-4]) setvars; local _sv=$REPLY; n100; local _val=$REPLY; local _str="SET @@SESSION.${_sv}"; REPLY="${_str/DUMMY/$_val}";;
       2[5-9]) setvarg; local _sg=$REPLY; n100; local _val=$REPLY; local _str="SET @@GLOBAL.${_sg}"; REPLY="${_str/DUMMY/$_val}";;
       3[0-4]) globses; local _gs=$REPLY; optsw; local _os=$REPLY; onoff; REPLY="SET @@${_gs}.OPTIMIZER_SWITCH=\"${_os}=${REPLY}\"";;
       35) case $(($RANDOM % 1 + 1)) in  # Charset/collation related SET statements
             1) globses; local _gs=$REPLY; charcol; REPLY="SET @@${_gs}.${REPLY}";;
             2) globses; local _gs=$REPLY; lctimename; REPLY="SET @@${_gs}.lc_time_names=${REPLY}";;
             *) REPLY="Assert: invalid random case selection in generic statements case (charset/collation section)";;
           esac;;
       3[6-7]) case $(($RANDOM % 5 + 1)) in
             1) engine; REPLY="SET @@GLOBAL.default_storage_engine=${REPLY}";;
             2) n9; REPLY="SET @@GLOBAL.server_id=${REPLY}";;
             3) globses; REPLY="SET @@${REPLY}.tx_read_only=0";;
             4) REPLY="SET @@GLOBAL.read_only=0";;
             5) REPLY="SET @@GLOBAL.super_read_only=0";;
             *) REPLY="Assert: invalid random case selection in generic statements case (commonly needed statements section)";;
           esac;;
        *) REPLY="Assert: invalid random case selection in generic statements case";;
      esac;;
    20) case $(($RANDOM % 16 + 1)) in  # Alter (significantly expanded for MariaDB)
        1) table; local _tbl=$REPLY; ctype; local _ct=$REPLY; colnull; local _cn=$REPLY; coldefault; REPLY="ALTER TABLE ${_tbl} ADD COLUMN c4 ${_ct} ${_cn} ${REPLY}";;
        2) table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} DROP COLUMN c${REPLY}";;
        3) table; local _tbl=$REPLY; engine; REPLY="ALTER TABLE ${_tbl} ENGINE=${REPLY}";;
        4) table; REPLY="ALTER TABLE ${REPLY} DROP PRIMARY KEY";;
        5) table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} ADD INDEX (c${REPLY})";;
        6) table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} ADD UNIQUE (c${REPLY})";;
        7) table; local _tbl=$REPLY; n3; local _n=$REPLY; REPLY="ALTER TABLE ${_tbl} ADD INDEX (c${_n}), ADD UNIQUE (c${_n})";;
        8) ctype; local C1TYPE=$REPLY
           if [[ "$C1TYPE" =~ (TEXT|CHAR|ENUM|SET) && ! "$C1TYPE" =~ (CHARACTER\ SET|COLLATE) ]]; then
             table; local _tbl=$REPLY; n3; local _n=$REPLY; bincharco; REPLY="ALTER TABLE ${_tbl} MODIFY c${_n} ${C1TYPE} ${REPLY}"
           else
             table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} MODIFY c${REPLY} ${C1TYPE}"
           fi;;
        9) table; local _tbl=$REPLY; n3; local _n=$REPLY; ctype; REPLY="ALTER TABLE ${_tbl} MODIFY c${_n} ${REPLY}";;
       10) table; local _tbl=$REPLY; n3; local _n=$REPLY; ctype; local _ct=$REPLY; colnull; local _cn=$REPLY; coldefault; REPLY="ALTER TABLE ${_tbl} CHANGE c${_n} c${_n} ${_ct} ${_cn} ${REPLY}";;
       11) table; local _tbl=$REPLY; algolock; local _al=$REPLY; n3; local _n=$REPLY; ctype; REPLY="ALTER TABLE ${_tbl} ${_al} MODIFY c${_n} ${REPLY}";;
       12) table; local _tbl=$REPLY; rowformat; REPLY="ALTER TABLE ${_tbl} ${REPLY}";;
       13) table; local _tbl=$REPLY; n3; local _c=$REPLY; REPLY="ALTER TABLE ${_tbl} ADD FULLTEXT INDEX (c${_c})";;
       14) table; local _tbl=$REPLY; n3; local _c=$REPLY; REPLY="ALTER TABLE ${_tbl} DROP INDEX idx1, ADD INDEX idx1 (c${_c})";;
       15) table; local _tbl=$REPLY; n3; local _c=$REPLY; emascdesc; REPLY="ALTER TABLE ${_tbl} ORDER BY c${_c} ${REPLY}";;
       16) table; local _tbl=$REPLY; algolock; local _al=$REPLY; ctype; local _ct=$REPLY; colnull; local _cn=$REPLY; coldefault; local _cd=$REPLY; engine; REPLY="ALTER TABLE ${_tbl} ${_al}, ADD COLUMN c5 ${_ct} ${_cn} ${_cd}, ENGINE=${REPLY}";;
        *) REPLY="Assert: invalid random case selection in ALTER case";;
       esac;;
    21) case $(($RANDOM % 42 + 1)) in  # SHOW
        1) REPLY="SHOW BINARY LOGS";;
        2) REPLY="SHOW MASTER LOGS";;
        3) like; REPLY="SHOW CHARACTER SET ${REPLY}";;
        4) like; REPLY="SHOW COLLATION ${REPLY}";;
        5) full; local _f=$REPLY; table; local _tbl=$REPLY; fromdb; local _fd=$REPLY; like; REPLY="SHOW ${_f} COLUMNS FROM ${_tbl} ${_fd} ${REPLY}";;
        6) REPLY="SHOW CREATE DATABASE test";;
        7) event; REPLY="SHOW CREATE EVENT ${REPLY}";;
        8) func; REPLY="SHOW CREATE FUNCTION ${REPLY}";;
        9) proc; REPLY="SHOW CREATE PROCEDURE ${REPLY}";;
       10) table; REPLY="SHOW CREATE TABLE ${REPLY}";;
       11) trigger; REPLY="SHOW CREATE TRIGGER ${REPLY}";;
       12) view; REPLY="SHOW CREATE VIEW ${REPLY}";;
       13) like; REPLY="SHOW DATABASES ${REPLY}";;
       14) engine; REPLY="SHOW ENGINE ${REPLY} STATUS";;
       15) engine; REPLY="SHOW ENGINE ${REPLY} MUTEX";;
       16) REPLY="SHOW ENGINES";;
       17) REPLY="SHOW STORAGE ENGINES";;
       18) ofslimit; REPLY="SHOW ERRORS ${REPLY}";;
       19) REPLY="SHOW EVENTS";;
       20) func; REPLY="SHOW FUNCTION CODE ${REPLY}";;
       21) like; REPLY="SHOW FUNCTION STATUS ${REPLY}";;
       22) user; REPLY="SHOW GRANTS FOR ${REPLY}";;
       23) table; local _tbl=$REPLY; fromdb; REPLY="SHOW INDEX FROM ${_tbl} ${REPLY}";;
       24) REPLY="SHOW MASTER STATUS";;
       25) fromdb; local _fd=$REPLY; like; REPLY="SHOW OPEN TABLES ${_fd} ${REPLY}";;
       26) REPLY="SHOW PLUGINS";;
       27) proc; REPLY="SHOW PROCEDURE CODE ${REPLY}";;
       28) like; REPLY="SHOW PROCEDURE STATUS ${REPLY}";;
       29) REPLY="SHOW PRIVILEGES";;
       30) full; REPLY="SHOW ${REPLY} PROCESSLIST";;
       31) proftype; local _pt=$REPLY; forquery; local _fq=$REPLY; offset; local _of=$REPLY; limit; REPLY="SHOW PROFILE ${_pt} ${_fq} ${_of} ${REPLY}";;
       32) REPLY="SHOW PROFILES";;
       33) REPLY="SHOW SLAVE HOSTS";;
       34) REPLY="SHOW SLAVE STATUS";;
       35) data; local _d=$REPLY; local _str="SHOW SLAVE STATUS FOR CHANNEL '${_d}'"; REPLY="${_str//\'\'/\'}";;
       36) globses; local _gs=$REPLY; like; REPLY="SHOW ${_gs} STATUS ${REPLY}";;
       37) fromdb; local _fd=$REPLY; like; REPLY="SHOW TABLE STATUS ${_fd} ${REPLY}";;
       38) REPLY="SHOW TABLES";;
       39) full; local _f=$REPLY; fromdb; local _fd=$REPLY; like; REPLY="SHOW ${_f} TABLES ${_fd} ${REPLY}";;
       40) fromdb; local _fd=$REPLY; like; REPLY="SHOW TRIGGERS ${_fd} ${REPLY}";;
       41) globses; local _gs=$REPLY; like; REPLY="SHOW ${_gs} VARIABLES ${REPLY}";;
       42) ofslimit; REPLY="SHOW WARNINGS ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in SHOW case";;
       esac;;
    22) case $(($RANDOM % 4 + 1)) in  # InnoDB monitor (complete)
        1) inmetrics; REPLY="SET GLOBAL innodb_monitor_enable='${REPLY}'";;
        2) inmetrics; REPLY="SET GLOBAL innodb_monitor_reset='${REPLY}'";;
        3) inmetrics; REPLY="SET GLOBAL innodb_monitor_reset_all='${REPLY}'";;
        4) inmetrics; REPLY="SET GLOBAL innodb_monitor_disable='${REPLY}'";;
        *) REPLY="Assert: invalid random case selection in InnoDB metrics case";;
      esac;;
    23) case $(($RANDOM % 7 + 1)) in  # Nested query calls
        1) query; REPLY="EXPLAIN ${REPLY}";;
        2) allor1; local _ao=$REPLY; query; REPLY="SELECT ${_ao} FROM (${REPLY}) AS a1";;
    [3-7]) case $(($RANDOM % 8 + 1)) in  # Prepared statements
       [1-3]) query; REPLY="SET @cmd:=\"${REPLY}\"";;
       [4-5]) REPLY="PREPARE stmt FROM @cmd";;
       [6-7]) REPLY="EXECUTE stmt";;
           8) REPLY="DEALLOCATE PREPARE stmt";;
           *) REPLY="Assert: invalid random case selection in prepared statements case";;
          esac;;
        *) REPLY="Assert: invalid random case selection in nested query calls case";;
      esac;;
2[4-8]) case $(($RANDOM % 24 + 1)) in  # XA (complete)
    [1-9]) xid; local _xid=$REPLY; onephase; REPLY="XA COMMIT ${_xid} ${REPLY}";;
       10) case $(($RANDOM % 2 + 1)) in
           1) xid; REPLY="XA START ${REPLY}";;
           2) xid; REPLY="XA BEGIN ${REPLY}";;
         esac;;
   1[1-8]) xid; REPLY="XA END ${REPLY}";;
       19) xid; REPLY="XA PREPARE ${REPLY}";;
       20) convertxid; REPLY="XA RECOVER ${REPLY}";;
   2[1-4]) xid; REPLY="XA ROLLBACK ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in XA case";;
      esac;;
    29) case $(($RANDOM % 5 + 1)) in  # Repair/optimize/analyze/rename/truncate table (complete)
        1) nowblocal; local _nb=$REPLY; table; local _t=$REPLY; quick; local _q=$REPLY; extended; local _e=$REPLY; usefrm; REPLY="REPAIR ${_nb} TABLE ${_t} ${_q} ${_e} ${REPLY}";;
        2) nowblocal; local _nb=$REPLY; table; REPLY="OPTIMIZE ${_nb} TABLE ${REPLY}";;
        3) nowblocal; local _nb=$REPLY; table; REPLY="ANALYZE ${_nb} TABLE ${REPLY}";;
        4) case $(($RANDOM % 3 + 1)) in
           1) table; local _t1=$REPLY; table; REPLY="RENAME TABLE ${_t1} TO ${REPLY}";;
           2) table; local _t1=$REPLY; table; local _t2=$REPLY; table; local _t3=$REPLY; table; REPLY="RENAME TABLE ${_t1} TO ${_t2},${_t3} TO ${REPLY}";;
           3) table; local _t1=$REPLY; table; local _t2=$REPLY; table; local _t3=$REPLY; table; local _t4=$REPLY; table; local _t5=$REPLY; table; REPLY="RENAME TABLE ${_t1} TO ${_t2},${_t3} TO ${_t4},${_t5} TO ${REPLY}";;
           *) REPLY="Assert: invalid random case selection in rename table case";;
           esac;;
        5) table; REPLY="TRUNCATE TABLE ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in repair/optimize/analyze/rename/truncate table case";;
      esac;;
3[0-1]) case $(($RANDOM % 7 + 1)) in  # Transactions (complete)
        1) trxopt; REPLY="START TRANSACTION ${REPLY}";;
        2) work; REPLY="BEGIN ${REPLY}";;
    [3-4]) work; local _w=$REPLY; chain; local _c=$REPLY; release; REPLY="COMMIT ${_w} ${_c} ${REPLY}";;
    [5-6]) work; local _w=$REPLY; chain; local _c=$REPLY; release; REPLY="ROLLBACK ${_w} ${_c} ${REPLY}";;
        7) onoff01; REPLY="SET autocommit=${REPLY}";;
        *) REPLY="Assert: invalid random case selection in transactions case";;
      esac;;
    32) case $(($RANDOM % 19 + 1)) in  # Lock tables (complete)
    [1-9]) REPLY="UNLOCK TABLES";;
       10) table; local _t=$REPLY; asalias3; local _a=$REPLY; locktype; REPLY="LOCK TABLES ${_t} ${_a} ${REPLY}";;
   1[1-4]) table; local _t1=$REPLY; asalias3; local _a1=$REPLY; locktype; local _l1=$REPLY; table; local _t2=$REPLY; n9; local _n=$REPLY; locktype; REPLY="LOCK TABLES ${_t1} ${_a1} ${_l1}, ${_t2} AS a${_n} ${REPLY}";;
   1[5-9]) table; local _t1=$REPLY; asalias3; local _a1=$REPLY; locktype; local _l1=$REPLY; table; local _t2=$REPLY; n9; local _n1=$REPLY; locktype; local _l2=$REPLY; table; local _t3=$REPLY; n9; local _n2=$REPLY; locktype; REPLY="LOCK TABLES ${_t1} ${_a1} ${_l1}, ${_t2} AS a${_n1} ${_l2}, ${_t3} AS a${_n2} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in lock case";;
      esac;;
    33) case $(($RANDOM % 3 + 1)) in  # Savepoints (complete)
        1) n2; REPLY="SAVEPOINT sp${REPLY}";;
        2) work; local _w=$REPLY; savepoint; local _s=$REPLY; n2; REPLY="ROLLBACK ${_w} TO ${_s} sp${REPLY}";;
        3) n2; REPLY="RELEASE SAVEPOINT sp${REPLY}";;
        *) REPLY="Assert: invalid random case selection in savepoint case";;
      esac;;
3[4-5]) case $(($RANDOM % 13 + 1)) in  # P_S (in progress)
    [1-2]) case $(($RANDOM % 5 + 1)) in  # Enabling and truncating
          1) REPLY="UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', TIMED = 'YES'";;
          2) REPLY="UPDATE performance_schema.setup_consumers SET ENABLED = 'YES'";;
          3) REPLY="UPDATE performance_schema.setup_objects SET ENABLED = 'YES', TIMED = 'YES'";;
          4) pstimernm; local _ptnm=$REPLY; pstimer; REPLY="UPDATE performance_schema.setup_timers SET TIMER_NAME='${_ptnm}' WHERE NAME='${REPLY}'";;
          5) pstable; PSTBL=$REPLY; if ! [[ "${PSTBL}" == *"setup"* ]]; then REPLY="TRUNCATE TABLE performance_schema.${PSTBL}"; else query; fi;;
          *) REPLY="Assert: invalid random case selection in P_S enabling subcase";;
          esac;;
    [3-9]) pstable; REPLY="SELECT * FROM performance_schema.${REPLY}";;
   1[0-3]) case $(($RANDOM % 10 + 1)) in  # Special setup for stress testing PXC 5.7
          1) REPLY="UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', TIMED = 'YES' WHERE NAME LIKE '%wsrep%'";;
          2) REPLY="UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', TIMED = 'YES' WHERE NAME LIKE '%galera%'";;
          3) REPLY="SELECT EVENT_ID, EVENT_NAME, TIMER_WAIT FROM performance_schema.events_waits_history WHERE EVENT_NAME LIKE '%galera%'";;
          4) REPLY="SELECT EVENT_ID, EVENT_NAME, TIMER_WAIT FROM performance_schema.events_waits_history WHERE EVENT_NAME LIKE '%wsrep%'";;
          5) REPLY="SELECT EVENT_NAME, COUNT_STAR FROM performance_schema.events_waits_summary_global_by_event_name WHERE EVENT_NAME LIKE '%wsrep%'";;
          6) REPLY="SELECT EVENT_NAME, COUNT_STAR FROM performance_schema.events_waits_summary_global_by_event_name WHERE EVENT_NAME LIKE '%galera%'";;
          7) REPLY="SELECT * FROM performance_schema.file_instances WHERE FILE_NAME LIKE '%galera%'";;
          8) REPLY="SELECT * FROM performance_schema.events_stages_history WHERE EVENT_NAME LIKE '%wsrep%'";;
          9) REPLY="SELECT EVENT_ID, EVENT_NAME, TIMER_WAIT FROM performance_schema.events_waits_history WHERE EVENT_NAME LIKE '%galera%'";;
         10) REPLY="SELECT EVENT_ID, EVENT_NAME, TIMER_WAIT FROM performance_schema.events_waits_history WHERE EVENT_NAME LIKE '%wsrep%'";;
          *) REPLY="Assert: invalid random case selection in P_S PXC specific subcase";;
          esac;;
        *) REPLY="Assert: invalid random case selection in P_S case";;
      esac;;
3[6-7]) case $(($RANDOM % 7 + 1)) in  # Calling & setup of functions and procedures (complete)
      [1-2]) ac; local _ac=$REPLY; data; REPLY="SET @${_ac}=${REPLY}";;
          3) proc; local _pr=$REPLY; ac; REPLY="CALL ${_pr}(@${REPLY})";;
          4) proc; local _pr=$REPLY; ac; local _ac1=$REPLY; ac; REPLY="CALL ${_pr}(@${_ac1},@${REPLY})";;
          5) case $(($RANDOM % 2 + 1)) in
              1) ac; REPLY="SELECT @${REPLY}";;
              2) REPLY="SELECT ROW_COUNT();";;
              *) REPLY="Assert: invalid random case selection in func,proc SELECT subcase";;
          esac;;
          6) case $(($RANDOM % 2 + 1)) in
              1) func; local _fn=$REPLY; ac; REPLY="SELECT ${_fn}(@${REPLY})";;
              2) func; local _fn=$REPLY; data; REPLY="SELECT ${_fn}(${REPLY})";;
              *) REPLY="Assert: invalid random case selection in function-with-var subcase";;
          esac;;
          7) case $(($RANDOM % 4 + 1)) in
              1) func; local _fn=$REPLY; ac; local _ac=$REPLY; data; REPLY="SELECT ${_fn}(@${_ac},${REPLY})";;
              2) func; local _fn=$REPLY; data; local _d1=$REPLY; data; REPLY="SELECT ${_fn}(${_d1},${REPLY})";;
              3) func; local _fn=$REPLY; data; local _d=$REPLY; ac; REPLY="SELECT ${_fn}(${_d},@${REPLY})";;
              4) func; local _fn=$REPLY; ac; local _ac1=$REPLY; ac; REPLY="SELECT ${_fn}(@${_ac1},@${REPLY})";;
              *) REPLY="Assert: invalid random case selection in function-with-var subcase";;
          esac;;
          *) REPLY="Assert: invalid random case selection in func,proc case";;
        esac;;
3[8-9]) case $(($RANDOM % 4 + 1)) in  # Numeric functions
         1) fullnrfunc; REPLY="SELECT ${REPLY}";;
         2) fullnrfunc; local _f1=$REPLY; numsimple; local _ns=$REPLY; fullnrfunc; REPLY="SELECT (${_f1}) ${_ns} (${REPLY})";;
         3) fullnrfunc; local _f1=$REPLY; numsimple; local _ns1=$REPLY; fullnrfunc; local _f2=$REPLY; numsimple; local _ns2=$REPLY; fullnrfunc; REPLY="SELECT (${_f1}) ${_ns1} (${_f2}) ${_ns2} (${REPLY})";;
         4) fullnrfunc; local _f1=$REPLY; numsimple; local _ns1=$REPLY; fullnrfunc; local _f2=$REPLY; numsimple; local _ns2=$REPLY; fullnrfunc; local _f3=$REPLY; numsimple; local _ns3=$REPLY; fullnrfunc; REPLY="SELECT (${_f1}) ${_ns1} (${_f2}) ${_ns2} (${_f3}) ${_ns3} (${REPLY})";;
         *) REPLY="Assert: invalid random case selection in numeric functions case";;
       esac;;

    40) case $(($RANDOM % 3 + 1)) in  # REPLACE
        1) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY
           REPLY="REPLACE INTO ${_tbl} VALUES (${_d1},${_d2},${_d3})";;
        2) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY
           REPLY="REPLACE INTO ${_tbl1} SELECT * FROM ${_tbl2}";;
        3) lowprio; local _lp=$REPLY; table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY
           REPLY="REPLACE ${_lp} INTO ${_tbl} (c1,c2,c3) VALUES (${_d1},${_d2},${_d3})";;
        *) REPLY="Assert: invalid random case selection in REPLACE case";;
      esac;;
    41) case $(($RANDOM % 5 + 1)) in  # INSERT variants (ON DUPLICATE KEY, IGNORE, multi-row)
        1) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY; n3; local _n=$REPLY; data; local _d4=$REPLY
           REPLY="INSERT INTO ${_tbl} VALUES (${_d1},${_d2},${_d3}) ON DUPLICATE KEY UPDATE c${_n}=${_d4}";;
        2) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY; n3; local _n1=$REPLY; n3; local _n2=$REPLY
           REPLY="INSERT INTO ${_tbl} VALUES (${_d1},${_d2},${_d3}) ON DUPLICATE KEY UPDATE c${_n1}=VALUES(c${_n2})";;
        3) ignore; local _ig=$REPLY; table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY
           REPLY="INSERT ${_ig} INTO ${_tbl} VALUES (${_d1},${_d2},${_d3})";;
        4) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY; n3; local _n=$REPLY; data; local _d=$REPLY
           REPLY="INSERT INTO ${_tbl1} (c1,c2,c3) SELECT c1,c2,c3 FROM ${_tbl2} ON DUPLICATE KEY UPDATE c${_n}=${_d}";;
        5) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY; data; local _d4=$REPLY; data; local _d5=$REPLY; data; local _d6=$REPLY
           REPLY="INSERT INTO ${_tbl} VALUES (${_d1},${_d2},${_d3}),(${_d4},${_d5},${_d6})";;
        *) REPLY="Assert: invalid random case selection in INSERT variants case";;
      esac;;
    42) case $(($RANDOM % 4 + 1)) in  # Window function SELECTs part 1
        1) n3; local _n=$REPLY; winfuncname; local _wf=$REPLY; winover; local _wo=$REPLY; table
           REPLY="SELECT c${_n}, ${_wf} ${_wo} FROM ${REPLY}";;
        2) n3; local _n=$REPLY; winfuncname; local _wf=$REPLY; winover; local _wo=$REPLY; table; local _tbl=$REPLY; where
           REPLY="SELECT c${_n}, ${_wf} ${_wo} FROM ${_tbl} ${REPLY}";;
        3) n3; local _n=$REPLY; winfuncname; local _wf1=$REPLY; winover; local _wo1=$REPLY; winfuncname; local _wf2=$REPLY; winover; local _wo2=$REPLY; table
           REPLY="SELECT c${_n}, ${_wf1} ${_wo1}, ${_wf2} ${_wo2} FROM ${REPLY}";;
        4) winfuncname; local _wf=$REPLY; winover; local _wo=$REPLY; table; local _tbl1=$REPLY; join; local _jn=$REPLY; table; local _tbl2=$REPLY; whereal
           REPLY="SELECT *, ${_wf} ${_wo} FROM ${_tbl1} AS a1 ${_jn} ${_tbl2} AS a2 ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in window function SELECTs part 1 case";;
      esac;;
    43) case $(($RANDOM % 3 + 1)) in  # Window function SELECTs part 2
        1) n3; local _n1=$REPLY; winfuncname; local _wf=$REPLY; n3; local _n2=$REPLY; emascdesc; local _ad=$REPLY; table
           REPLY="SELECT c${_n1}, ${_wf} OVER w FROM ${REPLY} WINDOW w AS (ORDER BY c${_n2} ${_ad})";;
        2) n3; local _n1=$REPLY; n3; local _n2=$REPLY; winover; local _wo1=$REPLY; winover; local _wo2=$REPLY; table; local _tbl=$REPLY; groupby
           REPLY="SELECT c${_n1}, SUM(c${_n2}) ${_wo1}, COUNT(*) ${_wo2} FROM ${_tbl} ${REPLY}";;
        3) n3; local _n=$REPLY; winfuncname; local _wf=$REPLY; winover; local _wo=$REPLY; selectq
           REPLY="SELECT c${_n}, ${_wf} ${_wo} FROM (${REPLY}) AS a1";;
        *) REPLY="Assert: invalid random case selection in window function SELECTs part 2 case";;
      esac;;
    44) case $(($RANDOM % 4 + 1)) in  # CTEs (Common Table Expressions)
        1) selectq; REPLY="WITH cte AS (${REPLY}) SELECT * FROM cte";;
        2) selectq; local _sq=$REPLY; where; local _wh=$REPLY; orderby; local _ob=$REPLY; limit
           REPLY="WITH cte AS (${_sq}) SELECT * FROM cte ${_wh} ${_ob} ${REPLY}";;
        3) n100; REPLY="WITH RECURSIVE cte AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM cte WHERE n < ${REPLY}) SELECT * FROM cte";;
        4) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY; n3; local _n1=$REPLY; n3; local _n2=$REPLY; join
           REPLY="WITH cte1 AS (SELECT * FROM ${_tbl1}), cte2 AS (SELECT * FROM ${_tbl2}) SELECT * FROM cte1 ${REPLY} cte2 ON cte1.c${_n1} = cte2.c${_n2}";;
        *) REPLY="Assert: invalid random case selection in CTEs case";;
      esac;;
    45) case $(($RANDOM % 5 + 1)) in  # CREATE/DROP VIEW
        1) orreplace; local _or=$REPLY; view; local _vw=$REPLY; selectq; REPLY="CREATE ${_or} VIEW ${_vw} AS ${REPLY}";;
        2) orreplace; local _or=$REPLY; view; local _vw=$REPLY; selectq; local _sq=$REPLY; withcheckoption; REPLY="CREATE ${_or} VIEW ${_vw} (c1,c2,c3) AS ${_sq} ${REPLY}";;
        3) orreplace; local _or=$REPLY; view; local _vw=$REPLY; selectq; REPLY="CREATE ${_or} ALGORITHM=MERGE VIEW ${_vw} AS ${REPLY}";;
        4) orreplace; local _or=$REPLY; view; local _vw=$REPLY; selectq; REPLY="CREATE ${_or} ALGORITHM=TEMPTABLE VIEW ${_vw} AS ${REPLY}";;
        5) ifexist; local _ie=$REPLY; view; REPLY="DROP VIEW ${_ie} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in CREATE/DROP VIEW case";;
      esac;;
    46) case $(($RANDOM % 5 + 1)) in  # CREATE/DROP INDEX
        1) idxname; local _idx=$REPLY; table; local _tbl=$REPLY; n3; REPLY="CREATE INDEX ${_idx} ON ${_tbl} (c${REPLY})";;
        2) idxname; local _idx=$REPLY; table; local _tbl=$REPLY; n3; REPLY="CREATE UNIQUE INDEX ${_idx} ON ${_tbl} (c${REPLY})";;
        3) idxname; local _idx=$REPLY; table; local _tbl=$REPLY; n3; local _c1=$REPLY; n3; REPLY="CREATE INDEX ${_idx} ON ${_tbl} (c${_c1},c${REPLY})";;
        4) ifnotexist; local _ine=$REPLY; idxname; local _idx=$REPLY; table; local _tbl=$REPLY; n3; REPLY="CREATE INDEX ${_ine} ${_idx} ON ${_tbl} (c${REPLY})";;
        5) ifexist; local _ie=$REPLY; idxname; local _idx=$REPLY; table; REPLY="DROP INDEX ${_ie} ${_idx} ON ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in CREATE/DROP INDEX case";;
      esac;;
    47) case $(($RANDOM % 6 + 1)) in  # Enhanced SELECT with GROUP BY/HAVING/DISTINCT
        1) distinct; local _d=$REPLY; n3; local _c=$REPLY; table; local _tbl=$REPLY; groupby; local _gb=$REPLY; having; REPLY="SELECT ${_d} c${_c}, COUNT(*) FROM ${_tbl} ${_gb} ${REPLY}";;
        2) n3; local _c1=$REPLY; n3; local _c2=$REPLY; table; local _tbl=$REPLY; n3; local _c3=$REPLY; having; local _hv=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="SELECT c${_c1}, SUM(c${_c2}) FROM ${_tbl} GROUP BY c${_c3} ${_hv} ${_ob} ${REPLY}";;
        3) distinct; local _d=$REPLY; n3; local _c1=$REPLY; n3; local _c2=$REPLY; n3; local _c3=$REPLY; n3; local _c4=$REPLY; table; local _tbl=$REPLY; n3; REPLY="SELECT ${_d} c${_c1}, AVG(c${_c2}), MIN(c${_c3}), MAX(c${_c4}) FROM ${_tbl} GROUP BY c${REPLY}";;
        4) distinct; local _d=$REPLY; table; local _tbl=$REPLY; where; local _wh=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="SELECT ${_d} * FROM ${_tbl} ${_wh} ${_ob} ${REPLY}";;
        5) n3; local _c1=$REPLY; n3; local _c2=$REPLY; table; local _tbl=$REPLY; n3; local _c3=$REPLY; having; REPLY="SELECT c${_c1}, GROUP_CONCAT(c${_c2}) FROM ${_tbl} GROUP BY c${_c3} ${REPLY}";;
        6) n3; local _c1=$REPLY; n3; local _c2=$REPLY; table; local _tbl=$REPLY; n3; local _c3=$REPLY; having; REPLY="SELECT c${_c1}, COUNT(DISTINCT c${_c2}) FROM ${_tbl} GROUP BY c${_c3} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in enhanced SELECT with GROUP BY/HAVING/DISTINCT case";;
      esac;;
    48) case $(($RANDOM % 6 + 1)) in  # HANDLER statements
        1) table; REPLY="HANDLER ${REPLY} OPEN";;
        2) table; REPLY="HANDLER ${REPLY} OPEN AS a1";;
        3) table; local _tbl=$REPLY; where; local _wh=$REPLY; limit; REPLY="HANDLER ${_tbl} READ FIRST ${_wh} ${REPLY}";;
        4) table; local _tbl=$REPLY; where; local _wh=$REPLY; limit; REPLY="HANDLER ${_tbl} READ NEXT ${_wh} ${REPLY}";;
        5) table; local _tbl=$REPLY; data; local _d=$REPLY; where; local _wh=$REPLY; limit; REPLY="HANDLER ${_tbl} READ idx1 = (${_d}) ${_wh} ${REPLY}";;
        6) table; REPLY="HANDLER ${REPLY} CLOSE";;
        *) REPLY="Assert: invalid random case selection in HANDLER case";;
      esac;;
    49) case $(($RANDOM % 5 + 1)) in  # System versioned table queries
        1) table; local _tbl=$REPLY; forsystemtime; REPLY="SELECT * FROM ${_tbl} ${REPLY}";;
        2) n3; local _n=$REPLY; table; local _tbl=$REPLY; forsystemtime; local _fst=$REPLY; where; REPLY="SELECT c${_n} FROM ${_tbl} ${_fst} ${REPLY}";;
        3) table; local _tbl=$REPLY; forsystemtime; local _fst=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="SELECT * FROM ${_tbl} ${_fst} ${_ob} ${REPLY}";;
        4) table; REPLY="SELECT COUNT(*) FROM ${REPLY} FOR SYSTEM_TIME ALL";;
        5) table; REPLY="DELETE HISTORY FROM ${REPLY} BEFORE SYSTEM_TIME '2030-01-01 00:00:00'";;
        *) REPLY="Assert: invalid random case selection in system versioned queries case";;
      esac;;
    50) case $(($RANDOM % 5 + 1)) in  # JSON function SELECTs
        1) jsonfunc; local _jf=$REPLY; table; REPLY="SELECT ${_jf} FROM ${REPLY}";;
        2) jsonfunc; local _jf1=$REPLY; jsonfunc; local _jf2=$REPLY; table; local _tbl=$REPLY; where; REPLY="SELECT ${_jf1}, ${_jf2} FROM ${_tbl} ${REPLY}";;
        3) n3; local _n=$REPLY; table; REPLY="SELECT JSON_VALID(c${_n}) FROM ${REPLY}";;
        4) n3; local _n=$REPLY; table; local _tbl=$REPLY; where; REPLY="SELECT JSON_KEYS(c${_n}) FROM ${_tbl} ${REPLY}";;
        5) n3; local _n=$REPLY; table; REPLY="SELECT JSON_LENGTH(c${_n}) FROM ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in JSON function SELECTs case";;
      esac;;
    51) case $(($RANDOM % 6 + 1)) in  # String/CAST/expression function SELECTs
        1) stringfunc; local _sf=$REPLY; table; REPLY="SELECT ${_sf} FROM ${REPLY}";;
        2) castexpr; local _ce=$REPLY; table; local _tbl=$REPLY; where; REPLY="SELECT ${_ce} FROM ${_tbl} ${REPLY}";;
        3) caseexpr; local _cx=$REPLY; table; REPLY="SELECT ${_cx} FROM ${REPLY}";;
        4) coalesceexpr; local _co=$REPLY; table; local _tbl=$REPLY; where; REPLY="SELECT ${_co} FROM ${_tbl} ${REPLY}";;
        5) stringfunc; local _sf=$REPLY; castexpr; local _ce=$REPLY; table; local _tbl=$REPLY; where; local _wh=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="SELECT ${_sf}, ${_ce} FROM ${_tbl} ${_wh} ${_ob} ${REPLY}";;
        6) caseexpr; local _cx=$REPLY; coalesceexpr; local _co=$REPLY; table; REPLY="SELECT ${_cx}, ${_co} FROM ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in string/CAST/expression function SELECTs case";;
      esac;;
    52) case $(($RANDOM % 8 + 1)) in  # GRANT/REVOKE/User management
        1) ifnotexist; local _ine=$REPLY; user; local _u=$REPLY; data; REPLY="CREATE USER ${_ine} ${_u} IDENTIFIED BY ${REPLY}";;
        2) ifexist; local _ie=$REPLY; user; REPLY="DROP USER ${_ie} ${REPLY}";;
        3) user; REPLY="GRANT ALL ON *.* TO ${REPLY}";;
        4) user; REPLY="GRANT SELECT, INSERT ON test.* TO ${REPLY}";;
        5) table; local _tbl=$REPLY; user; REPLY="GRANT SELECT ON test.${_tbl} TO ${REPLY}";;
        6) user; REPLY="REVOKE ALL PRIVILEGES ON *.* FROM ${REPLY}";;
        7) user; local _u=$REPLY; data; REPLY="ALTER USER ${_u} IDENTIFIED BY ${REPLY}";;
        8) user; local _u=$REPLY; data; REPLY="SET PASSWORD FOR ${_u} = PASSWORD(${REPLY})";;
        *) REPLY="Assert: invalid random case selection in GRANT/REVOKE/user management case";;
      esac;;
    53) case $(($RANDOM % 7 + 1)) in  # CHECK TABLE / CHECKSUM TABLE / DO
        1) table; REPLY="CHECK TABLE ${REPLY} QUICK";;
        2) table; REPLY="CHECK TABLE ${REPLY} EXTENDED";;
        3) table; REPLY="CHECKSUM TABLE ${REPLY} QUICK";;
        4) table; REPLY="CHECKSUM TABLE ${REPLY} EXTENDED";;
        5) REPLY="DO SLEEP(0)";;
        6) REPLY="DO RELEASE_LOCK('lock1')";;
        7) n100; local _n1=$REPLY; n100; REPLY="DO ${_n1} + ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in CHECK/CHECKSUM/DO case";;
      esac;;
    54) case $(($RANDOM % 8 + 1)) in  # INFORMATION_SCHEMA queries
        1) limit; REPLY="SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='test' ${REPLY}";;
        2) limit; REPLY="SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='test' ${REPLY}";;
        3) REPLY="SELECT * FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA='test'";;
        4) REPLY="SELECT * FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='test'";;
        5) REPLY="SELECT * FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='test'";;
        6) REPLY="SELECT * FROM INFORMATION_SCHEMA.PROCESSLIST";;
        7) like; REPLY="SELECT * FROM INFORMATION_SCHEMA.GLOBAL_STATUS ${REPLY}";;
        8) like; REPLY="SELECT * FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in INFORMATION_SCHEMA case";;
      esac;;
    55) case $(($RANDOM % 10 + 1)) in  # Enhanced ALTER TABLE
        1) table; local _tbl1=$REPLY; table; REPLY="ALTER TABLE ${_tbl1} RENAME TO ${REPLY}";;
        2) table; REPLY="ALTER TABLE ${REPLY} CONVERT TO CHARACTER SET utf8";;
        3) table; local _tbl1=$REPLY; n3; local _n=$REPLY; table; REPLY="ALTER TABLE ${_tbl1} ADD FOREIGN KEY (c${_n}) REFERENCES ${REPLY}(c1)";;
        4) table; local _tbl=$REPLY; n3; local _n=$REPLY; data; REPLY="ALTER TABLE ${_tbl} ALTER COLUMN c${_n} SET DEFAULT ${REPLY}";;
        5) table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} ALTER COLUMN c${REPLY} DROP DEFAULT";;
        6) table; local _tbl=$REPLY; n3; REPLY="ALTER TABLE ${_tbl} ORDER BY c${REPLY}";;
        7) table; REPLY="ALTER TABLE ${REPLY} FORCE";;
        8) table; REPLY="ALTER TABLE ${REPLY} ADD SYSTEM VERSIONING";;
        9) table; REPLY="ALTER TABLE ${REPLY} DROP SYSTEM VERSIONING";;
       10) table; local _tbl=$REPLY; algolock; local _al=$REPLY; ctype; REPLY="ALTER TABLE ${_tbl} ${_al}, ADD COLUMN c4 ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in enhanced ALTER TABLE case";;
      esac;;
    56) case $(($RANDOM % 4 + 1)) in  # CREATE/DROP TRIGGER
        1) orreplace; local _or=$REPLY; trigger; local _tr=$REPLY; beforeafter; local _ba=$REPLY; triggerop; local _top=$REPLY; table; REPLY="CREATE ${_or} TRIGGER ${_tr} ${_ba} ${_top} ON ${REPLY} FOR EACH ROW SET @a=1";;
        2) orreplace; local _or=$REPLY; definer; local _def=$REPLY; trigger; local _tr=$REPLY; beforeafter; local _ba=$REPLY; triggerop; local _top=$REPLY; table; local _tbl=$REPLY; query; REPLY="CREATE ${_or} ${_def} TRIGGER ${_tr} ${_ba} ${_top} ON ${_tbl} FOR EACH ROW ${REPLY}";;
        3) ifexist; local _ie=$REPLY; trigger; REPLY="DROP TRIGGER ${_ie} ${REPLY}";;
        4) orreplace; local _or=$REPLY; trigger; local _tr=$REPLY; beforeafter; local _ba=$REPLY; triggerop; local _top=$REPLY; table; local _tbl1=$REPLY; table; REPLY="CREATE ${_or} TRIGGER ${_tr} ${_ba} ${_top} ON ${_tbl1} FOR EACH ROW INSERT INTO ${REPLY} VALUES (NEW.c1, NEW.c2, NEW.c3)";;
        *) REPLY="Assert: invalid random case selection in CREATE/DROP TRIGGER case";;
      esac;;
    57) case $(($RANDOM % 3 + 1)) in  # Multi-table UPDATE
        1) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c1=$REPLY; n3; local _c2=$REPLY; n3; local _c3=$REPLY; data
           REPLY="UPDATE ${_t1} AS a1 JOIN ${_t2} AS a2 ON a1.c${_c1}=a2.c${_c2} SET a1.c${_c3}=${REPLY}";;
        2) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c1=$REPLY; n3; local _c2=$REPLY; n3; local _c3=$REPLY; n3
           REPLY="UPDATE ${_t1} AS a1, ${_t2} AS a2 SET a1.c${_c1}=a2.c${_c2} WHERE a1.c${_c3}=a2.c${REPLY}";;
        3) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c1=$REPLY; n3; local _c2=$REPLY; n3; local _c3=$REPLY; data; local _d=$REPLY; limit
           REPLY="UPDATE ${_t1} AS a1 LEFT JOIN ${_t2} AS a2 ON a1.c${_c1}=a2.c${_c2} SET a1.c${_c3}=${_d} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in multi-table UPDATE case";;
      esac;;
    58) case $(($RANDOM % 5 + 1)) in  # SELECT ... FOR UPDATE / locking
        1) table; local _t=$REPLY; forupdate; REPLY="SELECT * FROM ${_t} ${REPLY}";;
        2) n3; local _c1=$REPLY; table; local _t=$REPLY; n3; local _c2=$REPLY; operator; local _op=$REPLY; data; REPLY="SELECT c${_c1} FROM ${_t} WHERE c${_c2} ${_op} ${REPLY} FOR UPDATE";;
        3) table; local _t=$REPLY; where; REPLY="SELECT * FROM ${_t} ${REPLY} LOCK IN SHARE MODE";;
        4) table; local _t=$REPLY; where; REPLY="SELECT * FROM ${_t} ${REPLY} FOR UPDATE NOWAIT";;
        5) table; local _t=$REPLY; where; REPLY="SELECT * FROM ${_t} ${REPLY} FOR UPDATE SKIP LOCKED";;
        *) REPLY="Assert: invalid random case selection in SELECT FOR UPDATE case";;
      esac;;
    59) case $(($RANDOM % 6 + 1)) in  # Sequence operations
        1) orreplace; local _or=$REPLY; seqname; local _s=$REPLY; n100; local _n1=$REPLY; n10; REPLY="CREATE ${_or} SEQUENCE ${_s} START WITH ${_n1} INCREMENT BY ${REPLY}";;
        2) orreplace; local _or=$REPLY; seqname; local _s=$REPLY; n1000; REPLY="CREATE ${_or} SEQUENCE ${_s} START WITH 1 MINVALUE 1 MAXVALUE ${REPLY} CYCLE";;
        3) seqname; REPLY="SELECT NEXT VALUE FOR ${REPLY}";;
        4) seqname; REPLY="SELECT NEXTVAL(${REPLY})";;
        5) seqname; REPLY="ALTER SEQUENCE ${REPLY} RESTART";;
        6) ifexist; local _ie=$REPLY; seqname; REPLY="DROP SEQUENCE ${_ie} ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in sequence operations case";;
      esac;;
    60) case $(($RANDOM % 4 + 1)) in  # INSERT/DELETE ... RETURNING (MariaDB 10.5+)
        1) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY; returning
           REPLY="INSERT INTO ${_tbl} VALUES (${_d1},${_d2},${_d3}) ${REPLY}";;
        2) table; local _tbl1=$REPLY; table; local _tbl2=$REPLY; returning
           REPLY="INSERT INTO ${_tbl1} SELECT * FROM ${_tbl2} LIMIT 1 ${REPLY}";;
        3) table; local _tbl=$REPLY; where; local _wh=$REPLY; limit; local _lm=$REPLY; returning
           REPLY="DELETE FROM ${_tbl} ${_wh} ${_lm} ${REPLY}";;
        4) table; local _tbl=$REPLY; data; local _d1=$REPLY; data; local _d2=$REPLY; data; local _d3=$REPLY; returning
           REPLY="REPLACE INTO ${_tbl} VALUES (${_d1},${_d2},${_d3}) ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in INSERT/DELETE RETURNING case";;
      esac;;
    61) case $(($RANDOM % 8 + 1)) in  # SET NAMES / DESCRIBE / USE / KILL
        1) REPLY="SET NAMES utf8";;
        2) REPLY="SET NAMES latin1";;
        3) REPLY="SET NAMES binary";;
        4) REPLY="SET CHARACTER SET utf8";;
        5) table; REPLY="DESCRIBE ${REPLY}";;
        6) table; REPLY="DESC ${REPLY}";;
        7) REPLY="USE test";;
        8) n100; REPLY="KILL QUERY ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in SET NAMES/DESCRIBE/USE/KILL case";;
      esac;;
    62) case $(($RANDOM % 4 + 1)) in  # INTERSECT / EXCEPT (MariaDB 10.3+)
        1) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} INTERSECT ${REPLY}";;
        2) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} EXCEPT ${REPLY}";;
        3) selectq; local _sq1=$REPLY; selectq; local _sq2=$REPLY; selectq; REPLY="${_sq1} UNION ${_sq2} INTERSECT ${REPLY}";;
        4) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} INTERSECT ALL ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in INTERSECT/EXCEPT case";;
      esac;;

    63) case $(($RANDOM % 6 + 1)) in  # INSTALL/UNINSTALL SONAME (plugin management)
    [1-4]) installsoname;;
    [5-6]) uninstallsoname;;
        *) REPLY="Assert: invalid random case selection in INSTALL/UNINSTALL SONAME case";;
      esac;;
    64) case $(($RANDOM % 6 + 1)) in  # Enhanced JOIN SELECTs with ON/USING clauses
        1) n3; local _c=$REPLY; table; local _t1=$REPLY; table; local _t2=$REPLY; onclause; local _on=$REPLY; where
           REPLY="SELECT a1.c${_c} FROM ${_t1} AS a1 JOIN ${_t2} AS a2 ${_on} ${REPLY}";;
        2) table; local _t1=$REPLY; table; local _t2=$REPLY; onclause; local _on=$REPLY; orderby; local _ob=$REPLY; limit
           REPLY="SELECT * FROM ${_t1} AS a1 LEFT JOIN ${_t2} AS a2 ${_on} ${_ob} ${REPLY}";;
        3) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; table; local _t3=$REPLY; n3; local _c2=$REPLY; whereal
           REPLY="SELECT * FROM ${_t1} AS a1 JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} LEFT JOIN ${_t3} AS a3 ON a2.c${_c2}=a3.c${_c2} ${REPLY}";;
        4) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY
           REPLY="SELECT * FROM ${_t1} AS a1 NATURAL JOIN ${_t2} AS a2";;
        5) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY
           REPLY="SELECT * FROM ${_t1} AS a1 NATURAL LEFT JOIN ${_t2} AS a2";;
        6) n3; local _c=$REPLY; table; local _t1=$REPLY; table; local _t2=$REPLY; table; local _t3=$REPLY; n3; local _c2=$REPLY
           REPLY="SELECT a1.c${_c}, a2.c${_c2}, a3.c${_c} FROM ${_t1} AS a1 INNER JOIN ${_t2} AS a2 USING (c${_c}) RIGHT JOIN ${_t3} AS a3 ON a2.c${_c2}=a3.c${_c2}";;
        *) REPLY="Assert: invalid random case selection in enhanced JOIN SELECTs case";;
      esac;;
    65) case $(($RANDOM % 5 + 1)) in  # UNION ALL / combined set operations
        1) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} UNION ALL ${REPLY}";;
        2) selectq; local _sq1=$REPLY; selectq; local _sq2=$REPLY; selectq; REPLY="${_sq1} UNION ALL ${_sq2} UNION ALL ${REPLY}";;
        3) selectq; local _sq1=$REPLY; selectq; REPLY="(${_sq1}) UNION (${REPLY})";;
        4) selectq; local _sq1=$REPLY; selectq; local _sq2=$REPLY; orderby; local _ob=$REPLY; limit
           REPLY="${_sq1} UNION ALL ${_sq2} ${_ob} ${REPLY}";;
        5) selectq; local _sq1=$REPLY; selectq; REPLY="${_sq1} UNION DISTINCT ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in UNION ALL case";;
      esac;;
    66) case $(($RANDOM % 6 + 1)) in  # CREATE/ALTER/DROP DATABASE
        1) REPLY="CREATE DATABASE IF NOT EXISTS test2";;
        2) REPLY="CREATE DATABASE IF NOT EXISTS test3 CHARACTER SET utf8";;
        3) REPLY="CREATE DATABASE IF NOT EXISTS test2 CHARACTER SET latin1 COLLATE latin1_bin";;
        4) REPLY="ALTER DATABASE test CHARACTER SET utf8mb4";;
        5) REPLY="DROP DATABASE IF EXISTS test2";;
        6) REPLY="DROP DATABASE IF EXISTS test3";;
        *) REPLY="Assert: invalid random case selection in CREATE/ALTER/DROP DATABASE case";;
      esac;;

    67) importantvar;;  # Server-state-affecting SET variables (InnoDB, optimizer, buffers, etc.)
    68) importantvar;;  # Second slot for important variables (higher frequency — these are bug-prone)
    69) case $(($RANDOM % 8 + 1)) in  # Enhanced LOCK TABLES with WAIT/NOWAIT
        1) REPLY="UNLOCK TABLES";;
        2) REPLY="UNLOCK TABLES";;
        3) table; local _t=$REPLY; locktype; local _lt=$REPLY; lockwait; REPLY="LOCK TABLE ${_t} ${_lt} ${REPLY}";;
        4) table; local _t1=$REPLY; locktype; local _l1=$REPLY; table; local _t2=$REPLY; n9; local _n=$REPLY; locktype; local _l2=$REPLY; lockwait; REPLY="LOCK TABLES ${_t1} ${_l1}, ${_t2} AS a${_n} ${_l2} ${REPLY}";;
        5) table; local _t=$REPLY; REPLY="FLUSH TABLES ${_t} FOR EXPORT";;
        6) table; local _t=$REPLY; REPLY="FLUSH TABLES ${_t} WITH READ LOCK";;
        7) REPLY="FLUSH TABLES WITH READ LOCK";;
        8) REPLY="FLUSH TABLES";;
        *) REPLY="Assert: invalid random case selection in enhanced LOCK TABLES case";;
      esac;;
    70) case $(($RANDOM % 8 + 1)) in  # Complex multi-table JOINs with ON/USING
        1) seljoincol; local _sc=$REPLY; table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; where; REPLY="SELECT ${_sc} FROM ${_t1} AS a1 LEFT JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} ${REPLY}";;
        2) seljoincol; local _sc=$REPLY; table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; table; local _t3=$REPLY; n3; local _c2=$REPLY; whereal; REPLY="SELECT ${_sc} FROM ${_t1} AS a1 JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} LEFT JOIN ${_t3} AS a3 ON a2.c${_c2}=a3.c${_c2} ${REPLY}";;
        3) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; groupby; local _gb=$REPLY; having; REPLY="SELECT a1.c${_c}, COUNT(*) FROM ${_t1} AS a1 JOIN ${_t2} AS a2 USING (c${_c}) ${_gb} ${REPLY}";;
        4) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; selectq; REPLY="SELECT * FROM ${_t1} AS a1 WHERE a1.c${_c} IN (SELECT c${_c} FROM ${_t2}) AND a1.c${_c} NOT IN (${REPLY})";;
        5) table; local _t1=$REPLY; table; local _t2=$REPLY; table; local _t3=$REPLY; n3; local _c=$REPLY; n3; local _c2=$REPLY; orderby; local _ob=$REPLY; limit; REPLY="SELECT a1.c${_c}, a2.c${_c2}, a3.c${_c} FROM ${_t1} AS a1 INNER JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} RIGHT OUTER JOIN ${_t3} AS a3 ON a2.c${_c2}=a3.c${_c2} ${_ob} ${REPLY}";;
        6) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; REPLY="SELECT * FROM ${_t1} AS a1 LEFT JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} WHERE a2.c${_c} IS NULL";;
        7) table; local _t1=$REPLY; table; local _t2=$REPLY; n3; local _c=$REPLY; data; REPLY="SELECT * FROM ${_t1} AS a1 JOIN ${_t2} AS a2 ON a1.c${_c}=a2.c${_c} AND a1.c${_c}=${REPLY}";;
        8) table; local _t1=$REPLY; n3; local _c=$REPLY; REPLY="SELECT * FROM ${_t1} AS a1 JOIN ${_t1} AS a2 ON a1.c${_c}=a2.c${_c}";;
        *) REPLY="Assert: invalid random case selection in complex JOIN case";;
      esac;;
    71) case $(($RANDOM % 10 + 1)) in  # XA with varied xids + state transitions
    [1-3]) xid; local _x=$REPLY; onephase; REPLY="XA COMMIT ${_x} ${REPLY}";;
       4) xid; REPLY="XA START ${REPLY}";;
       5) xid; REPLY="XA BEGIN ${REPLY}";;
    [6-7]) xid; REPLY="XA END ${REPLY}";;
       8) xid; REPLY="XA PREPARE ${REPLY}";;
       9) convertxid; REPLY="XA RECOVER ${REPLY}";;
      10) xid; REPLY="XA ROLLBACK ${REPLY}";;
        *) REPLY="Assert: invalid random case selection in XA expanded case";;
      esac;;
    72) case $(($RANDOM % 8 + 1)) in  # CREATE TABLE ... SELECT, AS, constraints
        1) orreplace; local _or=$REPLY; table; local _tbl=$REPLY; engine; local _eng=$REPLY; table; local _t2=$REPLY; REPLY="CREATE ${_or} TABLE ${_tbl} ENGINE=${_eng} SELECT * FROM ${_t2}";;
        2) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; table; local _t2=$REPLY; where; REPLY="CREATE TABLE ${_ine} ${_tbl} SELECT * FROM ${_t2} ${REPLY}";;
        3) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct=$REPLY; n3; local _c=$REPLY; engine; local _eng=$REPLY; tableopts
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk}, c2 ${_ct}, c3 INT, CHECK(c${_c} > 0)) ENGINE=${_eng} ${REPLY}";;
        4) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; n3; local _c=$REPLY; engine; local _eng=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk}, c2 ${_ct1} NOT NULL, c3 ${_ct2}, UNIQUE KEY uk1(c${_c})) ENGINE=${_eng}";;
        5) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; ctype; local _ct=$REPLY; table; local _t2=$REPLY; engine; local _eng=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk}, c2 ${_ct}, c3 INT, FOREIGN KEY (c3) REFERENCES ${_t2}(c1)) ENGINE=${_eng}";;
        6) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; ctype; local _ct1=$REPLY; ctype; local _ct2=$REPLY; ctype; local _ct3=$REPLY; engine; local _eng=$REPLY; tableopts
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_ct1} NOT NULL, c2 ${_ct2} NOT NULL, c3 ${_ct3}, PRIMARY KEY (c1,c2)) ENGINE=${_eng} ${REPLY}";;
        7) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; n3; local _c=$REPLY; engine; local _eng=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk}, c2 INT GENERATED ALWAYS AS (c1 + 1) VIRTUAL, c3 INT GENERATED ALWAYS AS (c1 * 2) PERSISTENT, INDEX(c${_c})) ENGINE=${_eng}";;
        8) ifnotexist; local _ine=$REPLY; table; local _tbl=$REPLY; pk; local _pk=$REPLY; engine; local _eng=$REPLY
           REPLY="CREATE TABLE ${_ine} ${_tbl} (c1 ${_pk}, c2 INT DEFAULT 0, c3 VARCHAR(255) DEFAULT '', c4 TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=${_eng}";;
        *) REPLY="Assert: invalid random case selection in CREATE TABLE expanded case";;
      esac;;

     # TIP: when adding new options, make sure to update the case/esac to reflect the new number of options (the number behind the '%' in the case statement at the top of the list matches the number of available 'nr)' options)
     *) REPLY="Assert: invalid random case selection in main case";;
  esac
}

thread(){
  local _outfile="${FINAL_OUTFILE}${RANDOM_SUFFIX}_${1}.sql"
  local i
  for ((i=1; i<=QUERIES_PER_THREAD; i++)); do
    query
    printf '%s\n' "${REPLY};"
  done > "$_outfile"
}

# ====== Main runtime
_tmp="${RANDOM}${RANDOM}${RANDOM}"; RANDOM_SUFFIX="${_tmp:2:6}"  # Random number generator (6 digits)
MUTEX_THREAD_BUSY=0
QUERIES_PER_THREAD=$(( ${QUERIES} / ${THREADS} ))
FINAL_OUTFILE="${OUTPUT_FILE%.sql}"
PIDS=
if [ ${QUERIES_PER_THREAD} -gt 0 ]; then
  # Remove old output file & old temporary files (if any)
  rm -f ${FINAL_OUTFILE}.sql     # old output file
  rm -f ${FINAL_OUTFILE}*_*.sql  # old temporary files (if threads were used). DO NOT REMOVE '_' as batches.sh generates outcome.sql
  touch ${FINAL_OUTFILE}.sql
  if [ ! -r ${FINAL_OUTFILE}.sql ]; then
    echo "Assert: ${FINAL_OUTFILE}.sql not present after 'touch ${FINAL_OUTFILE}.sql' command!"
    exit 1
  fi
  # Actual query generation
  for ((i=1; i<=${THREADS}; i++)); do
    thread $i &
    PIDS="${PIDS} $!"
  done
  wait ${PIDS}
  # Process the leftover queries (result of rounding (queries/threads) into an integer result) by simply adding the leftover queries to the output file of thread 1
  QUERIES_PER_THREAD=$(( ${QUERIES} - ( ${THREADS} * ${QUERIES_PER_THREAD} ) ));
  if [ ${QUERIES_PER_THREAD} -gt 0 ]; then thread 1; fi
  # Recombine individual thread files
  for ((i=1; i<=${THREADS}; i++)); do
    cat ${FINAL_OUTFILE}${RANDOM_SUFFIX}_${i}.sql >> ${FINAL_OUTFILE}.sql
    rm ${FINAL_OUTFILE}${RANDOM_SUFFIX}_${i}.sql
  done
fi

# == Check for failures or report outcome
if grep -qi "Assert" ${FINAL_OUTFILE}.sql; then
  echo "Errors found, please fix generator.sh code:"
  grep "Assert" ${FINAL_OUTFILE}.sql | sort -u | sed "s|[ ]*;$||"
  rm ${FINAL_OUTFILE}.sql 2>/dev/null
else
  # SQL syntax cleanup; replace tabs to spaces, replace double or more spaces with single space, remove spaces when in front of a comma, remove end-of-line spaces
  sed -i "s|\t| |g;s|  \+| |g;s|[ ]*,|,|g;s|[ ]*;$|;|" ${FINAL_OUTFILE}.sql
  END=$(date +%s); RUNTIME=$(( ${END} - ${START} )); MINUTES=$(( ${RUNTIME} / 60 )); SECONDS=$(( ${RUNTIME} % 60 ))
  echo "DONE! Generated ${QUERIES} quality queries in ${MINUTES}m${SECONDS}s, and saved the results in ${FINAL_OUTFILE}.sql"
  echo "NOTE: you may like to do:  \$ sed -i \"s|some_engine|InnoDB|gi\" ${FINAL_OUTFILE}.sql  # Or, edit engines.txt and run generator.sh again"
fi

# Handy ref for large merged files swap all to given SE: sed "s|Aria|InnoDB|gi;s|MyISAM|InnoDB|gi;s|BLACKHOLE|InnoDB|gi;s|RocksDB|InnoDB|gi;s|RocksDBcluster|InnoDB|gi;s|MRG_MyISAM|InnoDB|gi;s|SEQUENCE|InnoDB|gi;s|NDB|InnoDB|gi;s|NDBCluster|InnoDB|gi;s|CSV|InnoDB|gi;s|TokuDB|InnoDB|gi;s|MEMORY|InnoDB|gi;s|ARCHIVE|InnoDB|gi;s|CASSANDRA|InnoDB|gi;s|CONNECT|InnoDB|gi;s|EXAMPLE|InnoDB|gi;s|FALCON|InnoDB|gi;s|HEAP|InnoDB|gi;s|INNODBcluster|InnoDB|gi;s|MARIA|InnoDB|gi;s|MEMORYCLUSTER|InnoDB|gi;s|MERGE|InnoDB|gi;s|Spider|InnoDB|gi;s|InnoDB|InnoDB|gi" input.sql | sort -r > output.sql
# And maybe: sed "s|PERFORMANCE_SCHEMA|test|gi;s|INFORMATION_SCHEMA|test|gi;"
