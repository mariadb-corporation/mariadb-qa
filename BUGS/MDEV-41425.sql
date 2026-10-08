# Requires /tmp/t1.csv of 4300000100 bytes: one line "2," plus 97 "b", then 43000000 lines "1," plus 97 "a"; ref bug report for MTR testcase
INSTALL SONAME 'ha_connect';
CREATE TABLE t1 (a INT NOT NULL, b CHAR(97) NOT NULL) ENGINE=CONNECT TABLE_TYPE=CSV FILE_NAME='/tmp/t1.csv' SEP_CHAR=',' HUGE=1;
DELETE FROM t1 WHERE a = 2;
#CLI: ERROR 1296 (HY000): Got error 122 'ftell error for recd=0: Invalid argument' from CONNECT; /tmp/t1.csv is then 5032704 bytes, expected 4300000000
#ERR: rnd_next CONNECT: ftell error for recd=0: Invalid argument
