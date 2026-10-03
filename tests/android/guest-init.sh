#!/bin/sh
# Isolated APK smoke boot. The host stops this guest after capturing its screen.
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root USER=root LOGNAME=root SHELL=/bin/sh TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export XDG_RUNTIME_DIR=/run/user/0
. /opt/android-test/config.sh
export VINIX_ANDROID_EXPECTED_RESULT VINIX_ROBLOX_APK VINIX_ANDROID_LINKER_DIAGNOSTICS

application_logs() {
    [ "${TEST_INTERACTIVE:-0}" = 1 ] && return
    for log in /tmp/android-boot-probe.log /tmp/android-launch.log /tmp/android-desktop.log /tmp/android-text.log \
        /tmp/vinix-"$TEST_HOSTED_NAME"-*.log /run/vinix-hosted-x11/vinix-"$TEST_HOSTED_NAME"-*.log; do
        [ -f "$log" ] || continue
        echo "ANDROID-LOG $log"
        if [ "${1:-}" = full ]; then
            # Native-library load errors can sit between the progress head
            # and abort tail. Keep the complete bounded startup on failure.
            head -c 262144 "$log"
        else
            head -100 "$log"
        fi
        echo "ANDROID-LOG-TAIL $log"
        tail -40 "$log"
        if [ "${1:-}" = full ]; then
            echo "ANDROID-NATIVE-LOAD-DIAGNOSTICS $log"
            grep -E 'LoadNativeLibrary|JNI_OnLoad|dlopen|UnsatisfiedLinkError|Exception' "$log" | tail -80
        fi
        if [ "$TEST_STRACE" = 1 ]; then
            echo "ANDROID-MAPPING-TRACE $log"
            grep -E 'mmap\(|mremap\(|mprotect\(|madvise\(' "$log" | tail -120
        fi
    done
}
diagnostics() {
    [ "${TEST_INTERACTIVE:-0}" = 1 ] && return
    echo ANDROID-DIAGNOSTICS-BEGIN
    uname -a
    ps
    cat /proc/meminfo
    application_logs full
    echo ANDROID-DIAGNOSTICS-END
}
fail() {
    echo "ANDROID-FAIL $*"
    diagnostics
    if [ "${TEST_INTERACTIVE:-0}" = 1 ]; then
        while :; do sleep 30; done
    fi
    exec /bin/sh </dev/console >/dev/console 2>&1
}

mkdir -p /tmp/.X11-unix /run/user/0 /dev/shm /var/log /var/lib/xkb
chmod 1777 /tmp /tmp/.X11-unix /dev/shm
# ART's launcher touches six MiB of its main stack before entering Java.
ulimit -s 32768 || fail "cannot raise the ART main stack limit"
echo ANDROID-START
uname -a
VINIX_ALLOW_WX=1 /opt/android-test/memory-probe || fail "native ART memory prerequisites failed"
if [ "$TEST_RUNTIME_ARCH" = x86_64 ]; then
    runtime=/opt/vinix-android-x86_64
    (
        unset LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        for probe in runtime-stack-probe runtime-memory-probe; do
            /usr/bin/qemu-x86_64 -s 33554432 -B 0x100000000 -L "$runtime" \
                -E "LD_LIBRARY_PATH=$runtime/lib:$runtime/usr/lib" \
                -E "LD_PRELOAD=$runtime/usr/lib/libvinix-android-compat.so" \
                "$runtime/lib/ld-musl-x86_64.so.1" "/opt/android-test/$probe" || exit 1
        done
    ) || fail "translated ART stack or memory prerequisites failed"
