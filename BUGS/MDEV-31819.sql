# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_encryption_rotation_iops=1;

# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_encryption_rotate_key_age=1;

# mysqld options required for replay:  --innodb-read-only=1
SET GLOBAL innodb_encryption_rotation_iops=0;
# ERR: safe_mutex: Trying to lock uninitialized mutex at /test/11.6_dbg/storage/innobase/fil/fil0crypt.cc, line 2198
