# export UBSAN_OPTIONS=print_stacktrace=1
# rm -Rf /test/UBASAN_MD151121-mariadb-10.8.0-linux-x86_64-dbg/data
# /test/UBASAN_MD151121-mariadb-10.8.0-linux-x86_64-dbg/scripts/mariadb-install-db --no-defaults --force --auth-root-authentication-method=normal  ${MYEXTRA_OPT} --basedir=/test/UBASAN_MD151121-mariadb-10.8.0-linux-x86_64-dbg --datadir=/test/UBASAN_MD151121-mariadb-10.8.0-linux-x86_64-dbg/data

CREATE TABLE t (a INT,b INT,c INT,x TEXT,y TEXT,z TEXT,id INT UNSIGNED AUTO_INCREMENT,i INT,KEY(id),UNIQUE KEY a (a,b,c));
ALTER TABLE t ADD CONSTRAINT test UNIQUE (id) USING HASH;
