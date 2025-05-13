#!/bin/bash
# Created by Ramesh Sivaraman and Roel Van de Paar, MariaDB

clean_and_validate(){
  SOURCE_CODE_REV="$(echo "${SOURCE_CODE_REV}" | head -n1 | sed 's|[ \n\t]\+||g')"  # Remove spaces, newlines, tabs
  if [ -z "${SOURCE_CODE_REV}" ]; then
    return
  fi
  VALIDATE_SYNTAX="$(echo "${SOURCE_CODE_REV}" | grep -o '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]')"
  if [ "${SOURCE_CODE_REV}" != "${VALIDATE_SYNTAX}" ]; then  # Not a valid git commit hash
    SOURCE_CODE_REV=
  fi
  VALIDATE_SYNTAX=
}

if [ -z "$SOURCE_CODE_REV" -a -r ./include/mysql/server/private/source_revision.h ]; then
  SOURCE_CODE_REV="$(cat ./include/mysql/server/private/source_revision.h 2>/dev/null | cut -d'"' -f2)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ../include/mysql/server/private/source_revision.h ]; then
  SOURCE_CODE_REV="$(cat ../include/mysql/server/private/source_revision.h 2>/dev/null | cut -d'"' -f2)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ./mysqld/source_revision.h ]; then
  SOURCE_CODE_REV="$(cat ./mysqld/source_revision.h 2>/dev/null | cut -d'"' -f2)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ../mysqld/source_revision.h ]; then
  SOURCE_CODE_REV="$(cat ../mysqld/source_revision.h 2>/dev/null | cut -d'"' -f2)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ./dbuild/Docs/INFO_SRC ]; then  # MS build
  SOURCE_CODE_REV="$(grep -om1 'commit.*' ./dbuild/Docs/INFO_SRC | awk '{print $2}' | sed 's|[ \n\t]\+||g')"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ./docs/INFO_SRC ]; then  # MS build
  SOURCE_CODE_REV="$(grep -om1 'commit.*' ./docs/INFO_SRC | awk '{print $2}' | sed 's|[ \n\t]\+||g')"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ../docs/INFO_SRC ]; then  # MS build
  SOURCE_CODE_REV="$(grep -om1 'commit.*' ../docs/INFO_SRC | awk '{print $2}' | sed 's|[ \n\t]\+||g')"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" ]; then
  # With thanks to https://www.cyberciti.biz/faq/howto-grep-text-between-two-words-in-unix-linux/
  if [ -r ./log/master.err ]; then
    SOURCE_CODE_REV=$(grep -oP '(?<=source revision )(?s).*(?= as process)' ./log/master.err 2>/dev/null)
  elif [ -r ./node1/node1.err -o -r ./node1/node1.err ]; then
    SOURCE_CODE_REV=$(grep -oPh '(?<=source revision )(?s).*(?= as process)' ./node*/node*.err 2>/dev/null | head -n1)
  fi
  clean_and_validate
fi

if [ -z "$SOURCE_CODE_REV" -a -r ./git_revision.txt ]; then
  # This file is being added by mariadb-qa/build_mdpsms_opt/dbg.sh as of early Feb 2023
  SOURCE_CODE_REV="$(cat ./git_revision.txt 2>/dev/null)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" -a -r ../git_revision.txt ]; then
  # This file is being added by mariadb-qa/build_mdpsms_opt/dbg.sh as of early Feb 2023
  SOURCE_CODE_REV="$(cat ../git_revision.txt 2>/dev/null)"
fi
clean_and_validate

if [ -z "$SOURCE_CODE_REV" ]; then
  BIN=
  if [ -x ./bin/mariadbd ]; then BIN='./bin/mariadbd'; 
  elif [ -x ../bin/mariadbd ]; then BIN='../bin/mariadbd'; 
  elif [ -x ./bin/mysqld ]; then BIN='./bin/mysqld'; 
  elif [ -x ../bin/mysqld ]; then BIN='../bin/mysqld'; 
  elif [ -x ./bin/mysqld-debug ]; then BIN='./bin/mysqld-debug'; 
  elif [ -x ../bin/mysqld-debug ]; then BIN='../bin/mysqld-debug'; 
  elif [ -x ./mysqld/mysqld ]; then BIN='./mysqld/myqsld'; 
  elif [ -x ./mysqld/mariadbd ]; then BIN='./mysqld/mariadbd'; 
  elif [ -x ../mysqld/mysqld ]; then BIN='../mysqld/myqsld'; 
  elif [ -x ../mysqld/mariadbd ]; then BIN='../mysqld/mariadbd'; 
  elif [ -x ../../mariadbd ]; then BIN='../../mariadbd'; 
  elif [ -x ../../mysqld ]; then BIN='../../mysqld'; 
  elif [ -x ./dbuild/sql/mariadbd ]; then BIN="./dbuild/sql/mariadbd";
  else echo "Assert: Server binary could not be found"; exit 1;
  fi
  if [ -r "${BIN}" ]; then
    # Newer method, after Feb 2023
    SOURCE_CODE_REV="$(strings ${BIN} | grep --binary-files=text -im1 -A1 '^Source control revision id for MariaDB source code' | grep -v 'Source control revision id for MariaDB source code')"
    clean_and_validate  # Important format check; in case the next line (-A1) was NOT a revision but some other arbritary string
    if [ -z "$SOURCE_CODE_REV" ]; then
      # Older method, worked up till circa early Feb 2023. Left for backwards compatibility if SOURCE_CODE_REV still not found (unlikely)
      SOURCE_CODE_REV="$(grep -om1 --binary-files=text "Source control revision id for MariaDB source code[^ ]\+" ${BIN} 2>/dev/null | tr -d '\0' | sed 's|.*source code||;s|Version||;s|version_source_revision||')"
    fi
    clean_and_validate
  fi
fi

if [ ! -z "$SOURCE_CODE_REV" ]; then
  echo "${SOURCE_CODE_REV}"
  exit 0
else
  echo "*** Source code revision could not extracted from anywhere, please improve/expand source_code_rev.sh ***"
  exit 1
fi
