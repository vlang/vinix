#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Apple's installed libraries are behavioral references only. No Apple library
# is copied into the runner, guest, or repository.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/reference"}
mkdir -p "$output"
"${IOS_CLANGXX:-clang++}" -DIOS_CXX_REFERENCE -std=c++17 -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/cxx-extended.cpp" -o "$output/cxx-extended"
"$output/cxx-extended"
python3 - "$output/cxx-extended" <<'PY'
import signal
import subprocess
import sys
result = subprocess.run([sys.argv[1], "abort"], capture_output=True)
assert result.returncode == -signal.SIGABRT, (result.returncode, result.stderr)
assert b"IOS-CXX-ABORT: stack 17 1099511627776 2.500 0x1234\n" in result.stderr, result.stderr
print("IOS-CXX-REFERENCE: formatted diagnostic and SIGABRT")
PY
"${IOS_CLANG:-clang}" -DIOS_KEYCHAIN_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Security -framework Foundation "$repo/tests/ios/keychain.m" -o "$output/keychain"
"$output/keychain"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/common-crypto.c" -o "$output/common-crypto"
"$output/common-crypto"
"${IOS_CLANG:-clang}" -DIOS_QUEUE_REFERENCE -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/atomic-queue.c" -o "$output/atomic-queue"
"$output/atomic-queue"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/assertions.c" -o "$output/assertions"
"$output/assertions"
python3 - "$output/assertions" <<'PY'
import signal
import subprocess
import sys
for mode, expected in (("with-function", b"Assertion failed: (1 == 2), function fixture, file synthetic.c, line 17.\n"),
                       ("no-function", b"Assertion failed: (1 == 2), file synthetic.c, line 17.\n")):
    result = subprocess.run([sys.argv[1], mode], capture_output=True)
    assert result.returncode == -signal.SIGABRT, (mode, result.returncode, result.stderr)
    assert expected in result.stderr, result.stderr
print("IOS-ASSERT-REFERENCE: diagnostics and SIGABRT with/without function names")
PY
"${IOS_CLANG:-clang}" -DIOS_STACK_REFERENCE -O1 -fno-stack-protector -Wall -Wextra -Werror \
    "$repo/tests/ios/stack-probe.c" -o "$output/stack-probe"
"$output/stack-probe"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/libsystem-safety.c" -o "$output/libsystem-safety"
"$output/libsystem-safety"
python3 - "$output/libsystem-safety" <<'PY'
import signal
import subprocess
import sys
for mode in ("memcpy", "memmove", "memset", "strncpy", "strcat", "unterminated", "zero-capacity"):
    result = subprocess.run([sys.argv[1], mode], capture_output=True)
    assert result.returncode == -signal.SIGTRAP, (mode, result.returncode, result.stderr)
print("IOS-LIBSYSTEM-SAFETY-REFERENCE: seven genuine SIGTRAP overflow cases")
PY
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/runes.c" -o "$output/runes"
"$output/runes"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/sockets.c" -o "$output/sockets"
"$output/sockets"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/exit-handlers.c" -o "$output/exit-handlers"
"$output/exit-handlers"
exit_status=0
"$output/exit-handlers" explicit || exit_status=$?
test "$exit_status" = 7
exit_status=0
"$output/exit-handlers" immediate || exit_status=$?
test "$exit_status" = 8
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/numeric.c" -o "$output/numeric"
"$output/numeric"
"${IOS_CLANG:-clang}" -fno-builtin -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/nan.c" -o "$output/nan"
"$output/nan"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/poll.c" -o "$output/poll"
"$output/poll" --native-darwin
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/permissions.c" -o "$output/permissions"
test -L "$output/permissions-loop" || ln -s permissions-loop "$output/permissions-loop"
"$output/permissions" "$output/permissions-loop"
"${IOS_CLANG:-clang}" -DIOS_DISPATCH_REFERENCE -fblocks -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/dispatch.c" -o "$output/dispatch"
"$output/dispatch"
"${IOS_CLANG:-clang}" -DIOS_FCNTL_REFERENCE -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/fcntl.c" -o "$output/fcntl"
"$output/fcntl"
"${IOS_CLANG:-clang}" -DIOS_NETDB_REFERENCE -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/netdb.c" -o "$output/netdb"
"$output/netdb"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/interfaces.c" -o "$output/interfaces"
"$output/interfaces"
"${IOS_CLANG:-clang}" -DIOS_SYSTEM_QUERIES_REFERENCE -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/system-queries.c" -o "$output/system-queries"
"$output/system-queries"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/process.c" -o "$output/process"
"$output/process"
python3 - "$output/process" <<'PY'
import subprocess, sys
for mode, number in [("usr1", 30), ("usr2", 31), ("bus", 10)]:
    result = subprocess.run([sys.argv[1], mode], capture_output=True)
    assert result.returncode == -number, (mode, result.returncode, result.stdout, result.stderr)
print("IOS-PROCESS-REFERENCE: native Darwin SIGUSR1, SIGUSR2 and SIGBUS delivery")
PY
"${IOS_CLANG:-clang}" -DIOS_IOCTL_REFERENCE -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/ioctl.c" -o "$output/ioctl"
"$output/ioctl"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/calendar.c" -o "$output/calendar"
"$output/calendar" --native-darwin
"${IOS_CLANG:-clang}" -fno-objc-arc -O1 -Wall -Wextra -Werror -framework Security -framework Foundation \
    "$repo/tests/ios/security.m" -o "$output/security"
"$output/security"
"${IOS_CLANG:-clang}" -DIOS_TRUST_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Security -framework Foundation "$repo/tests/ios/security-trust.m" -o "$output/security-trust"
"$output/security-trust"
"${IOS_CLANG:-clang}" -DIOS_PROXY_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework CFNetwork -framework Foundation "$repo/tests/ios/cfnetwork.m" -o "$output/cfnetwork"
"$output/cfnetwork"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -framework Foundation -framework GameController \
    "$repo/tests/ios/game-constants.m" -o "$output/game-constants"
"$output/game-constants"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreGraphics \
    "$repo/tests/ios/geometry.c" -o "$output/geometry"
"$output/geometry"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreGraphics -framework CoreFoundation \
    "$repo/tests/ios/provider-images.c" -o "$output/provider-images"
"$output/provider-images"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework AudioToolbox \
    "$repo/tests/ios/audio-converter.c" -o "$output/audio-converter"
"$output/audio-converter"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework AudioToolbox \
    "$repo/tests/ios/audio-graph.c" -o "$output/audio-graph"
"$output/audio-graph"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$repo/tests/ios/colors.m" -o "$output/colors"
"$output/colors"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreFoundation \
    "$repo/tests/ios/core-foundation.c" -o "$output/core-foundation"
"$output/core-foundation"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit \
    "$repo/tests/ios/framework-constants.m" -o "$output/framework-constants"
"$output/framework-constants"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit \
    "$repo/tests/ios/accessibility.m" -o "$output/accessibility"
"$output/accessibility"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -framework Foundation \
    "$repo/tests/ios/objc-runtime.m" -o "$output/objc-runtime"
"$output/objc-runtime"
"${IOS_CLANG:-clang}" -DIOS_ARC_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Foundation "$repo/tests/ios/arc-registers.m" "$repo/tests/ios/arc-registers.S" \
    -o "$output/arc-registers"
"$output/arc-registers"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$repo/tests/ios/graphics.m" -o "$output/graphics-fixture"
"$output/graphics-fixture"
sh "$repo/tests/ios/reference-modules.sh" "$output"
