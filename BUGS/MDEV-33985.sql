SELECT (WITH x(x) AS (SELECT 1) SELECT * FROM x WHERE (NEXTVAL(x)));

SET optimizer_switch=REPLACE (REPLACE (@@optimizer_switch,'=on','=off'),'in_to_exists=off','in_to_exists=on');
SELECT (WITH x (x) AS (SELECT 1) SELECT * FROM x WHERE (NEXTVAL (x)));
