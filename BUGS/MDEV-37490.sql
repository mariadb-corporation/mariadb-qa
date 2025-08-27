GRANT SELECT (USER) ON mysql.global_priv TO PUBLIC;
DELETE FROM mysql.global_priv;
FLUSH PRIVILEGES;
GRANT SELECT (USER) ON mysql.global_priv TO PUBLIC;
