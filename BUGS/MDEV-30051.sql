CREATE TABLE t(c INT) ENGINE=InnoDB;
SELECT * FROM t AS v NATURAL JOIN t AS w GROUP BY c HAVING c AND(SELECT (c=1 AND (((1 +''/ 0) AND ''=FALSE) OR c='')));

CREATE TABLE t (c BLOB) ENGINE=InnoDB;
SELECT * FROM t AS v NATURAL JOIN t AS w GROUP BY c HAVING c AND (SELECT (c=1 AND (( (1 +''/ 0) AND''=FALSE) OR c='')));