# Requires /tmp/b.txt of 2147483649 bytes: perl -e 'print "a" x 1048576 for 1..2048; print "b"' > /tmp/b.txt
CREATE TABLE t1 (a INT);
LOAD DATA INFILE '/tmp/b.txt' INTO TABLE t1 CHARACTER SET binary (@b) SET a=1;
SELECT @b > '', STRCMP(@b,'');
#CLI: 0, -1; expected 1, 1
#ERR: - (no error)