else
    runtime=/opt/vinix-android-aarch64
    (
        unset LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib"
        loader="$runtime/lib/ld-musl-aarch64.so.1"
        # Record musl's original initial-stack metadata before requiring the
        # runtime's correction against this same process mapping contract.
        "$loader" --library-path "$LD_LIBRARY_PATH" /opt/android-test/runtime-stack-probe
        echo "ANDROID-STACK-RAW status=$?"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        for probe in runtime-stack-probe runtime-memory-probe runtime-atfork-probe; do
            "$loader" --library-path "$LD_LIBRARY_PATH" "/opt/android-test/$probe" || exit 1
        done
        "$loader" --library-path "$runtime/lib:$runtime/usr/lib:$runtime/usr/lib/art" \
            "$runtime/usr/libexec/vinix-android/atl-configuration-test" || exit 1
        "$loader" --library-path "$LD_LIBRARY_PATH" /opt/android-test/runtime-fortify-probe \
            "$runtime/usr/lib/libvinix-android-compat.so" "$runtime/usr/lib/libc_bio.so.0" || exit 1
        "$loader" --library-path "$LD_LIBRARY_PATH" /opt/android-test/runtime-mallinfo-probe \
            "$runtime/usr/lib/libvinix-android-compat.so" || exit 1
        "$loader" --library-path "$LD_LIBRARY_PATH" /opt/android-test/runtime-netdb-probe \
            "$runtime/usr/lib/libc_bio.so.0" || exit 1
    ) || fail "native ART stack, memory, fork callback, configuration, fortified I/O, allocator or netdb prerequisites failed"
fi
if [ -n "${TEST_ART_BOOT_PROBE:-}" ]; then
    [ "$TEST_RUNTIME_ARCH" = aarch64 ] || fail "Java bootclasspath probe requires native ARM64 ART"
    [ -f "$TEST_ART_BOOT_PROBE" ] || fail "Java bootclasspath probe is missing"
    echo ANDROID-BOOTCLASSPATH-START
    (
        runtime=/opt/vinix-android-aarch64
        loader="$runtime/lib/ld-musl-aarch64.so.1"
        unset ANDROID_ROOT ANDROID_DATA LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib:$runtime/usr/lib/art:$runtime/usr/lib/java/dex/art/natives"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        for icu_data_file in "$runtime"/usr/share/icu/*/icudt*l.dat; do
            if [ -f "$icu_data_file" ]; then
                export ICU_DATA="${icu_data_file%/*}"
                break
            fi
        done
        exec "$loader" --library-path "$LD_LIBRARY_PATH" "$runtime/usr/bin/dalvikvm" \
            -Xnoimage-dex2oat -Xusejit:false -cp "$TEST_ART_BOOT_PROBE" ArtBootProbe
    ) >/tmp/android-boot-probe.log 2>&1 || fail "native Java bootclasspath probe failed"
    cat /tmp/android-boot-probe.log
    grep -q '^ANDROID-BOOTCLASSPATH-PASS ' /tmp/android-boot-probe.log \
        || fail "native Java bootclasspath probe did not report its assertions passing"
    echo ANDROID-BOOTCLASSPATH-VERIFIED
fi
if [ -n "${TEST_LAYOUT_PROBE:-}" ]; then
    echo ANDROID-LAYOUT-FOCUS-START
    (
        runtime=/opt/vinix-android-aarch64
        unset ANDROID_ROOT ANDROID_DATA LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib:$runtime/usr/lib/art:$runtime/usr/lib/java/dex/art/natives"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        framework="$runtime/usr/lib/java/dex/android_translation_layer"
        for icu_data_file in "$runtime"/usr/share/icu/*/icudt*l.dat; do
            if [ -f "$icu_data_file" ]; then
                export ICU_DATA="${icu_data_file%/*}"
                break
            fi
        done
        exec "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" \
            "$runtime/usr/bin/dalvikvm" -Xnoimage-dex2oat -Xusejit:false \
            -cp "$TEST_LAYOUT_PROBE:$framework/api-impl.jar:$framework/gstub.jar:$framework/ghax.jar" \
            android.view.AndroidLayoutFocusProbe
    ) >/tmp/android-layout-focus-probe.log 2>&1 || {
        cat /tmp/android-layout-focus-probe.log
        fail "native framework layout focus probe failed"
    }
    cat /tmp/android-layout-focus-probe.log
    grep -q '^ANDROID-LAYOUT-FOCUS-PASS ' /tmp/android-layout-focus-probe.log \
        || fail "native framework layout focus probe did not report its assertions passing"
    echo ANDROID-LAYOUT-FOCUS-VERIFIED
fi
if [ -n "${TEST_POINTER_PROBE:-}" ]; then
    echo ANDROID-POINTER-CAPTURE-START
    (
        runtime=/opt/vinix-android-aarch64
        unset ANDROID_ROOT ANDROID_DATA LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib:$runtime/usr/lib/art:$runtime/usr/lib/java/dex/art/natives"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        framework="$runtime/usr/lib/java/dex/android_translation_layer"
        for icu_data_file in "$runtime"/usr/share/icu/*/icudt*l.dat; do
            if [ -f "$icu_data_file" ]; then
                export ICU_DATA="${icu_data_file%/*}"
                break
            fi
        done
        exec "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" \
            "$runtime/usr/bin/dalvikvm" -Xnoimage-dex2oat -Xusejit:false \
            -cp "$TEST_POINTER_PROBE:$framework/api-impl.jar:$framework/gstub.jar:$framework/ghax.jar" \
            android.view.AndroidPointerCaptureProbe
    ) >/tmp/android-pointer-capture-probe.log 2>&1 || {
        cat /tmp/android-pointer-capture-probe.log
        fail "native framework pointer capture probe failed"
    }
    cat /tmp/android-pointer-capture-probe.log
    grep -q '^ANDROID-POINTER-CAPTURE-PASS ' /tmp/android-pointer-capture-probe.log \
        || fail "native framework pointer capture probe did not report its assertions passing"
    echo ANDROID-POINTER-CAPTURE-VERIFIED
