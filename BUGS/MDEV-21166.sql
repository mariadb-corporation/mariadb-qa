CREATE FUNCTION mroonga_query_expand RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_query_expand ('a', 'a', 'a', 'a');

CREATE FUNCTION mroonga_normalize RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_normalize('a');

CREATE FUNCTION mroonga_command RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_command('a');

CREATE FUNCTION mroonga_escape RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_escape('+');

CREATE FUNCTION mroonga_highlight_html RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_highlight_html('a' AS query);

CREATE FUNCTION mroonga_snippet_html RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_snippet_html('a','','');
