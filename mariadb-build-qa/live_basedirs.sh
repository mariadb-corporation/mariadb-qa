#!/bin/bash

grep -o 'port=[0-9]\+' */start | sed 's|.*=||' | xargs -I{} echo "ps -ef | grep 'port={}' | grep -v grep" | xargs -I{} bash -c "{}"
