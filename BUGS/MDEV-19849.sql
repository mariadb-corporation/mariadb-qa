CREATE TABLE t (c CHAR(6)) CHARSET=utf8 ENGINE=InnoDB;
RENAME TABLE t TO t.t;  # Where database 't' does not exist
# Then observe in client ERROR 1025 (HY000): Error on rename of './test/t' to './t/t' (errno: 168 "Unknown (generic) error from engine")
