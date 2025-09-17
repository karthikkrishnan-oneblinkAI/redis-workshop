#!/bin/bash

TIMEOUT="${TIMEOUT:-600}"
CODE="${CODE:-200}"
seconds=0
SLEEP="${SLEEP:-5}"

echo Waiting up to $TIMEOUT seconds for HTTP $CODE from $URL 
until [ "$seconds" -gt "$TIMEOUT" ]; do
  printf .
  req=( curl --silent --output /dev/null -k --max-time $TIMEOUT $EXTRAS -w '%{http_code}' --fail $URL )
  lastcode=$(${req[@]} | sed "s/'//g")
  if [ $lastcode -eq $CODE ]; then
     break
  fi
  sleep $SLEEP
  seconds=$((seconds+SLEEP))
done

if [ "$seconds" -lt "$TIMEOUT" ]; then
  echo OK after $seconds seconds
else
  echo "ERROR: Timed out wating for HTTP 200 from" $URL >&2
  exit 1
fi
