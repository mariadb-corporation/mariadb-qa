#!/bin/bash

if [ ! -z "${1}" ]; then screen -d -r "${*}"; fi

#screen -ls
