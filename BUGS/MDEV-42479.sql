# Requires /tmp/b.txt of 2147483649 bytes: perl -e 'print "a" x 1048576 for 1..2048; print "b"' > /tmp/b.txt
CREATE TABLE t1 (a INT);
LOAD DATA INFILE '/tmp/b.txt' INTO TABLE t1 CHARACTER SET binary (@b) SET a=1;
SELECT LOCATE('b',@b,2147483649);
#CLI: returns 0; expected 2147483649
#ERR: - (no error)

# Requires /tmp/b.txt of 3221225473 bytes: perl -e 'print "a" x 1048576 for 1..3072; print "b"' > /tmp/b.txt
CREATE TABLE t1 (a INT);
LOAD DATA INFILE '/tmp/b.txt' INTO TABLE t1 CHARACTER SET binary (@b) SET a=1;
SELECT LOCATE('b',@b), INSTR(@b,'b'), LOCATE('a',@b,3221225470);

# Requires /tmp/b.txt of 2147483649 bytes: perl -e 'print "a" x 1048576 for 1..2048; print "b"' > /tmp/b.txt
CREATE TABLE t1 (a INT);
LOAD DATA INFILE '/tmp/b.txt' INTO TABLE t1 CHARACTER SET binary (@b) SET a=1;
SELECT LENGTH(RPAD(@b,2147483648)), LENGTH(LPAD(@b,2147483648));
#CLI: returns 2147483647, 2147483647; expected 2147483648, 2147483648
#ERR: - (no error)

# Requires /tmp/b.txt of 2147483649 bytes: perl -e 'print "a" x 1048576 for 1..2048; print "b"' > /tmp/b.txt
CREATE TABLE t1 (a INT);
LOAD DATA INFILE '/tmp/b.txt' INTO TABLE t1 CHARACTER SET binary (@b) SET a=1;
SELECT LENGTH(SUBSTRING(@b FROM 2));
#CLI: returns 2147483647; expected 2147483648
#ERR: - (no error)
