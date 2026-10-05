#!/bin/sh
# Guest integration test for an on-demand Alpine FFmpeg installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX FFMPEG PACKAGE TEST"

if [ -e /usr/bin/ffmpeg ] || [ -e /usr/bin/ffprobe ]; then
	echo "FFmpeg was preinstalled; this test needs a clean base image" >&2
	exit 1
fi

i=0
while [ ! -s /etc/resolv.conf ] && [ "$i" -lt 60 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -s /etc/resolv.conf ]; then
	echo "DHCP did not install /etc/resolv.conf" >&2
	exit 1
fi

pkg install ffmpeg

test -x /usr/bin/ffmpeg
test -x /usr/bin/ffprobe
test -x /usr/bin/qt-faststart
ffmpeg -version | grep -q '^ffmpeg version '
echo "PASS pkg installed FFmpeg from Alpine"

# Encode generated frames with Alpine's native MPEG-4 encoder. This crosses
# libavfilter, libavcodec, libavformat, worker threads and filesystem output,
# catching substantially more Vinix ABI regressions than a version banner.
ffmpeg -hide_banner -loglevel error \
	-f lavfi -i 'testsrc2=size=64x48:rate=10:duration=1' \
	-c:v mpeg4 -threads 2 -y /tmp/vinix-ffmpeg-smoke.avi
test -s /tmp/vinix-ffmpeg-smoke.avi

probe=$(ffprobe -v error -select_streams v:0 \
	-show_entries stream=codec_name,width,height,nb_frames \
	-of csv=p=0 /tmp/vinix-ffmpeg-smoke.avi)
test "$probe" = 'mpeg4,64,48,10'
echo "PASS FFmpeg encoded and probed a 10-frame MPEG-4 video"
echo "VINIX FFMPEG PACKAGE TEST: PASS"
