#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# TODO: Idea: the current file check (only done for reducer.log) checks the file age. Likely other directories could have a file age check by using ls -t 2>/dev/null | head -n1 and taking the age of that file. If any updates happen in the directory then this would show directory is still live/active

EXCLUDE_DIR_REGEX='multipath|var_|afl|sql_shuffled|r1'  # 'var_' is excluded to avoid deleting MTR --mem directories, and multipath is a system dir
LOW_MEMORY=20  # A number, reflecting a minimum 'directly free available memory' before long-running reducers which have been successful thus far (i.e. at least 2 ~/pge started after the original reduction, and file is _out_out_out already), are terminated. If total memory is for example 128GB then 20 may be a good number to use here, or similar.

ARMED=0
if [ "${1}" != "1" ]; then
  echo "(!) Script not armed! To arm it, include the number 1 behind it, e.g.: $ ~/mariadb-qa/tmpfs_clean.sh 1"
  echo "(!) Doing so would enable actual tmpfs cleanup. Now executing a trial run only: no actual changes are made!"
else
  ARMED=1
fi

SILENT=0
if [ "${2}" != "" ]; then
  SILENT=1
fi

# Check if not running already. The '$$' check is necessary as otherwise the command captures it's own process
if [ ! -z "$(ps -ef | grep tmpfs_clean | grep -vE "grep|vi |$$")" ]; then
  if [ ${SILENT} -eq 0 ]; then
    echo "Self terminating as tmpfs_clean.sh is running elsewhere already:"
    ps -ef | grep tmpfs_clean | grep -vE "grep|vi |$$"
  fi
  exit 2
fi

# To avoid overly long running ~/pge repeat reducers, we terminate them after at least 3 (the original reduction + 
# two ~/pge's) runs if memory is running low. These reducers are highly likely quite far advanced in overall testcase 
# reduction as we are at at least 3 runs (on the same testcase) far. Reducers will only create '_out..._out' file 
# iterations if reduction was successful at least once
# Update RV 2 Apr 24: this was terminating manually started important reducers that already had a 'out_out_out' testcase. Also, PGE_LOOPS was previously set to 2 in ~/sr as more pge loops caused too much system load overall (balance of all work). Thus, this is no longer needed and additionally causes issues as described: disabled
#AVAILABLE_MEM=$(free -g | grep 'Mem' | awk '{print $7}')
#if [ -z "${LOW_MEMORY}" ]; then LOW_MEMORY=20; fi
#if [ "${AVAILABLE_MEM}" -lt ${LOW_MEMORY} ]; then
#  cd /dev/shm; tail -n1 */reducer.log | grep -B1 'out_out_out' | grep -B1 'DONE' | grep --binary-files=text '==>.*/reducer.log <==' | grep -o '[0-9]\+' | sort -u | grep '^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' | xargs -I{} echo "if [ -d \"{}\" ]; then rm -Rf \"/dev/shm/{}\"; fi" | xargs -I{} bash -c "{}" 
#fi

