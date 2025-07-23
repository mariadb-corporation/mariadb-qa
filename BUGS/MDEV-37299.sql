# mysqld options required for replay: --innodb_encrypt_tables=ON --plugin_load_add=file_key_management --file_key_management_filename=/home/ramesh/mariadb-qa/pquery/galera_encryption.key  --innodb-read-only=1
SET GLOBAL innodb_encryption_threads=4;
