SET SESSION wsrep_on=OFF;
SET default_storage_engine=MYISAM;
CREATE SEQUENCE t;
SET SESSION wsrep_on=ON;
CREATE INDEX idx ON t (a);

SET default_storage_engine='MYISAM';
CREATE SEQUENCE t INCREMENT BY 0 CACHE=0 ENGINE=InnoDB;
CREATE INDEX c ON t (c);
