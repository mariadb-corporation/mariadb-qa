CREATE TABLE t (c INT);
INSERT INTO t VALUES (1);
FLUSH TABLES;
perl;
open my $f, '+<', "$ENV{MYSQLTEST_VARDIR}/mysqld.1/data/test/t.frm"; seek $f, 39, 0; print $f chr(0x20); close $f;
EOF
SELECT * FROM t;
