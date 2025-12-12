# mysqld options required for replay:  --plugin-load-add=hashicorp_key_management.so --hashicorp-key-management-vault-url=http://127.0.0.1:8200/v1/my_test
INSTALL PLUGIN test_sql_service SONAME 'test_sql_service';
SET GLOBAL innodb_default_encryption_key_id=4;
