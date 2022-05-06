SET GLOBAL wsrep_provider_options='repl.max_ws_size=512';
CREATE TABLE t1 (c1 int);
CREATE TABLE t2 (c2 int);
CREATE TRIGGER tr AFTER INSERT ON t1 FOR EACH ROW UPDATE t2 SET t2.c2 = t2.c2+1;
DROP TABLE t1;
FLUSH TABLE t1;
