SET GLOBAL wsrep_cluster_address=AUTO;
SET GLOBAL wsrep_slave_threads=12;  # Will thread_hang in CLI

SET GLOBAL wsrep_cluster_address=ON;
SET GLOBAL wsrep_slave_threads=0;
