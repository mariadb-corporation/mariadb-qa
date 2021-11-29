#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ -z "$(whereis bison | grep -o ':.*' | sed 's|:[ \t]*||')" ]; then 
  echo 'Run:  sudo apt install bison  # And then try again!'
  exit 1
fi

echo 'Compiling grammar... This takes about 5 seconds on a high end machine'
rm -f grammar.txt
#yacc -Wother -Wyacc -Wdeprecated -k -l --verbose sql/sql_yacc.yy
yacc -Wother -Wyacc -Wdeprecated --verbose sql/sql_yacc.yy 2>/dev/null
rm -f y.tab.c
sed '/^Terminals, with rules/,$d' y.output > grammar.tmp
rm -f y.output
grep '^[ \t]\+[0-9]\+' grammar.tmp \
 | sed 's|\t| |g;s|^[ ]\+[0-9]\+[ ]*||;s| [ ]\+| |g' \
 | grep --binary-files=text -v '^$@[0-9]\+: %empty' \
 | sed 's|$@[0-9]\+[ ]*||g' \
 | sed "s|'('|(|g;s|')'|)|g;s|','|,|g;s|'\.'|.|g;s|'+'|+|g;s|'-'|-|g;s|'/'|/|g;s|'%'|%|g;s|'!'|!|g;s|'<'|<|g;s|'>'|>|g;s|'{'|{|g;s|'}'|}|g;s|'~'|~|g;s|'@'|@|g;s|'='|=|g;s|'^'|^|g;s/'|'/|/g;s|'\&'|\&|g;s|':'|:|g;s|';'|;|g;s|'\*'|ASTERIX|g" \
 > grammar.txt
rm -f grammar.tmp
echo "Generated grammar.txt with $(wc -l grammar.txt | sed 's| .*||') lines"
