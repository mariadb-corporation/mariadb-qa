SET collation_connection=ucs2_general_ci;
CREATE TABLE t2 (c1 DOUBLE PRIMARY KEY,c2 ENUM('aaaaaaaaaaaaaaaaaaaaaaaaaaaa','bbbbbbbbbbbbbbbbbbbbbbbbbbbbb','cccccccccccccccccccccccccccc') CHARACTER SET 'Binary' COLLATE 'Binary',c3 SET('aaaaaaaaaaaaaaaaaaaaaaaaaaaa','bbbbbbbbbbbbbbbbbbbbbbbbbbbbb','cccccccccccccccccccccccccccc'));
