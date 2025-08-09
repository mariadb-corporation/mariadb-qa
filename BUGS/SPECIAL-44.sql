CREATE TABLE t (id INT) ENGINE=MEMORY;
INSERT INTO t SELECT 1 FROM seq_1_to_128,seq_1_to_32768 b;
# CLI: ERROR 1114 (HY000): The table 't' is full
# ERR: [ERROR] mariadbd: The table 't' is full
