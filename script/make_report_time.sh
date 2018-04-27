#!/bin/sh
shift  # get rid of the '-c' supplied by make.

touch bench.txt
sh -c "$*"
