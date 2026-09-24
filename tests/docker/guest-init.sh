#!/bin/sh
# PID 1 for the automated Docker VM test (run-aarch64.sh --guest-init).
export HOME=/root
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export TERM=linux

echo
echo "VINIX DOCKER TEST: START"
if /root/docker-smoke.sh; then
	echo "VINIX DOCKER TEST: PASS"
else
	echo "VINIX DOCKER TEST: FAIL"
fi
sync
/sbin/poweroff -f 2>/dev/null
exec /bin/sh
