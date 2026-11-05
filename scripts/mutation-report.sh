#!/bin/bash
# mutation-report.sh <log of make mutate>: a Markdown report for the job's summary, from the lines each mutation
# printed, so a run stopped early still reports what it got through.
log=$1
count() { grep -c "^$1 " "$log" 2>/dev/null; }

caught=$(count caught)
survived=$(count survived)
echo "## Mutation testing"
if ! grep -q " mutations built and tested: " "$log" 2>/dev/null; then
    echo
    echo "**This run didn't finish, so these counts are partial.**"
fi
echo
echo "${caught:-0} caught, ${survived:-0} survived."
if [ "${survived:-0}" -gt 0 ]; then
    echo
    echo "Survivors, each needing a test, a deletion or a \`mutate:ignore\`:"
    echo
    grep "^survived " "$log" | sed -E 's/^survived +/- /'
fi
