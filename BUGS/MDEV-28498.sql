CREATE TABLE t0 (a ENUM ('',0x0000),b ENUM (''));

# Then check error log for: [ERROR] mysqld: Incorrect information in file: './test/t0.frm' or CLI output for: ERROR 1033 (HY000) at line 1 in file: 'in.sql': Incorrect information in file: './test/t0.frm'
