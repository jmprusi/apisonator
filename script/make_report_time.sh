#!/bin/sh
shift  # get rid of the '-c' supplied by make.

if [ "$(uname)" = "Linux" ]; then
        \command time -o bench.txt -a -f "[%E] : $*" -- sh -c "$*"
else
        # As other commands refer to the bench.txt file, we create it
        # to avoid failures.
        touch bench.txt
        \command time sh -c "$*"
fi
