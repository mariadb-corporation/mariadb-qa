CREATE TEMPORARY TABLE tmp (a timestamp null on update current_timestamp(6), b int);
ALTER TABLE tmp FORCE;
INSERT INTO tmp VALUES (NULL,1);
UPDATE tmp SET b = 2;