# General/Main cleanup
COUNT_FOUND_AND_DEL=0
COUNT_FOUND_AND_NOT_DEL=0
if [ $(ls --color=never -ld /dev/shm/* 2>/dev/null | grep --binary-files=text -vE "${EXCLUDE_DIR_REGEX}" | wc -l) -eq 0 ]; then
  if [ ${SILENT} -eq 0 ]; then
    echo "> No /dev/shm/* erasable directories found"
  fi
else
  rm -f /tmp/tmpfs_clean_dirs
  # In the next line, 'var_' is excluded to avoid deleting MTR --mem directories
  ls --color=never -ld /dev/shm/* 2>/dev/null | grep --binary-files=text -vE "${EXCLUDE_DIR_REGEX}" | sed 's|^.*/dev/shm|/dev/shm|' >/tmp/tmpfs_clean_dirs 2>/dev/null
  COUNT=$(wc -l /tmp/tmpfs_clean_dirs 2>/dev/null | sed 's| .*||')
  for DIRCOUNTER in $(seq 1 ${COUNT}); do
    DIR="$(head -n ${DIRCOUNTER} /tmp/tmpfs_clean_dirs | tail -n1)"
    STORE_COUNT_FOUND_AND_DEL=${COUNT_FOUND_AND_DEL}
    if [ -d ${DIR} ]; then  # Ensure it's a directory (avoids deleting pquery-reach.log for example)
      if [ $(ps -ef | grep --binary-files=text -v 'grep' | grep --binary-files=text "${DIR}" | wc -l) -eq 0 ]; then
        sync; sleep 0.3  # Small wait, then recheck (to avoid missed ps output)
        if [ $(ps -ef | grep --binary-files=text -v 'grep' | grep --binary-files=text "${DIR}" | wc -l) -eq 0 ]; then
          sync; sleep 0.3  # Small wait, then recheck (to avoid missed ps output)
          if [ $(ps -ef | grep --binary-files=text -v 'grep' | grep --binary-files=text "${DIR}" | wc -l) -eq 0 ]; then
            AGEDIR=$[ $(date +%s) - $(stat -c %Z ${DIR}) ]  # Directory age in seconds
            if [ ${AGEDIR} -ge 90 ]; then  # Yet another safety, don't delete very recent directories
              if [ -r ${DIR}/reducer.log ]; then
                AGEFILE=$[ $(date +%s) - $(stat -c %Z ${DIR}/reducer.log) ]  # File age in seconds
                if [ ${AGEFILE} -ge 90 ]; then  # Yet another safety specifically for often-occuring reducer directories, don't delete very recent reducers
                  if [ ${SILENT} -eq 0 ]; then
                    echo "Deleting reducer directory ${DIR} (directory age: ${AGEDIR}s, file age: ${AGEFILE}s)"
                  fi
                  COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
                  if [ ${ARMED} -eq 1 ]; then rm -Rf ${DIR}; fi
                fi
              else
                DIRNAME=$(echo ${DIR} | sed 's|.*/||')
                if [ "$(echo ${DIRNAME} | sed 's|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]||' | sed 's|[0-9][0-9][0-9][0-9][0-9][0-9][0-9]||' | sed 's|[0-9][0-9][0-9][0-9][0-9][0-9]||')" == "" ]; then  # 10, 7 or 6 Numbers subdir; this is likely a multirun_mysqld.sh (10), pquery-reach.sh (7) or pquery-run.sh (6) generated directory. Note that lenghts have to go from high to low, otherwise a partial replace (for example 6 numbers) of a larger number (for example 10) may happen and thus this if statement would not eval as true
                  SUBDIRCOUNT=$(ls --color=never -dF ${DIR}/* 2>/dev/null | grep --binary-files=text \/$ | sed 's|/$||' | wc -l)  # Number of trial subdirectories
                  if [ ${SUBDIRCOUNT} -le 1 ]; then  # pquery-run.sh directories generally have 1 (or 0 when in between trials) subdirectories. Both 0 and 1 need to be covered
                    if [ $(ls ${DIR}/*pquery*reach* 2>/dev/null | wc -l) -gt 0 ]; then # A pquery-reach.sh directory
                      PR_FILE_TO_CHECK=$(ls --color=never ${DIR}/*pquery*reach* 2>/dev/null | head -n1)  # Head -n1 is defensive, there should be only 1 file
                      if [ -z ${PR_FILE_TO_CHECK} ]; then
                        echo "Assert: \$PR_FILE_TO_CHECK empty"
                        exit 1
                      fi
                      AGEFILE=$(( $(date +%s) - $(stat -c %Z "${PR_FILE_TO_CHECK}")))  # File age in seconds
                      if [ ${AGEFILE} -ge 1200 ]; then  # Delete pquery-reach.sh directories aged >=20 minutes
                        if [ ${SILENT} -eq 0 ]; then
                          echo "Deleting pquery-reach.sh directory ${DIR} (pquery-reach log age: ${AGEFILE}s)"
                        fi
                        COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
                        if [ ${ARMED} -eq 1 ]; then rm -Rf ${DIR}; fi
                      fi
                    else
                      SUBDIR=$(ls --color=never -dF ${DIR}/* 2>/dev/null | grep --binary-files=text \/$ | sed 's|/$||')
                      for i in `seq 1 3`; do  # Try 3 times
                        if [ "${SUBDIR}" == "" ]; then  # Script may have caught a snapshot in-between pquery-run.sh trials
                          sync; sleep 3  # Delay (to provide pquery-run.sh (if running) time to generate new trial directory), then recheck
                          SUBDIR=$(ls --color=never -dF ${DIR}/* 2>/dev/null | grep --binary-files=text \/$ | sed 's|/$||')
                        else
                          break
                        fi
                      done
                      if [ ! -z "${SUBDIR}" ]; then  # No subdir, if directory exists, then it is empty
                        AGESUBDIR=$(( $(date +%s) - $(stat -c %Z "${SUBDIR}") ))  # Current trial directory age in seconds
                        if [ ${AGESUBDIR} -ge 10800 ]; then  # Don't delete pquery-run.sh directories if they have recent trials in them (i.e. they are likely still running): >=3hr
                          if [[ "${DIR}" != "/dev/shm/sql_shuffled" && "${DIR}" != "/dev/shm/afl"* ]]; then  # Do not delete the temporary SQL shuffle directory created and used by pquery-run.sh, and do not delete fuzzer directories
                            if [ ${SILENT} -eq 0 ]; then
                              echo "Deleting workdir ${DIR} (trial subdirectory age: ${AGESUBDIR}s)"
                            fi
                            COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
                            if [ ${ARMED} -eq 1 ]; then rm -Rf ${DIR}; fi
                          fi
                        fi
                      fi
                    fi
                  else
                    # multirun_mysqld.sh-like dir check
                    MMDC=$(ls --color=never ${DIR}/* 2>/dev/null | grep --binary-files=text -E 'socket|pid' | wc -l)  # Number of files relevant to multirun_mysqld.sh
                    if [ "${MMDC}" -ge 2 ]; then  # If >=2 it is reasonable to assume this is a multirun_mysqld.sh directory
                      MAINMDDIRAGE=$[ $(date +%s) - $(stat -c %Z ${DIR}) ]  # Directory age in seconds
                      if [ ${MAINMDDIRAGE} -gt 90 ]; then  # Safety: don't delete any directory touched in last 90 seconds
                        echo "Deleting multirun_mysqld.sh-like directory ${DIR}"
                        COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
                        if [ ${ARMED} -eq 1 ]; then rm -Rf ${DIR}; fi
                      fi
                      MAINMDDIRAGE=
                    else 
                      echo "> Warning: Unrecognized directory structure: ${DIR} (Assert: >=1 sub directories found, not fully covered yet, please fixme)"
                    fi
                    MMDC=
                  fi
                else
                  if [[ "${DIR}" != "/dev/shm/sql_shuffled" && "${DIR}" != "/dev/shm/afl"* ]]; then  # As above
                    if [ ${SILENT} -eq 0 ]; then
                      echo "Deleting directory ${DIR} (directory age: ${AGEDIR}s)"
                    fi
                    COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
                    if [ ${ARMED} -eq 1 ]; then rm -Rf ${DIR}; fi
                  fi
                fi
              fi
            fi
          fi
        fi
      fi
    fi
    if [ ${STORE_COUNT_FOUND_AND_DEL} -eq ${COUNT_FOUND_AND_DEL} ]; then  # A directory was found but not deleted
      COUNT_FOUND_AND_NOT_DEL=$[ ${COUNT_FOUND_AND_NOT_DEL} + 1 ]
    fi; STORE_COUNT_FOUND_AND_DEL=
  done
  # Check for out-of-use sql_shuffled files (new method)
  if [ -d /dev/shm/sql_shuffled ]; then
    cd /dev/shm/sql_shuffled
    TEMP=$(mktemp)
    touch -d '5 hours ago' ${TEMP}
    FILELIST=$(mktemp)
    ls --color=never 2>/dev/null | grep -vE "$(find . -type p,f,s,l -newer ${TEMP} 2>&1 | sed 's|^\./||;s/\n/|/g' )" > ${FILELIST}  # -v: older
    rm -f ${TEMP}
    NROFFILES=$(cat ${FILELIST} 2>/dev/null | wc -l)
    if [ "${NROFFILES}" -gt 0 ]; then
      for i in `seq 1 ${NROFFILES}`; do  
        FILETODEL="/dev/shm/sql_shuffled/$(head -n${i} ${FILELIST} 2>/dev/null | tail -n1)"
        if [ -r "${FILETODEL}" ]; then 
          echo "Deleting outdated sql shuffle file ${FILETODEL} (file age: $[ $(date +%s) - $(stat -c %Z ${FILETODEL}) ]s)"
          if [ ${ARMED} -eq 1 ]; then rm -f "${FILETODEL}" ; fi
          COUNT_FOUND_AND_DEL=$[ ${COUNT_FOUND_AND_DEL} + 1 ]
        fi
        FILETODEL=
      done
    fi
    rm -f ${FILELIST}
    FILELIST=
    NROFFILES=
    TEMP=
    cd - >/dev/null
  fi
  # Final output
  if [ ${SILENT} -eq 0 ]; then
    if [ ${COUNT_FOUND_AND_NOT_DEL} -ge 1 -a ${COUNT_FOUND_AND_DEL} -eq 0 ]; then
      echo ""
      echo "> Though $(ls -ld /dev/shm/* 2>/dev/null | wc -l) tmpfs directories/files were found on /dev/shm, they are all in use. Nothing was deleted."
    else
      if [ ${COUNT_FOUND_AND_DEL} -gt 0 ]; then
        echo "> Deleted ${COUNT_FOUND_AND_DEL} tmpfs directories/files & skipped ${COUNT_FOUND_AND_NOT_DEL} tmpfs directories/files as they were in use."
      else
        echo "> Deleted ${COUNT_FOUND_AND_DEL} tmpfs directories/files. No other tmpfs directories/files exist. All good."
      fi
    fi
  fi
fi

# This is now handles above in 'Check for out-of-use sql_shuffled files (new method)'
# TODO: somehow make this more universal in case PRE_SHUFFLE_DIR is changed in pquery-run.conf
#if [ -d /dev/shm/sql_shuffled ]; then
#  if [ ${SILENT} -eq 0 ]; then
#    echo "> Note: /dev/shm/sql_shuffled directory found (default PRE_SHUFFLE_DIR in pquery-run.conf): cleaning unused shuffled SQL files"
#  fi
#  sleep 2
#  # The following oneliner takes the leading 6 digits of the shuffled .sql file (which is the workdir), then checkes if a pquery-go-expert screen (running in a 'ge' screen session) with the same workdir is running. If not, it will delete the file as it is then safe to do so. 
# # TODO: how to make this safer for runs not started inside screen sessions (almost never the case for professional setups). Perhaps it is possible to do a similar "age check" as is used elsewhere in this script
#  ls --color=never /dev/shm/sql_shuffled 2>/dev/null | sed 's|_[0-9]\+\.sql||' | xargs -I{} echo "echo '{}' | grep -vE \$(screen -ls | grep -o '\.ge[0-9][0-9][0-9][0-9][0-9][0-9]' | sed 's|\.ge||' | tr '\n' '|' | sed 's/|$//') 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | xargs -I{} echo "if [ ! -z '{}' ]; then echo 'rm -Rf /dev/shm/sql_shuffled/{}_*.sql'; fi" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
#fi

if [ ! -z "$(ls -d --color=never /dev/shm/var_* 2>/dev/null)" ]; then
  echo "> Note: MTR --mem directories found, please check/delete these manually as required (first column is space used):"
  du -shc /dev/shm/var_* | grep -v total
fi

if [ ${SILENT} -eq 0 ]; then
  echo "> Done! /dev/shm available space is now: $(df -h | egrep --binary-files=text "/dev/shm" | awk '{print $4}')"
fi
exit 0

# With thanks, https://linoxide.com/linux-command/linux-commad-to-list-directories-directory-names-only/
