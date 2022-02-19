SET sql_mode='';
RENAME TABLE mysql.proxies_priv TO mysql.proxies_priv_bak;
CREATE TABLE mysql.proxies_priv ENGINE=InnoDB SELECT * FROM mysql.proxies_priv_bak;
GRANT PROXY ON grant_plug TO grant_plug_dest;
