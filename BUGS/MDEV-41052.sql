  CREATE TABLE t (pk INT PRIMARY KEY, filler CHAR(255) NOT NULL DEFAULT '', g GEOMETRY NOT NULL, SPATIAL KEY spt(g)) ENGINE=InnoDB;
  INSERT INTO t (pk,g) SELECT seq, POINT(seq,seq) FROM seq_1_to_20000;
  SET GLOBAL innodb_lru_scan_depth=1024;
  DELIMITER $$
  CREATE PROCEDURE p(n INT)
  BEGIN
    WHILE n > 0 DO
      ALTER TABLE t FORCE;
      SELECT COUNT(*) FROM t FORCE INDEX(spt) WHERE MBRWithin(g, ST_GeomFromText('POLYGON((-1 -1,-1 99999,99999 99999,99999 -1,-1 -1))'));
      SET n = n - 1;
    END WHILE;
  END$$
  DELIMITER ;
  SET debug_dbug='+d,row_merge_instrument_log_check_flush';
  CALL p(10);
  SET debug_dbug='';
  CHECK TABLE t EXTENDED;