fi
if [ -n "${TEST_LIFECYCLE_PROBE:-}" ]; then
    echo ANDROID-ACTIVITY-LIFECYCLE-START
    rm -f /tmp/android-lifecycle-status
    mkfifo /tmp/android-lifecycle-events
    (while :; do sleep 30; done) >/tmp/android-lifecycle-events &
    lifecycle_input_pid=$!
    /usr/bin/vinix-wine-host :98 /tmp/android-activity-lifecycle-probe 128x128x24 \
        /opt/android-test/lifecycle-launch --fill \
        </tmp/android-lifecycle-events >/tmp/android-activity-lifecycle-probe.log 2>&1 || {
        kill "$lifecycle_input_pid" 2>/dev/null || true
        cat /tmp/android-activity-lifecycle-probe.log
        fail "native framework activity lifecycle probe failed"
    }
    kill "$lifecycle_input_pid" 2>/dev/null || true
    wait "$lifecycle_input_pid" 2>/dev/null || true
    rm -f /tmp/android-lifecycle-events
    cat /tmp/android-activity-lifecycle-probe.log
    [ "$(cat /tmp/android-lifecycle-status 2>/dev/null)" = 0 ] \
        || fail "native framework activity lifecycle probe did not exit successfully"
    grep -q '^ANDROID-ACTIVITY-LIFECYCLE-PASS ' /tmp/android-activity-lifecycle-probe.log \
        || fail "native framework activity lifecycle probe did not report its assertions passing"
    echo ANDROID-ACTIVITY-LIFECYCLE-VERIFIED
fi
if [ -n "${TEST_BIONIC_LOADER_PROBE:-}" ]; then
    (
        runtime=/opt/vinix-android-aarch64
        unset LD_LIBRARY_PATH LD_PRELOAD
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        export BIONIC_LD_LIBRARY_PATH="$TEST_BIONIC_LOADER_PROBE"
        "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" \
            "$TEST_BIONIC_LOADER_PROBE/loader-test" "$runtime/usr/lib/libdl_bio.so.0" \
            "$TEST_BIONIC_LOADER_PROBE/packed-relocation-probe.so"
    ) || fail "packed relocations or nested native loader callbacks failed"
    echo ANDROID-BIONIC-LOADER-VERIFIED
fi
[ -x /usr/bin/run-android ] || fail "run-android is missing"
[ -f "$TEST_APK" ] || fail "APK is missing: $TEST_APK"

if [ "$TEST_DESKTOP_APP" = Roblox ] || [ -n "${TEST_TLS_PROBE:-}" ]; then
    # DHCP publishes the resolver file asynchronously. Launching the online
    # client before that write can cache a failed first lookup in Java.
    i=0
    while ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null; do
        [ "$i" -lt 30 ] || fail "guest DHCP did not publish DNS configuration"
        sleep 1
        i=$((i + 1))
    done
    echo "ANDROID-NETWORK-READY wait_seconds=$i"
fi

