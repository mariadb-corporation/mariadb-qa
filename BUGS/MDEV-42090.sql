CREATE FUNCTION sphinx_snippets RETURNS STRING SONAME 'ha_sphinx.so';
SELECT sphinx_snippets(NULL,'idx','word');
