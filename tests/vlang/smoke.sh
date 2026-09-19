#!/bin/sh
set -eu

echo "compiler: $(v version)"
echo "commit:   $(cat /usr/lib/vlang/VERSION)"
v -new-compiler -no-memory-limit -os linux -arch arm64 -gc none \
	-o /tmp/v-smoke.c /root/v-smoke.v
gcc -static -O2 -fno-stack-protector -w /tmp/v-smoke.c -lm -o /tmp/v-smoke
/tmp/v-smoke | grep -Fx 'V runs natively on Vinix'
echo "V native compile smoke test passed"
