#!/bin/bash
rm -f outcome.sql out
for i in $(seq 1 500); do
  echo "- Processing ${i}/500..."
  time ./generator.sh 10000
  cat out.sql >> outcome.sql
  wc -l outcome.sql
  rm out.sql
done
echo "- Done! Results saved in outcome.sql"
echo "NOTE: you may want to do:  $ sed -i 's|TokuDB|InnoDB|gi' outcome.sql  # Or, edit engines.txt and run generator.sh again"
