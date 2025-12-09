RENAME TABLE mysql.help_topic TO mysql.help_topic1;
CREATE VIEW mysql.help_topic AS SELECT * FROM mysql.help_topic1;
