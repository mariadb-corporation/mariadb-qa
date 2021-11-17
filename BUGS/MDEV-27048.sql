CREATE TABLE t (a INT,b INT,c INT,x TEXT,y TEXT,z TEXT,id INT UNSIGNED AUTO_INCREMENT,i INT,KEY(id),UNIQUE KEY a (a,b,c));
ALTER TABLE t ADD CONSTRAINT test UNIQUE (id) USING HASH;

# Also: mariadb-install-db startup produces this issue (ref MDEV-27048 report)
