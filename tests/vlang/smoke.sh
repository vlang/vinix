#!/bin/sh
set -eu

echo "compiler: $(v version)"
echo "commit:   $(cat /usr/lib/vlang/VERSION)"
tcc -v
rm -rf /tmp/v-smoke-test
mkdir -p /tmp/v-smoke-test
cp /root/v-smoke.v /tmp/v-smoke-test/hi.v
cd /tmp/v-smoke-test

# Exercise the ordinary one-command driver path developers use. This must let
# V select and invoke the guest's native C compiler itself; generating C and
# calling GCC separately would miss failures in V's compiler probe/launcher.
echo "compiling: v -gc none -nocache hi.v"
if ! v -gc none -nocache hi.v; then
	echo "V native compile command failed" >&2
	exit 1
fi
if [ ! -x ./hi ]; then
	echo "V native compile produced no executable" >&2
	exit 1
fi
echo "running: ./hi"
output=$(./hi) || {
	status=$?
	echo "V-compiled executable failed with status $status" >&2
	exit "$status"
}
printf '%s\n' "$output"
[ "$output" = 'V runs natively on Vinix' ] || {
	echo "V-compiled executable returned unexpected output" >&2
	exit 1
}
echo "V native compile smoke test passed"
