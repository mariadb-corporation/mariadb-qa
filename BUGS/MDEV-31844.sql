PREPARE s FROM "ALTER TABLE t modify b TEXT CHARACTER SET utf8 DEFAULT '' ";
SET @@character_set_collations='';
EXECUTE s;
