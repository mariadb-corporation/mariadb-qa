# mysqld options required for replay:  --server-id=100
CREATE GLOBAL TEMPORARY TABLE t ON COMMIT PRESERVE ROWS ENGINE=MyISAM AS VALUES (5),(6),(7);
SET GLOBAL server_id=1;
TRUNCATE t;  # Causes thread-hang
