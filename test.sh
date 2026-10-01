#!/usr/bin/env bash
# Smoke tests for agent-semaphore. Run: ./test.sh

set -uo pipefail

cd "$(dirname "$0")"
sem=$PWD/agent-semaphore
export AGENT_SEMAPHORE_DIR
AGENT_SEMAPHORE_DIR=$(mktemp -d)
work=$(mktemp -d)
trap 'rm -rf "$AGENT_SEMAPHORE_DIR" "$work"' EXIT

failed=0
check() {
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$3', got '$2'"
    failed=1
  fi
}

# Each job records how many jobs were running alongside it.
job='n=$(ls '"$work"'/running | wc -l); echo $n >>'"$work"'/peaks; sleep 1; rm '"$work"'/running/$$'
mkdir "$work/running"
for _ in 1 2 3 4 5; do
  "$sem" -n limit -c 2 -p 1 -q 'touch '"$work"'/running/$$; '"$job" &
done
wait
check "runs every command" "$(wc -l <"$work/peaks" | tr -d ' ')" 5
check "never exceeds the slot count" "$(sort -n "$work/peaks" | tail -1)" 2

"$sem" -n exit -c 1 'exit 7'
check "passes the exit status through" $? 7

check "runs argv directly" "$("$sem" -n argv -c 1 printf '%s|' 'a b' c)" "a b|c|"

check "does not queue behind itself" "$("$sem" -n nested -c 1 -t 3 "$sem" -n nested -c 1 -t 3 echo inner)" inner

"$sem" -n names-a -c 1 sleep 2 &
sleep 0.5
check "names are independent" "$("$sem" -n names-b -c 1 -t 1 echo free)" free
wait

"$sem" -n busy -c 1 sleep 3 &
sleep 0.5
"$sem" -n busy -c 1 -t 1 -p 1 -q true 2>/dev/null
check "times out with 75" $? 75
check "status shows the holder" "$("$sem" --status -n busy | sed -n 1p)" "busy: 1/1 busy"
wait
check "status shows the slot free again" "$("$sem" --status -n busy | sed -n 1p)" "busy: 0/1 busy"

"$sem" -n held -c 1 'sleep 2 & disown'
"$sem" -n held -c 1 -t 1 -p 1 -q true 2>/dev/null
check "slot stays held while children live" $? 75
sleep 2

exit $failed
