DROP DATABASE test;
SET SESSION collation_server=filename;
CREATE DATABASE test;
USE test;
CREATE TABLE t (c CHAR BINARY);

DROP DATABASE test;
SET SESSION collation_server=filename;
CREATE DATABASE test;
USE test;
CREATE TABLE t0 (c ENUM ('') BINARY);
