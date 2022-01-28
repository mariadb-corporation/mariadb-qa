#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB

# Terminates all owned live mysql, mysqld and maria processes
ps -ef | grep -E "mysql|maria" | grep "$(whoami)" | egrep -v "grep" | awk '{print $2}' | xargs kill -9 2>/dev/null
