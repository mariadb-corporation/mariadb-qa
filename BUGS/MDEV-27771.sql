SET NAMES cp932;
CREATE TABLE t1 (gc CHAR(1) GENERATED ALWAYS AS ('�')) ENGINE=InnoDB;

# Then check error log for [ERROR] mysqld: Incorrect information in file: './test/t1.frm' and client reports ERROR 1918 (22007): Encountered illegal value '�' when converting to latin1
