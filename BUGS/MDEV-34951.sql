CREATE OR REPLACE TABLE t1 (a INT,b INT,KEY(a),KEY(b));
ALTER TABLE t1 RENAME KEY b TO B;
DELETE FROM t1;

CREATE TABLE t (c INT UNIQUE) ENGINE=InnoDB;
ALTER TABLE t RENAME KEY c TO C;
ALTER TABLE t MODIFY C INT;
SHOW WARNINGS;
# CLI: 2x warning similar to 'Warning | 1082 | InnoDB: Table test/t contains 2 indexes inside InnoDB, which is different from the number of indexes 1 defined in the MariaDB'
# ERR: 2x error similar to '[ERROR] InnoDB: Table test/t contains 2 indexes inside InnoDB, which is different from the number of indexes 1 defined in the .frm file. See https://mariadb.com/kb/en/innodb-troubleshooting/'
