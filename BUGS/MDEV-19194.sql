CREATE TABLE tx (pk INT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE t1 (a INT, CONSTRAINT fk FOREIGN KEY (a) REFERENCES tx(pk)) ENGINE=InnoDB;
ALTER IGNORE TABLE t1 DROP FOREIGN KEY fk, DROP FOREIGN KEY fk, ALGORITHM=COPY;

create table t1(f1 int not null, f2 int not null, key(f1))engine=innodb;
create table t2(f1 int not null, f2 int not null,foreign key `f1` (f1) references t1(f1))engine=innodb;
alter table t2 drop foreign key f1, drop foreign key f1, algorithm=copy;
