SET SQL_MODE='';
SET max_session_mem_used=0;
CREATE TABLE t (a INT) ENGINE=none;

SET SESSION query_alloc_block_size=0;
SET SESSION max_session_mem_used=0;
ANALYZE TABLE db.tbl;
