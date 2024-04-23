CREATE FUNCTION f(c INT) RETURNS BLOB RETURN 0;
CREATE PROCEDURE p(IN c INT) SELECT f('a');
CALL p(0);
CALL p(0);

SET MAX_JOIN_SIZE=2;
SET @doc:=sys.ps_thread_trx_info(@ps_thread_id);  # Succeeds
SET @doc:=sys.ps_thread_trx_info(@ps_thread_id);  # Crashes
