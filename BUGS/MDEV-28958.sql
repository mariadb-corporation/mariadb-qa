CREATE TABLE c(c INT) ENGINE=InnoDB;
SELECT * FROM(SELECT * FROM c GROUP BY NOT c=c) AS c NATURAL JOIN c AS c GROUP BY c HAVING c=c OR c=c;
