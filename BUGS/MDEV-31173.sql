SET @wsrep_cluster_address_orig=@@GLOBAL.wsrep_cluster_address;
SET wsrep_on=0;
INSERT INTO mysql.wsrep_allowlist (ip) VALUES (0);
SET GLOBAL wsrep_cluster_address=@wsrep_cluster_address_orig;
SELECT 1;
