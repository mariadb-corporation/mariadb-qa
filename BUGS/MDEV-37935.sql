SET sql_mode='';
SET SESSION autocommit=0;
SET SESSION enforce_storage_engine=Aria;
SET WSREP_OSU_METHOD = RSU;
CREATE TABLE t1 (a TEXT) ;
CREATE TABLE t2 (a TEXT) ;
SET SESSION autocommit=1;
REPLACE INTO t2 (a) SELECT /*!99997 */ a from t1;
