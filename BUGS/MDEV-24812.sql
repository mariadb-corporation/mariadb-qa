DELIMITER //
CREATE FUNCTION f() RETURNS INT BEGIN SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE,READ ONLY;RETURN 1;END;//
DELIMITER ;
CREATE TABLE t(c DECIMAL(0));
INSERT INTO t VALUES(f());

# mysqld options required for replay:  --log_bin_trust_function_creators=1
DELIMITER //
CREATE FUNCTION f() RETURNS INT BEGIN SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE,READ ONLY;RETURN 1;END;//
DELIMITER ;
CREATE TABLE t(c DECIMAL(0));
INSERT INTO t VALUES(f());
