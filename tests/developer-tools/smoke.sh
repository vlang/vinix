#!/bin/sh
set -eu

export PATH=/aarch64-linux-musl-native/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export CC=gcc

work=/tmp/vinix-developer-tools
rm -rf "$work"
mkdir -p "$work"
cd "$work"

echo "VINIX NATIVE DEVELOPER TOOLS TEST"

git --version
make --version
cmake --version
ninja --version
pkg-config --version
autoconf --version
automake --version
file --version
python3 -c 'import fcntl; print("Python fcntl module available")'

test "$(printf '%s\n' vinix | sed 's/vinix/pipe-ok/')" = pipe-ok
echo "PASS shell pipeline EOF"

libtool --version
gdb --version
strace --version

cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) { puts("hello from a Vinix native build"); return 0; }
EOF
cat > Makefile <<'EOF'
hello: hello.c
	$(CC) -g -o $@ $<
EOF
make
test "$(./hello)" = "hello from a Vinix native build"
echo "PASS GNU make native C build"

git init -q
git config user.name Vinix
git config user.email developer@vinix.local
git add hello.c Makefile
git commit -qm initial
test "$(git rev-parse --is-inside-work-tree)" = true
test "$(git log -1 --format=%s)" = initial
echo "PASS Git repository and commit"

mkdir cmake-src
cp hello.c cmake-src/
cat > cmake-src/CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(vinix_cmake C)
add_executable(cmake-hello hello.c)
EOF
cmake -S cmake-src -B cmake-build -G Ninja
cmake --build cmake-build
test "$(cmake-build/cmake-hello)" = "hello from a Vinix native build"
ctest --test-dir cmake-build
echo "PASS CMake and Ninja native build"

mkdir meson-src
cp hello.c meson-src/
cat > meson-src/meson.build <<'EOF'
project('vinix-meson', 'c')
executable('vinix-meson-hello', 'hello.c')
EOF
meson setup meson-build meson-src
meson compile -C meson-build
test "$(meson-build/vinix-meson-hello)" = "hello from a Vinix native build"
echo "PASS Meson and Ninja native build"

mkdir -p pkg/lib/pkgconfig
cat > pkg/lib/pkgconfig/vinix-smoke.pc <<EOF
prefix=$work/pkg
Name: vinix-smoke
Description: pkg-config smoke package
Version: 1.2.3
Libs: -L\${prefix}/lib -lvinix-smoke
Cflags: -I\${prefix}/include
EOF
PKG_CONFIG_PATH="$work/pkg/lib/pkgconfig" pkg-config \
    --atleast-version=1.2.0 vinix-smoke
test "$(PKG_CONFIG_PATH="$work/pkg/lib/pkgconfig" \
    pkg-config --modversion vinix-smoke)" = 1.2.3
echo "PASS pkg-config metadata lookup"

mkdir autotools
cd autotools
cp ../hello.c .
cat > configure.ac <<'EOF'
AC_INIT([vinix-autotools], [1.0])
AC_PROG_CC
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
EOF
autoconf
test -s configure
./configure --help >/dev/null
automake --help >/dev/null
libtool --help >/dev/null
echo "PASS Autoconf generation and Automake/Libtool startup"
cd ..

cp hello.c hello.patched.c
printf '%s\n' '--- hello.patched.c' '+++ hello.patched.c' \
    '@@ -1,2 +1,2 @@' ' #include <stdio.h>' \
    '-int main(void) { puts("hello from a Vinix native build"); return 0; }' \
    '+int main(void) { puts("patched on Vinix"); return 0; }' > hello.patch
patch < hello.patch
grep -q 'patched on Vinix' hello.patched.c
diff -u hello.c hello.patched.c > hello.diff || test $? -eq 1
test -s hello.diff
echo "PASS patch and diffutils"

tmux_socket=vinix-smoke-$$
tmux -L "$tmux_socket" -f /dev/null new-session -d -s smoke \
    'printf "tmux pane ready\\n"; exec sleep 30'

# Starting a detached server exercises the UNIX-domain control socket. Its
# first pane also makes tmux allocate a Unix98 PTY and launch a shell command
# behind it. Wait for the command's output rather than relying on a scheduler
# race between the server and this client.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    pane_output="$(tmux -L "$tmux_socket" capture-pane -p -t smoke 2>/dev/null || true)"
    case "$pane_output" in
        *'tmux pane ready'*) break ;;
    esac
    sleep 1
done
case "$pane_output" in
    *'tmux pane ready'*) ;;
    *)
        tmux -L "$tmux_socket" kill-server 2>/dev/null || true
        echo "tmux pane did not produce its expected output" >&2
        exit 1
        ;;
esac
tmux -L "$tmux_socket" has-session -t smoke
tmux -L "$tmux_socket" kill-server
echo "PASS tmux server, UNIX socket, and PTY pane"

echo "PASS file, GDB, and strace startup"

echo "VINIX NATIVE DEVELOPER TOOLS TEST: PASS"
