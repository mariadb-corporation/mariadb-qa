SET GLOBAL innodb_log_archive=ON;
SET GLOBAL innodb_file_per_table=0;
CREATE TABLE t1 (b VARCHAR(8000)) STATS_PERSISTENT=0;
SET GLOBAL innodb_trx_purge_view_update_only_debug=ON;
SET GLOBAL debug_dbug='+d,ib_log_checkpoint_avoid';
SET debug_dbug='+d,skip_page_checksum';
INSERT INTO t1 SELECT REPEAT('x', 8000) FROM seq_1_to_10000;
SET GLOBAL innodb_log_checkpoint_now=ON;
DELIMITER //
BEGIN NOT ATOMIC
  WHILE (@r:= 2 * @@innodb_log_file_size - 12304 - (SELECT variable_value FROM information_schema.global_status WHERE variable_name='INNODB_LSN_CURRENT')) >= 3000 DO
    INSERT INTO t1 VALUES (REPEAT('x', LEAST(8000, @r - 2500)));
  END WHILE;
  WHILE @r > @r MOD 10 * 11 DO SET GLOBAL innodb_fil_make_page_dirty_debug=0, @r=@r-10; END WHILE;
  SET GLOBAL innodb_saved_page_number_debug=1000;
  WHILE @r > 0 DO SET GLOBAL innodb_fil_make_page_dirty_debug=0, @r=@r-11; END WHILE;
END//
DELIMITER ;
SET GLOBAL debug_dbug='';
check table t1 ;
