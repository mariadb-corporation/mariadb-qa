#!/bin/bash
# Created by Roel Van de Paar, MariaDB

echo 'Remember to run cloneall.sh first!' && sleep 3

# User variables
BUILD_10_1=0
BUILD_10_2=0
BUILD_10_3=0
BUILD_10_4=0
BUILD_10_5=1
BUILD_10_6=1
BUILD_10_7=0
BUILD_10_8=0
BUILD_10_9=0
BUILD_10_10=0
BUILD_10_11=1
BUILD_11_0=0
BUILD_11_1=0
BUILD_11_2=0
BUILD_11_3=0
BUILD_11_4=1
BUILD_11_5=0
BUILD_11_6=0
BUILD_11_7=1
BUILD_11_8=1

#export ADD_EXTRA_AUTO_OPTIONS=''  # Add additional cmake options, granular per-version settings below
ADD_EXTRA_AUTO_OPTIONS='-DWITH_PMEM=1'
USE_EXTRA_A_OPT_10_1=0
USE_EXTRA_A_OPT_10_2=0
USE_EXTRA_A_OPT_10_3=0
USE_EXTRA_A_OPT_10_4=0
USE_EXTRA_A_OPT_10_5=0
USE_EXTRA_A_OPT_10_6=0
USE_EXTRA_A_OPT_10_7=0
USE_EXTRA_A_OPT_10_8=0
USE_EXTRA_A_OPT_10_9=1
USE_EXTRA_A_OPT_10_10=1
USE_EXTRA_A_OPT_10_11=1
USE_EXTRA_A_OPT_11_0=1
USE_EXTRA_A_OPT_11_1=1
USE_EXTRA_A_OPT_11_2=1
USE_EXTRA_A_OPT_11_3=1
USE_EXTRA_A_OPT_11_4=1
USE_EXTRA_A_OPT_11_5=1
USE_EXTRA_A_OPT_11_6=1
USE_EXTRA_A_OPT_11_7=1
USE_EXTRA_A_OPT_11_8=1

# Script variables setup
export -n EXTRA_AUTO_OPTIONS  # Remove the export property (does not unset)
EXTRA_AUTO_OPTIONS=  # Unset
DIR=${PWD}

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_slow" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_slow"
  return 2> /dev/null; exit 0
fi

cleanup_dirs(){
  cd ${DIR}
  if [ -d /data/TARS ]; then mv ${DIR}/*.tar.gz /data/TARS 2>/dev/null; sync; fi
  rm -Rf 10.1_dbg 10.2_dbg 10.3_dbg 10.4_dbg 10.5_dbg 10.6_dbg 10.7_dbg 10.8_dbg 10.9_dbg 10.10_dbg \
         10.1_opt 10.2_opt 10.3_opt 10.4_opt 10.5_opt 10.6_opt 10.7_opt 10.8_opt 10.9_opt 10.10_opt \
         10.11_dbg 11.0_dbg 11.1_dbg 11.2_dbg 11.3_dbg 11.4_dbg 11.5_dbg 11.6_dbg 11.7_dbg 11.8_dbg \
         10.11_opt 11.0_opt 11.1_opt 11.2_opt 11.3_opt 11.4_opt 11.5_opt 11.6_opt 11.7_opt 11.8_opt
}

buildall(){  # Build 2-by-2 in reverse order to optimize initial time-till-ready-for-use (newer builds=larger=longer)
  if [ ${BUILD_11_8} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_8}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.8 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.8 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_7} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_7}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.7 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.7 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_6} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_6}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.6 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.6 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_5} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_5}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.5 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.5 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_4} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_4}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.4 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.4 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_3} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_3}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.3 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.3 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_2} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_2}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_1} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_1}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_11_0} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_11_0}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_11} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_11}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_10} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_10}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_9} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_9}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_8} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_8}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_7} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_7}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_6} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_6}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi
  
  if [ ${BUILD_10_5} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_5}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_4} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_4}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_3} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_3}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_2} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_2}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi

  if [ ${BUILD_10_1} -eq 1 ]; then
    if [ ! -z "${ADD_EXTRA_AUTO_OPTIONS}" -a "${USE_EXTRA_A_OPT_10_1}" -eq 1 ]; then
      export EXTRA_AUTO_OPTIONS="${ADD_EXTRA_AUTO_OPTIONS}"
    else 
      export -n EXTRA_AUTO_OPTIONS; EXTRA_AUTO_OPTIONS=
    fi
    cleanup_dirs; cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt.sh
    cleanup_dirs; cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg.sh
  fi
}

buildall
cleanup_dirs

# Cleanup
export -n EXTRA_AUTO_OPTIONS
EXTRA_AUTO_OPTIONS=
