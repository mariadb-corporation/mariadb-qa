CREATE TABLE t1 (
  id int primary key,value varchar(2),
  vcomplete int AS (cast(substr(value,1,1) as int)),
  va int AS (null),vb int AS (null),vc int AS (null),
  vresult char(1) AS (substr(value,2)),
  KEY key1(vresult,vcomplete)
) ENGINE=InnoDB; 
BEGIN;
INSERT INTO t1(id,value) VALUES (1,'0F');
UPDATE t1 SET value = '1S';
UPDATE t1 SET value = '0F';
COMMIT;
SET GLOBAL innodb_max_purge_lag_wait=0;

CREATE TABLE t1 (
  id int primary key,
  value varchar(200),
  vcomplete int AS (json_extract(value,'$.complete')) STORED,
  va int AS (json_extract(value,'$.a')),
  vb int AS (json_extract(value,'$.b')) ,
  vc int AS (json_extract(value,'$.c')) ,
  vresult varchar(20) AS (json_extract(value,'$.result')) ,
  KEY key1 (vresult,vcomplete)
) ENGINE=InnoDB;
BEGIN;
INSERT INTO t1(id,value) VALUES (1,'{"complete": 0,"result": "FAILURE"}');
UPDATE t1 SET value = '{"complete": 1,"result": "SUCCESS"}';
UPDATE t1 SET value = '{"complete": 0,"result": "FAILURE"}';
COMMIT;
SET GLOBAL innodb_max_purge_lag_wait=0;
