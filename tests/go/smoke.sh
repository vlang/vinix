#!/bin/sh
set -eu

export PATH=/usr/lib/go/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export GOROOT=/usr/lib/go
export GOCACHE=/tmp/go-cache
export CGO_ENABLED=0

rm -rf "$GOCACHE" /tmp/go-smoke /tmp/go-cgo
mkdir -p "$GOCACHE"

go version
go env GOOS GOARCH GOROOT
gofmt -d /root/go-smoke.go /root/go-cgo.go
go build -o /tmp/go-smoke /root/go-smoke.go
/tmp/go-smoke

if command -v gcc >/dev/null 2>&1; then
	CGO_ENABLED=1 CC=gcc go build -o /tmp/go-cgo /root/go-cgo.go
	/tmp/go-cgo
else
	echo "GCC absent; skipping cgo smoke test"
fi
