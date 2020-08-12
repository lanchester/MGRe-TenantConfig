#!/bin/bash

PID_FILE=/rails/tmp/pids/server.pid

if [[ -f $PID_FILE ]]; then
    rm $PID_FILE
fi

bundle exec rails s -p 3000 -b 0.0.0.0
