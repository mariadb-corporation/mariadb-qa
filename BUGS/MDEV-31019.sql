SET lc_time_names=111;
SELECT MONTHNAME('2010-12-12');

SET lc_time_names=111;
SET TIMESTAMP=1040000000;
SELECT MAKETIME(0,0,0)+MONTHNAME(CURRENT_TIMESTAMP());