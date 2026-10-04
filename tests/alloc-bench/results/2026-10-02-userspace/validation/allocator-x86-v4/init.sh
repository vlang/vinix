#!/bin/sh
exec >/dev/com1 2>&1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /proc
echo UALLOC-VERIFY-BEGIN
gcc --version | head -n1
gcc -dM -E - </dev/null | grep __clang__ && exit 1
sha256sum /root/verify.c
sha256sum /root/clock.c
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin /root/clock.c -o /root/clock || {
    echo CLOCK-FAIL stage=compile
    while :; do sleep 60; done
}
/root/clock || {
    echo CLOCK-FAIL stage=run
    while :; do sleep 60; done
}
for policy in optimized disabled; do
    cp /root/libcs/$policy/libc.so /lib/.vinix-libc.new || exit 1
    chmod 755 /lib/.vinix-libc.new
    mv -f /lib/.vinix-libc.new /lib/ld-musl-x86_64.so.1 || exit 1
    cp /root/libcs/$policy/libc.a /usr/lib/.vinix-libc.a.new || exit 1
    chmod 644 /usr/lib/.vinix-libc.a.new
    mv -f /usr/lib/.vinix-libc.a.new /usr/lib/libc.a || exit 1
    echo UALLOC-POLICY policy=$policy
    sha256sum /lib/ld-musl-x86_64.so.1 /usr/lib/libc.a /root/libcs/$policy/build.json
    for linkage in dynamic static; do
        extra=
        [ "$linkage" = static ] && extra=-static
        echo UALLOC-LINKAGE policy=$policy mode=$linkage
        gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread $extra /root/verify.c -o /root/verify || {
            echo UALLOC-FAIL stage=compile policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        /root/verify || {
            echo UALLOC-FAIL stage=run policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        echo UALLOC-ORIGINAL-COMPLETE policy=$policy mode=$linkage
        gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread $extra /root/verify-all-classes.c -o /root/verify-all-classes || {
            echo UALLOC-FAIL stage=supplemental-compile policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        /root/verify-all-classes || {
            echo UALLOC-FAIL stage=supplemental-run policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        echo UALLOC-MODE-COMPLETE policy=$policy mode=$linkage
    done
done
echo UALLOC-VERIFY-COMPLETE
while :; do sleep 60; done
