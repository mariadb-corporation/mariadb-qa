SELECT HOST,USER,PASSWORD FROM mysql.user ORDER BY HOST,USER,PASSWORD;

SELECT * FROM mysql.user ORDER BY authentication_string;

SELECT * FROM mysql.user ORDER BY HOST,USER,PASSWORD;

SELECT * FROM mysql.user ORDER BY HOST,USER,authentication_string;
