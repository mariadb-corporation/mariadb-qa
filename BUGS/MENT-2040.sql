SET SESSION pseudo_slave_mode=1;
XA START 'a';
SET @wsrep_cluster_address_saved=@@GLOBAL.wsrep_cluster_address;
XA END 'a';
XA PREPARE 'a';
SET GLOBAL wsrep_on=OFF;
SET GLOBAL wsrep_cluster_address=@wsrep_cluster_address_saved;
