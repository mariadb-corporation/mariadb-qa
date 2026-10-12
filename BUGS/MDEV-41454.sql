SET @t= UNIX_TIMESTAMP(NOW(6));
SELECT LENGTH(REGEXP_REPLACE(REPEAT('a', 300000), 'a', 'b')) INTO @l;
SELECT ROUND(UNIX_TIMESTAMP(NOW(6)) - @t) AS s, @l;
#CLI: returns s=44, @l=300000; the same call on a binary string takes 0.06 s
#ERR: - (no error)

SET @t= UNIX_TIMESTAMP(NOW(6));
SELECT LENGTH(REGEXP_REPLACE(CONVERT(REPEAT('a', 300000) USING utf8mb4) COLLATE utf8mb4_bin, 'a', 'b')) INTO @l;
SELECT ROUND(UNIX_TIMESTAMP(NOW(6)) - @t) AS s, @l;
#CLI: returns s=39, @l=300000
#ERR: - (no error)

SET @t= UNIX_TIMESTAMP(NOW(6));
SELECT LENGTH(REGEXP_REPLACE(CONVERT(REPEAT('a', 300000) USING latin1), 'a', 'b')) INTO @l;
SELECT ROUND(UNIX_TIMESTAMP(NOW(6)) - @t) AS s, @l;
#CLI: returns s=35, @l=300000
#ERR: - (no error)
