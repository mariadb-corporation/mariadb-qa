SET GLOBAL join_buffer_space_limit=4095;
SET join_buffer_space_limit=DEFAULT;
CREATE TEMPORARY TABLE t (e INT,c CHAR(100),c2 CHAR(100),PRIMARY KEY(e),INDEX a(c)) ENGINE=InnoDB;
INSERT INTO t SELECT a.* FROM t a,t b,t c,t d,t e;
