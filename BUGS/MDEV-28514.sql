CREATE TABLE t0 (b INT,c INT,d BIT,v BIT AS (d) VIRTUAL,KEY(b,v)) ENGINE=MyISAM PARTITION BY HASH (b);
CHECK TABLE t0;