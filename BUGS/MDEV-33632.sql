# mysqld options required for replay:  --wsrep-provider=
SET GLOBAL wsrep_cluster_address='localhost';
SET GLOBAL wsrep_slave_threads=1;
