# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_encryption_rotation_iops=1;

# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_encryption_rotate_key_age=1;
