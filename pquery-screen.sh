#!/bin/bash

if [ ! -z "${1}" ]; then screen -d -r $1; fi

screen -ls
