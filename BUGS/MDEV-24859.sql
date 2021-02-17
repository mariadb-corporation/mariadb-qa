# mysqld options required for replay:  --log_bin_trust_function_creators=1
SET sql_mode='';
DELIMITER //
CREATE FUNCTION f (arg CHAR(1)) RETURNS VARCHAR(1) BEGIN DECLARE v1 VARCHAR(1);DECLARE v2 VARCHAR(1);SET v1=CONCAT (LOWER (arg),UPPER (arg));SET v2=CONCAT (LOWER (v1),UPPER (v1));INSERT INTO t VALUES(v1), (v2);RETURN CONCAT (LOWER (arg),UPPER (arg));END;//
DELIMITER ;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TEMPORARY TABLE t (c DEC);
INSERT INTO t SELECT f (1);

# mysqld options required for replay:  --log_bin_trust_function_creators=1
SET sql_mode='';
DELIMITER //
CREATE FUNCTION f () RETURNS INT BEGIN INSERT INTO t VALUES(1);RETURN 1;END; //
DELIMITER ;
CREATE TEMPORARY TABLE t(c INT);
INSERT INTO t SELECT f();
