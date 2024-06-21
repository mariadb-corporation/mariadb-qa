DROP DATABASE test
SHUTDOWN
SET @@global.wsrep_cluster_address=AUTO
RENAME.*TABLE.*mysql\..*TO
ALTER.*TABLE.*mysql\.
DROP.*TABLE.*mysql\.
SET.*GLOBAL.*wsrep_cluster_address
