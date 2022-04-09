#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB

# Terminates all owned QA-relevant processes
ps -ef | egrep "mysql"     | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "maria"     | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "reducer"   | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "valgrind"  | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "pquery"    | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "go-expert" | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "\./all"    | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "bug"       | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
ps -ef | egrep "multirun"  | grep "$(whoami)" | egrep -v "grep|vim|kill_all_procs" | awk '{print $2}' | xargs kill -9 2>/dev/null
