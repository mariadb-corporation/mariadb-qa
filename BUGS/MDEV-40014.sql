# Ref bug report for full MTR testcase
CREATE DATABASE `stress_sdb0`;
CREATE DATABASE `stress_sdb1`;
CREATE TABLE `stress_sdb1`.`t2` (id INT AUTO_INCREMENT PRIMARY KEY, val VARCHAR(50));
CREATE USER 'stress_su3'@'localhost';
GRANT SELECT ON `stress_sdb0`.* TO 'stress_su3'@'localhost';
GRANT SELECT ON `stress_sdb1`.`t2` TO 'stress_su3'@'localhost';
DENY EVENT, EXECUTE, CREATE ON `stress_sdb0`.* TO 'stress_su3'@'localhost';
DENY UPDATE (val) ON `stress_sdb1`.`t2` TO 'stress_su3'@'localhost';
REVOKE DENY CREATE, CREATE TEMPORARY TABLES, EXECUTE ON `stress_sdb0`.* FROM 'stress_su3'@'localhost';
SHOW GRANTS FOR 'stress_su3'@'localhost';
