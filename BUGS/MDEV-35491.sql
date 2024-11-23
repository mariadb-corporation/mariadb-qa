CREATE TABLE t (a INT,b VARCHAR(512),c VARCHAR(16),PRIMARY KEY(a),INDEX (b (512))) KEY_BLOCK_SIZE=2;
#CLI: ERROR 1118 (42000): Row size too large (> 8126). Changing some columns to TEXT or BLOB may help. In current row format, BLOB prefix of 0 bytes is stored inline.
#ERR: [ERROR] InnoDB: Cannot add field `b` in table `test`.`t` because after adding it, the row size is 2053 which is greater than maximum allowed size (1922 bytes) for a record on index leaf page.
# Bug: message incostency
