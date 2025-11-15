CREATE FUNCTION f(c INT) RETURNS BLOB RETURN 0;
CREATE PROCEDURE p(IN c INT) SELECT f('a');
CALL p(0);
CALL p(0);

SET MAX_JOIN_SIZE=2;
SET @doc:=sys.ps_thread_trx_info(@ps_thread_id);  # Succeeds
SET @doc:=sys.ps_thread_trx_info(@ps_thread_id);  # Crashes

CREATE FUNCTION f() RETURNS BLOB RETURN 1;
DELIMITER //
CREATE DEFINER=root@localhost PROCEDURE p (a INT,b INT) BEGIN DECLARE v INT DEFAULT f (5);IF(f (6)) THEN SELECT'';END IF;SET v=f (7);while f (8)<1 DO SELECT'';END while;END; //
DELIMITER ;
CALL p (-1,1);
CALL p (-1,1);  # Asserts, in bb-12.2-serg only
