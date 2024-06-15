CREATE TABLE t (c1 INT KEY,c2 INT,FOREIGN KEY(c2) REFERENCES t (c1) ON DELETE CASCADE) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,0),(2,1),(3,2),(4,3),(5,4),(6,5),(7,6),(8,7),(9,8),(10,9),(11,10),(12,11),(13,12),(14,13),(15,14);
DELETE FROM t;
# CLI: ERROR 1296 (HY000): Got error 193 '`test`.`t`, CONSTRAINT `t_ibfk_1` FOREIGN KEY (`c2`) REFERENCES `t` (`c1`) ON DELETE CASCADE' from InnoDB
# ERR: [ERROR] InnoDB: Cannot delete/update rows with cascading foreign key constraints that exceed max depth of 15. Please drop excessive foreign constraints and try again
