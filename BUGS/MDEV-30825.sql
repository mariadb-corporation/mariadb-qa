SET GLOBAL innodb_checksum_algorithm=1, innodb_compression_algorithm=0;
CREATE TABLE t (c INT) page_compressed=1 page_compression_level=4 ENGINE=InnoDB;
SHUTDOWN;
