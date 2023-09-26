CREATE TABLE t (c VARCHAR(1) CHARACTER SET utf32 COLLATE utf32_turkish_ci) ENGINE=MyISAM;
CALL sys.statement_performance_analyzer (1,1,1);
DROP TABLE t;
CREATE TABLE t (c INT) ENGINE=MyISAM;
SET sql_log_bin=1;
INSERT INTO t VALUES (1);
