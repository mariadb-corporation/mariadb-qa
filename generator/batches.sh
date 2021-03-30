#!/bin/bash
rm -f outcome.sql out
for i in $(seq 1 500); do
  echo "- Processing ${i}/500..."
  time ./generator.sh 10000
  cat out.sql >> outcome.sql
  wc -l outcome.sql
  rm out.sql
done
echo "- Done!"
