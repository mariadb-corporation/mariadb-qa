#!/bin/bash

grep -m1 BASEDIR= */*.conf | sed 's|  .*||;s|/pquery-pquery-run-MD.*conf:BASEDIR=|:|;s|\(.*\):\(.*\)|\2 \1|;' | sort
