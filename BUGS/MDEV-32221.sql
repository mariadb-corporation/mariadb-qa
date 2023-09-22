set global event_scheduler=1;
ALTER TABLE mysql.event ENGINE=InnoDB;
CREATE EVENT e_x2 ON SCHEDULE EVERY 1 SECOND DO DROP TABLE x_t;