if [ -n "${TEST_TLS_PROBE:-}" ]; then
    echo ANDROID-TLS-START
    (
        runtime=/opt/vinix-android-aarch64
        unset ANDROID_ROOT ANDROID_DATA LD_LIBRARY_PATH LD_PRELOAD
        export VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib:$runtime/usr/lib/art:$runtime/usr/lib/java/dex/art/natives"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        for icu_data_file in "$runtime"/usr/share/icu/*/icudt*l.dat; do
            if [ -f "$icu_data_file" ]; then
                export ICU_DATA="${icu_data_file%/*}"
                break
            fi
        done
        exec "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" \
            "$runtime/usr/bin/dalvikvm" -Xnoimage-dex2oat -Xusejit:false \
            "-Djavax.net.ssl.trustStore=$runtime/etc/ssl/certs/java/cacerts" \
            -Djavax.net.ssl.trustStoreType=JKS -Djavax.net.ssl.trustStorePassword=changeit \
            -cp "$TEST_TLS_PROBE" AndroidTlsProbe
    ) >/tmp/android-tls-probe.log 2>&1 || {
        cat /tmp/android-tls-probe.log
        fail "native Java HTTPS trust probe failed"
    }
    cat /tmp/android-tls-probe.log
    grep -q '^ANDROID-TLS-PASS ' /tmp/android-tls-probe.log \
        || fail "native Java HTTPS trust probe did not report its assertions passing"
    echo ANDROID-TLS-VERIFIED
fi

if [ "$TEST_MODE" = direct ]; then
    mkfifo /tmp/android-events
    # Keep the bridge input pipe alive without sending invented events.
    (while :; do sleep 30; done) >/tmp/android-events &
    /usr/bin/vinix-wine-host :99 /tmp/vinix-android-direct "$TEST_GEOMETRY" \
        /opt/android-test/launch --fill </tmp/android-events >/tmp/android-launch.log 2>&1 &
    app_pid=$!
else
    printf '%s\n' version=1 name=564d kdf=scrypt n=16384 r=8 p=1 \
        salt=00000000000000000000000000000000 \
        hash=0000000000000000000000000000000000000000000000000000000000000000 \
        >/root/.vinix-user
    chmod 600 /root/.vinix-user
    /usr/bin/vinix-desktop --open="$TEST_DESKTOP_APP" </dev/console >/tmp/android-desktop.log 2>&1 &
    app_pid=$!
fi

display=
surface=
resumed=0
[ "$TEST_WAIT_FOR_RESUME" = 0 ] && resumed=1
i=0
while [ "$i" -lt "$TEST_TIMEOUT" ]; do
    kill -0 "$app_pid" 2>/dev/null || fail "application host exited"
    for candidate in /tmp/vinix-"$TEST_HOSTED_NAME"-* /run/vinix-hosted-x11/vinix-"$TEST_HOSTED_NAME"-*; do
        [ -f "$candidate/Xvfb_screen0" ] && surface="$candidate"
    done
    for socket in /tmp/.X11-unix/X*; do
        [ -S "$socket" ] || continue
        candidate_display=":${socket#/tmp/.X11-unix/X}"
        if /opt/android-test/x11-probe "$candidate_display" inspect "$TEST_TITLE" >/tmp/android-window.log 2>&1; then
            display=$candidate_display
            break
        fi
    done
    if [ "$resumed" = 0 ]; then
        for log in /tmp/android-launch.log /tmp/vinix-"$TEST_HOSTED_NAME"-*.log \
            /run/vinix-hosted-x11/vinix-"$TEST_HOSTED_NAME"-*.log; do
            [ -f "$log" ] || continue
            if grep -q 'onPostResume - yay!' "$log"; then
                echo ANDROID-ACTIVITY-RESUMED
                resumed=1
                break
            fi
        done
    fi
    [ -n "$display" ] && [ -n "$surface" ] && [ "$resumed" = 1 ] && break
    if [ "$i" -gt 0 ] && [ $((i % 15)) -eq 0 ]; then
        echo "ANDROID-WAIT elapsed=$i"
        application_logs
    fi
    sleep 1
    i=$((i + 1))
done
[ -n "$display" ] && [ -n "$surface" ] && [ "$resumed" = 1 ] \
    || fail "APK did not finish starting within ${i}s"
if [ "$TEST_OBSERVE" = 0 ]; then
    [ -s /tmp/android-text.log ] || fail "test text observer was not loaded"
