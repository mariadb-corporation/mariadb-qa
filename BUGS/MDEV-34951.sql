CREATE OR REPLACE TABLE t1 (a INT,b INT,KEY(a),KEY(b));
ALTER TABLE t1 RENAME KEY b TO B;
DELETE FROM t1;

CREATE TABLE t (c INT UNIQUE) ENGINE=InnoDB;
ALTER TABLE t RENAME KEY c TO C;
ALTER TABLE t MODIFY C INT;
SHOW WARNINGS;
# CLI: 2x warning similar to 'Warning | 1082 | InnoDB: Table test/t contains 2 indexes inside InnoDB, which is different from the number of indexes 1 defined in the MariaDB'
# ERR: 2x error similar to '[ERROR] InnoDB: Table test/t contains 2 indexes inside InnoDB, which is different from the number of indexes 1 defined in the .frm file. See https://mariadb.com/kb/en/innodb-troubleshooting/'

CREATE TABLE t (c POINT GENERATED ALWAYS AS (POINT(1,1)) UNIQUE) ENGINE=InnoDB;
ALTER TABLE t RENAME KEY c to C;
INSERT INTO t VALUES (1);
# OR
CREATE TABLE t (c POINT GENERATED ALWAYS AS (POINT(1,1)) UNIQUE) ENGINE=InnoDB;
ALTER TABLE t RENAME KEY c to C;
INSERT INTO t VALUES (1,1);
# ERR: [ERROR] Cannot find index C in InnoDB index dictionary. [ERROR] InnoDB indexes are inconsistent with what defined in .frm for table ./test/t [ERROR] InnoDB could not find key no 0 with name C from dict cache for table test/t [ERROR] InnoDB: Table test/t contains 1 indexes inside InnoDB, which is different from the number of indexes 1 defined in the .frm file. See https://mariadb.com/kb/en/innodb-troubleshooting/
