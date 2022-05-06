SET autocommit=FALSE;
ALTER TABLE mysql.columns_priv ENGINE=InnoDB;
FLUSH PRIVILEGES;