fi
cat /tmp/android-window.log
if [ -n "${TEST_EGL_PROBE:-}" ]; then
    echo ANDROID-EGL-START
    (
        runtime=/opt/vinix-android-aarch64
        unset LD_LIBRARY_PATH LD_PRELOAD
        export DISPLAY="$display" VINIX_ALLOW_WX=1
        export LD_LIBRARY_PATH="$runtime/lib:$runtime/usr/lib"
        export LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so"
        export GDK_BACKEND=x11 GDK_DISABLE="${GDK_DISABLE:+$GDK_DISABLE,}glx" GSK_RENDERER=cairo
        export GTK_A11Y=none GSETTINGS_BACKEND=memory
        export FONTCONFIG_PATH="$runtime/etc/fonts" FONTCONFIG_FILE="$runtime/etc/fonts/fonts.conf"
        export GSETTINGS_SCHEMA_DIR="$runtime/usr/share/glib-2.0/schemas"
        export LIBGL_DRIVERS_PATH="$runtime/usr/lib/dri"
        exec "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" "$TEST_EGL_PROBE"
    ) >/tmp/android-egl-probe.log 2>&1 || {
        cat /tmp/android-egl-probe.log
        fail "native EGL and GTK texture probe failed"
    }
    cat /tmp/android-egl-probe.log
    grep -q '^ANDROID-EGL-PASS ' /tmp/android-egl-probe.log \
        || fail "native EGL and GTK texture probe did not report its assertions passing"
    echo ANDROID-EGL-VERIFIED
fi
echo "ANDROID-SURFACE $surface/Xvfb_screen0"
echo "ANDROID-DISPLAY $display"
if [ "$TEST_MODE" = direct ]; then
    /opt/android-test/x11-probe "$display" present >/tmp/android-present.log 2>&1 &
fi
rm -f /tmp/android-result
echo ANDROID-READY
if [ "${TEST_INTERACTIVE:-0}" = 1 ]; then
    echo "ANDROID-INTERACTIVE functionality=unchecked"
    # The desktop owns /dev/console for its keyboard. A second shell on that
    # console would consume the user's login input. Keep init quiet instead.
    while kill -0 "$app_pid" 2>/dev/null; do sleep 1; done
    fail "application host exited during interactive session"
fi
if [ "$TEST_OBSERVE" = 1 ]; then
    i=0
    while [ "$i" -lt "$TEST_OBSERVATION_SECONDS" ]; do
        kill -0 "$app_pid" 2>/dev/null || fail "application host exited during observation"
        /opt/android-test/x11-probe "$display" inspect "$TEST_TITLE" >/tmp/android-window.log 2>&1 \
            || fail "APK window disappeared or stopped drawing"
        sleep 1
        i=$((i + 1))
    done
    cat /tmp/android-window.log
    diagnostics
    echo "ANDROID-OBSERVED seconds=$i functionality=unchecked"
    exec /bin/sh </dev/console >/dev/console 2>&1
fi
if [ "$TEST_INPUT" = xtest ]; then
    /opt/android-test/x11-probe "$display" type "$TEST_TITLE" "$TEST_KEYS" "$TEST_FOCUS_X" "$TEST_FOCUS_Y" \
        || fail "keyboard input failed"
fi

i=0
last_input=
while [ "$i" -lt 240 ]; do
    kill -0 "$app_pid" 2>/dev/null || fail "application host exited during arithmetic"
    if [ -f /tmp/android-input ]; then
        actual_input=$(cat /tmp/android-input)
        if [ "$actual_input" != "$last_input" ]; then
            printf 'ANDROID-INPUT %s\n' "$actual_input"
            last_input=$actual_input
        fi
    fi
    if [ -f /tmp/android-result ] && [ "$(cat /tmp/android-result)" = "$VINIX_ANDROID_EXPECTED_RESULT" ]; then
        echo "ANDROID-ARITHMETIC expected=$VINIX_ANDROID_EXPECTED_RESULT"
        /opt/android-test/x11-probe "$display" inspect "$TEST_TITLE" || fail "APK stopped drawing"
        diagnostics
        echo ANDROID-PASS
        exec /bin/sh </dev/console >/dev/console 2>&1
    fi
    sleep 1
    i=$((i + 1))
done
fail "APK did not display arithmetic result $VINIX_ANDROID_EXPECTED_RESULT"
