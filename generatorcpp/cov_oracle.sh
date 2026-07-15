#!/bin/bash
# Coverage scenario: single-node replay under sql_mode=ORACLE, exercising the Oracle-dialect
# parser (yy_oracle.cc) and PL/SQL paths. Thin wrapper over coverage_run.sh that sets the
# server sql_mode and tags the run; all other knobs (NQ/CHUNK/CPAR/GEN/...) pass through.
set -u
export SQLMODE="${SQLMODE:-ORACLE}"
export TAG="${TAG:-oracle}"
exec bash "$HOME/mariadb-qa/generatorcpp/coverage_run.sh"
