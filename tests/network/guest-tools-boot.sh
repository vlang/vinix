#!/bin/sh
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=linux
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export XBPS_ARCH=aarch64

echo "VINIX NETWORK CLIENT INTEGRATION TEST"

i=0
while [ ! -s /etc/resolv.conf ] && [ "$i" -lt 100 ]; do
    sleep 1
    i=$((i + 1))
done
if [ ! -s /etc/resolv.conf ]; then
    echo "DHCP did not install /etc/resolv.conf" >&2
    exit 1
fi

VINIX_NETWORK_SMOKE_URL=http://10.0.2.2:18080/ok \
    /root/network-tools-smoke.sh

curl --fail --silent --show-error --max-time 30 \
    https://example.com/ > /tmp/example.html
grep -q 'Example Domain' /tmp/example.html
echo "PASS curl DNS/HTTPS"

git ls-remote https://github.com/vlang/vc.git HEAD > /tmp/git-head
grep -q 'HEAD' /tmp/git-head
echo "PASS git smart HTTPS"

# The host test server is deliberately not SSH. Reaching its invalid banner
# proves that the real OpenSSH client completed a TCP connection through lwIP.
if ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=10 \
    -p 18080 10.0.2.2 </dev/null >/tmp/ssh.out 2>/tmp/ssh.err; then
    echo "SSH unexpectedly accepted the HTTP endpoint" >&2
    exit 1
fi
if ! grep -Eq 'banner|identification|protocol|Connection closed' /tmp/ssh.err; then
    cat /tmp/ssh.err >&2
    echo "SSH did not reach the host endpoint" >&2
    exit 1
fi
echo "PASS OpenSSH TCP client"

apk update
echo "PASS APK repository sync"
xbps-install -S
echo "PASS XBPS repository sync"

echo "VINIX NETWORK CLIENT INTEGRATION TEST: PASS"
exec /bin/sh
