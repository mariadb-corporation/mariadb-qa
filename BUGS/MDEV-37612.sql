CREATE GLOBAL TEMPORARY TABLE t2 (c INT) ENGINE=MyISAM;
HANDLER t2 OPEN AS a2;  # ERROR 1180 (HY000): Got error 1 "Operation not permitted" during COMMIT on dbg+opt
SELECT 1;  # Immediately shows server lost on dbg, on opt it will complete. Opt seems to SIGSEGV on client exit
