SET SESSION wsrep_osu_method=RSU;
CREATE FUNCTION fun1(x INT,y INT) RETURNS INT RETURN x;
SELECT 1;
SET GLOBAL wsrep_cluster_address=DEFAULT;

SET GLOBAL wsrep_provider_options='gmcast.isolate=1';
CREATE TABLE t(id int);
SET GLOBAL wsrep_provider_options='pc.bootstrap=1';
SET @@global.wsrep_cluster_address=default;
