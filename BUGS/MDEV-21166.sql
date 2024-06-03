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

CREATE FUNCTION last_insert_grn_id RETURNS INTEGER SONAME 'ha_mroonga.so';
SELECT last_insert_grn_id();

CREATE FUNCTION mroonga_snippet RETURNS STRING SONAME 'ha_mroonga.so';
SELECT mroonga_snippet ('',0,0,'',0,0,'','','','','');  # UBSAN, or
SELECT mroonga_snippet ('',0,0, 0,0,0,'','','','','');  # UBSAN + SIGSEGV

CREATE FUNCTION last_insert_grn_id RETURNS INT SONAME 'ha_mroonga.so';
SELECT last_insert_grn_id();
