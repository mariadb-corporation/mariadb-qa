# mysqld options required for replay: --log-bin
CREATE EVENT e ON SCHEDULE AT CURRENT_TIMESTAMP DO ALTER TABLE tp EXCHANGE PARTITION p WITH TABLE t;
DUMMY_ERROR;
SET GLOBAL event_scheduler=ON;
RESET MASTER TO 5000000000;
SELECT SLEEP(2);  # Not required; shows server crashed
