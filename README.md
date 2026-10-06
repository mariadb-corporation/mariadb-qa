MariaDB QA
==================================================================================

MariaDB QA is a suite of scripts and utilities which assists in building, fuzzing, automated testing and bug reporting tools for MariaDB products.

With thanks and gratitude to the team at Percona for the original work at:
* https://github.com/Percona-QA/percona-qa

For a video introduction to PQuery and a number of the PQuery Framework scripts, see:
* https://www.percona.com/blog/free-mysql-qa-and-bash-linux-training-series/

For a start guide to the Framework (PQuery + MariaDB's implementation of the Squirrel Fuzzer), see:
* https://github.com/mariadb-corporation/mariadb-qa/blob/master/fuzzer/README
* https://github.com/mariadb-corporation/mariadb-qa/blob/master/fuzzer/SETUP
* https://github.com/mariadb-corporation/mariadb-qa/blob/master/fuzzer/PROCEDURE

CorLogic (ref corlogic/ dir) runs the same SQL on two or more servers and reports where the results differ. See:
* https://github.com/mariadb-corporation/mariadb-qa/blob/master/corlogic/README.md

Omnium, in its own repository, is one binary for the whole pipeline: build, test, reduce, report, and file in Jira. It uses the known-bug lists, filters, SQL generators and reducer from this repository. See:
* https://github.com/mariadb-corporation/omnium

Please Note: 
* For a number of the scripts to run successfully, it is required that sudo is enabled and working and should not request a password.
* Please contact Roel or Ramesh (ref commits) if you have any questions, or for information.
* Most of the documentation is in-line in the code: checkout the scripts to learn more.
