# As of Oct 2025, SQL alike to:
CREATE OR REPLACE TABLE mysql.procs_priv (id INT);
CREATE USER plug_user IDENTIFIED WITH test_plugin_server AS'';
# CLI: ERROR 1728 (HY000): Cannot load from mysql.procs_priv. The table is probably corrupted
# ERR: [ERROR] mariadbd: Cannot load from mysql.procs_priv. The table is probably corrupted
