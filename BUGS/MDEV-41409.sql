# mysqld options required for replay:  --max_allowed_packet=1073741824
SET @a= REPEAT(_latin1'a',1073741824);
SELECT CHAR_LENGTH(CONVERT(@a USING utf8mb4));
#CLI: returns 8; expected 1073741824 (optimized build; a debug build asserts)
#ERR: - (no error)
