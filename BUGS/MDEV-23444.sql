SET div_precision_increment= 0;
SELECT * FROM (SELECT AVG(@x := 0)) sq;

SET SESSION div_precision_increment=0;
SELECT * FROM (SELECT WEEKDAY (0)/0) AS a0;

SET SESSION div_precision_increment=-2;
SELECT * FROM (SELECT AVG(@x :=0)) sq;
