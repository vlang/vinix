#!/bin/sh
set -eu

echo "VINIX ARM64 NETWORK TOOLS TEST"
curl --version
git --version
ssh -V
apk --version
xbps-query --version

if [ -n "${VINIX_NETWORK_SMOKE_URL:-}" ]; then
    echo "fetching $VINIX_NETWORK_SMOKE_URL"
    body="$(curl --fail --silent --show-error "$VINIX_NETWORK_SMOKE_URL")"
    test "$body" = "vinix-network-ok"
fi

echo "VINIX ARM64 NETWORK TOOLS TEST: PASS"
