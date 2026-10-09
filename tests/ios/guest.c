// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void fail(const char *message) {
    printf("iOS FAIL: %s\n", message);
    fflush(stdout);
    for (;;) pause();
}

static void run_program(int native, const char *image, const char *left, const char *op,
                        const char *right, int expected_status, const char *expected_output) {
    int descriptors[2];
    if (pipe(descriptors)) fail("pipe");
    pid_t child = fork();
    if (child < 0) fail("fork");
    if (!child) {
        close(descriptors[0]);
        if (dup2(descriptors[1], 1) < 0 || dup2(descriptors[1], 2) < 0) _exit(126);
        close(descriptors[1]);
        char *arguments[] = { "/opt/ios/run-ios", (char *)image,
            (char *)left, (char *)op, (char *)right, NULL };
        execv(native ? image : arguments[0], native ? arguments + 1 : arguments);
        _exit(127);
    }
    close(descriptors[1]);
    char output[32768];
    size_t length = 0;
    for (;;) {
        ssize_t count = read(descriptors[0], output + length, sizeof(output) - length - 1);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) fail("read");
        if (!count) break;
        length += (size_t)count;
        if (length == sizeof(output) - 1) fail("unexpected excessive output");
    }
    close(descriptors[0]);
    output[length] = 0;
    if (!strcmp(image, "--audit") &&
        (strstr(output, "IOS-CF:") || strstr(output, "IOS-GLES:") || strstr(output, "IOS-MODULES:")))
        fail("import audit executed application code");
    int status;
    while (waitpid(child, &status, 0) < 0) if (errno != EINTR) fail("waitpid");
    int status_matches = expected_status < 0 ? WIFSIGNALED(status) && WTERMSIG(status) == -expected_status :
        WIFEXITED(status) && WEXITSTATUS(status) == expected_status;
    if (!status_matches || !strstr(output, expected_output)) {
        printf("image=%s expression=%s %s %s status=%d output=%s\n", image,
            left ? left : "", op ? op : "", right ? right : "", status, output);
        fail("application result/status mismatch");
    }
    if (!strcmp(image, "/opt/ios/PPSSPP") && (!strstr(output, "SceneDelegate: Launching PPSSPP") ||
        !strstr(output, "V panic: iOS:") || (!strstr(output, "unimplemented") && !strstr(output, "unsupported") && !strstr(output, "not implemented"))))
        fail("PPSSPP did not reach scene launch or explicit unsupported API failure");
    printf("iOS RESULT: %s", output);
}

static void run(const char *image, const char *left, const char *op,
                const char *right, int expected_status, const char *expected_output) {
    run_program(0, image, left, op, right, expected_status, expected_output);
}

extern void test_uikit(void);
extern void test_2048(void);
extern void test_gles_ui(void);
extern void test_ppsspp_ui(void);

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (!access("/opt/ios/gles", R_OK)) {
        setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
        unsetenv("GALLIUM_DRIVER");
        setenv("MESA_SHADER_CACHE_DISABLE", "true", 1);
        run("--audit", "/opt/ios/gles", NULL, NULL, 0,
            "0 unresolved strong, 0 unresolved weak (app code was not executed)");
        run("/opt/ios/gles", NULL, NULL, NULL, 0,
            "IOS-GLES: native ES3 shader pixels, GLKView resize, depth/stencil, TLS and ARC teardown");
        puts("iOS PASS: native OpenGL ES shader rendering and GLKView lifecycle");
        test_gles_ui();
        run("/opt/ios/TextFixture.app/TextFixture", NULL, NULL, NULL, 0,
            "IOS-TEXT: registered font, traits, UTF-8, real metrics and clipped premultiplied glyph pixels\n");
        puts("iOS PASS: native CoreText fonts and bitmap glyph rendering");
        run("/opt/ios/compression", NULL, NULL, NULL, 0,
            "IOS-ZLIB: stream layout, native compression and iOS allocation callbacks\n");
        puts("iOS PASS: native zlib and Mach-O callbacks");
    }
    run("/opt/ios/arc-threads", NULL, NULL, NULL, 0,
        "IOS-ARC: eight threads, weak/deallocation races and isolated autorelease pools\n");
    puts("iOS PASS: thread-safe ARC and autorelease pools");
    run("/opt/ios/atomic-queue", NULL, NULL, NULL, 0,
        "IOS-ATOMIC-QUEUE: LIFO, generation, independent offsets and eight-thread node reuse");
    puts("iOS PASS: lock-free Darwin atomic queues and node reuse");
    run("/opt/ios/assertions", NULL, NULL, NULL, 0, "IOS-ASSERT: native assertion import");
    run("/opt/ios/assertions", "with-function", NULL, NULL, -SIGABRT,
        "Assertion failed: (1 == 2), function fixture, file synthetic.c, line 17.\n");
    run("/opt/ios/assertions", "no-function", NULL, NULL, -SIGABRT,
        "Assertion failed: (1 == 2), file synthetic.c, line 17.\n");
    puts("iOS PASS: Darwin assertion diagnostics and SIGABRT");
    run("/opt/ios/stack-probe", NULL, NULL, NULL, 0,
        "IOS-STACK-PROBE: 32 KiB frames, integer/FP arguments and eight native threads");
    puts("iOS PASS: Darwin stack probes preserve native arguments");
    run("/opt/ios/libsystem-safety", NULL, NULL, NULL, 0,
        "IOS-LIBSYSTEM-SAFETY: descriptor limits, unlimited bitmaps, overlap, padding and fortified strings");
    const char *overflow_modes[] = {"memcpy", "memmove", "memset", "strncpy", "strcat", "unterminated", "zero-capacity"};
    for (unsigned index = 0; index < sizeof(overflow_modes)/sizeof(*overflow_modes); index++)
        run("/opt/ios/libsystem-safety", overflow_modes[index], NULL, NULL, -SIGTRAP,
            "iOS: fortified operation exceeds destination");
    puts("iOS PASS: Darwin descriptor checks and fortified operations with SIGTRAP");
    run("/opt/ios/runes", NULL, NULL, NULL, 0,
        "IOS-RUNES: full Unicode fingerprints, C/UTF-8 locales, masks, digit values, widths and eight threads");
    puts("iOS PASS: Darwin Unicode rune flags and locale selection");
    run("/opt/ios/sockets", NULL, NULL, NULL, 0,
        "IOS-SOCKETS: IPv4/IPv6 TCP, UDP, socketpair, truncation, timeouts, flags, errors and eight threads");
    puts("iOS PASS: Darwin socket addresses, options and native network I/O");
    run("/opt/ios/exit-handlers", NULL, NULL, NULL, 0,
        "IOS-EXIT: main completed\nIOS-EXIT: mixed LIFO, reentrant registration, DSO filtering and eight threads");
    run("/opt/ios/exit-handlers", "explicit", NULL, NULL, 7,
        "IOS-EXIT: main completed\nIOS-EXIT: mixed LIFO, reentrant registration, DSO filtering and eight threads");
    run("/opt/ios/exit-handlers", "immediate", NULL, NULL, 8,
        "IOS-EXIT: immediate exit skips callbacks");
    puts("iOS PASS: image-scoped exit callbacks and real process termination");
    run("/opt/ios/mach-memory", NULL, NULL, NULL, 0,
        "IOS-MACH-VM: aliases, offsets, occupied targets, real errors and independent mapping lifetimes");
    puts("iOS PASS: native Mach VM aliases and mapping lifetime");
    const char *calculator = "/opt/ios/calculator";
    run(calculator, "7", "+", "5", 0, "IOS-CALCULATOR: 12\n");
    run(calculator, "3", "-", "9", 0, "IOS-CALCULATOR: -6\n");
    run(calculator, "2147483647", "*", "2147483647", 0, "IOS-CALCULATOR: 4611686014132420609\n");
    run(calculator, "81", "/", "9", 0, "IOS-CALCULATOR: 9\n");
    run(calculator, "23", "%", "7", 0, "IOS-CALCULATOR: 2\n");
    puts("iOS PASS: Mach-O arithmetic and libSystem imports");
    run("/opt/ios/calculator-legacy", "19", "+", "23", 0, "IOS-CALCULATOR: 42\n");
    run("/opt/ios/lifecycle", NULL, NULL, NULL, 0, "IOS-LIFECYCLE: destructor\n");
    puts("iOS PASS: legacy dyld imports and image/TLS lifecycle");
    run("/opt/ios/pointer-tags", NULL, NULL, NULL, 0,
        "IOS-POINTER-TAGS: relocated addresses and all high bytes preserved");
    run("/opt/ios/pointer-tags-legacy", NULL, NULL, NULL, 0,
        "IOS-POINTER-TAGS: relocated addresses and all high bytes preserved");
    puts("iOS PASS: native chained and legacy pointer tags");
    run("/opt/ios/core-foundation", NULL, NULL, NULL, 0,
        "IOS-CF: Unicode ranges, binary strings, collections, raw pointers, data growth, numbers and ownership");
    run("/opt/ios/core-foundation", "custom", NULL, NULL, 1,
        "custom CF collection callbacks are not implemented");
    puts("iOS PASS: native CoreFoundation conversion, data and collection ownership");
    run("/opt/ios/audio-converter", NULL, NULL, NULL, 0,
        "IOS-AUDIO-CONVERTER: real PCM samples, planar/interleaved layouts, callback errors/resume, EOF/reset and ownership");
    run("/opt/ios/audio-converter", "unsupported", NULL, NULL, 0,
        "IOS-AUDIO-CONVERTER: unsupported codecs/rates and invalid handles rejected");
    puts("iOS PASS: native PCM conversion and AudioToolbox callback ABI");
    run("/opt/ios/audio-graph", NULL, NULL, NULL, 0,
        "IOS-AUDIO-GRAPH: native callbacks, mixer gains, PCM conversion, errors/silence, offline start/stop and buffer ownership");
    run("/opt/ios/audio-graph", "hardware", NULL, NULL, 0,
        "IOS-AUDIO-GRAPH: hardware output and voice capture are unavailable");
    puts("iOS PASS: native offline AudioUnit graph rendering and mixer ownership");
    run("/opt/ios/colors", NULL, NULL, NULL, 0,
        "IOS-COLORS: precise components/equality, owned color spaces, UIKit caches, gray/RGB fill state and real pixels");
    puts("iOS PASS: native CoreGraphics color precision, fill state and ownership");
    run("/opt/ios/provider-images", NULL, NULL, NULL, 0,
        "IOS-PROVIDER-IMAGES: borrowed bytes, native release callbacks, retained CFData, RGB formats/decode, packed stack ABI and real pixels");
    puts("iOS PASS: native CoreGraphics providers, raw image formats and callback ownership");
    run("/opt/ios/geometry", NULL, NULL, NULL, 0,
        "IOS-GEOMETRY: native HFA arguments/results, constants, negative dimensions, half-open hit testing, null/empty edges and rectangle math");
    puts("iOS PASS: native CoreGraphics geometry and HFA calling conventions");
    run("/opt/ios/game-constants", NULL, NULL, NULL, 0,
        "IOS-GAME-CONSTANTS: 64-bit keyboard codes, notification strings and haptic localities match Mac libraries");
    puts("iOS PASS: native GameController typed key codes and string constants");
    run("/opt/ios/security", NULL, NULL, NULL, 0,
        "IOS-SECURITY: owned DER certificates, RSA/EC public keys, attributes, decode errors, typed constants and secure random bytes");
    puts("iOS PASS: native Security certificates, public keys, constants and random bytes");
    run("/opt/ios/security", NULL, NULL, NULL, 0,
        "IOS-SECURITY-POLICY: owned X.509 and SSL policies, client/hostname properties, equality and copied metadata");
    puts("iOS PASS: native Security X.509 and SSL policy ownership");
    run("/opt/ios/security-trust", NULL, NULL, NULL, 0,
        "IOS-SECURITY-TRUST: owned trust/key snapshots, explicit CA anchors, verify dates, negative decisions and cache invalidation");
    puts("iOS PASS: native Security explicit-anchor trust evaluation and key ownership");
    run("/opt/ios/cfnetwork", NULL, NULL, NULL, 0,
        "IOS-PROXY: typed HTTP proxy constants, configuration snapshots and owned settings");
    run("/opt/ios/cfnetwork", "invalid", NULL, NULL, 1,
        "iOS: HTTP proxy configuration is invalid or unsupported");
    puts("iOS PASS: native CFNetwork HTTP proxy settings and ownership");
    run("/opt/ios/keychain", NULL, NULL, NULL, 0,
        "IOS-KEYCHAIN: generic passwords, duplicate/update/delete, binary data, one/all results and ownership");
    for (int pass = 0; pass < 3; pass++) {
        const char *mode = pass == 0 ? "write" : pass == 1 ? "read" : "delete";
        run("/opt/ios/keychain", mode, NULL, NULL, 0,
            "IOS-KEYCHAIN: credential persisted across process restart");
    }
    pid_t writers[2];
    for (int i = 0; i < 2; i++) {
        writers[i] = fork();
        if (writers[i] < 0) fail("keychain writer fork");
        if (!writers[i]) {
            run("/opt/ios/keychain", "race", i ? "writer-two" : "writer-one", NULL, 0,
                "IOS-KEYCHAIN: concurrent credential writer completed");
            fflush(stdout);
            _exit(0);
        }
    }
    for (int i = 0; i < 2; i++) {
        int status;
        while (waitpid(writers[i], &status, 0) < 0) if (errno != EINTR) fail("keychain writer wait");
        if (!WIFEXITED(status) || WEXITSTATUS(status)) fail("keychain concurrent writer");
    }
    run("/opt/ios/keychain", "read-race", NULL, NULL, 0,
        "IOS-KEYCHAIN: concurrent credentials preserved");
    puts("iOS PASS: native keychain queries, ownership and persistent credentials");
    run("/opt/ios/common-crypto", NULL, NULL, NULL, 0,
        "IOS-CRYPTO: SHA digests, long-key HMAC, NIST AES CBC/ECB, padding, in-place buffers and error/size ABI");
    puts("iOS PASS: native CommonCrypto SHA, HMAC and AES calling conventions");
    run("/opt/ios/framework-constants", NULL, NULL, NULL, 0,
        "IOS-CONSTANTS: Foundation and UIKit strings, accessibility traits and typed scalars");
    puts("iOS PASS: native framework constants match installed Apple libraries");
    run("/opt/ios/accessibility", NULL, NULL, NULL, 0,
        "IOS-ACCESSIBILITY: disabled service queries, element metadata, HFA frames, weak containers and ARC ownership");
    puts("iOS PASS: native accessibility metadata and weak container lifecycle");
    run("/opt/ios/objc-runtime", NULL, NULL, NULL, 0,
        "IOS-OBJC-RUNTIME: canonical selectors, method encodings, inherited replacement, saved IMPs, HFA/stack ABI and dynamic class/ivar lifetimes");
    puts("iOS PASS: native Objective-C reflection, replacement and dynamic classes");
    run("/opt/ios/arc-registers", NULL, NULL, NULL, 0,
        "IOS-ARC-REGISTERS: 52 retain/release entry points, nil/constants, x0 results, callee register preservation and real weak/dealloc ownership");
    puts("iOS PASS: native register-specific ARC calling conventions and ownership");
    run("/opt/ios/graphics", NULL, NULL, NULL, 0,
        "IOS-GRAPHICS: scaled/nested/TLS contexts, BGRA pixels, state/clip, independent snapshots, image drawing and real PNG/JPEG round trips");
    puts("iOS PASS: native UIKit bitmap contexts, image ownership and PNG/JPEG codecs");
    run("/opt/ios/Modules.app/Modules", NULL, NULL, NULL, 0,
        "IOS-MODULES: bundled dylibs, runpaths, rebased exports, dependency constructors, Objective-C inheritance, independent TLS and dynamic lookup");
    puts("iOS PASS: bundled Mach-O libraries, dependent initialization and isolated image TLS");
    run("--audit", "/opt/ios/Modules.app/Modules", NULL, NULL, 0,
        "0 unresolved strong, 1 unresolved weak (app code was not executed)");
    run("/opt/ios/ModulesMissing.app/Modules", NULL, NULL, NULL, 1,
        "library not found in runpaths: @rpath/Leaf.framework/Leaf");
    run("/opt/ios/ModulesArm64e.app/Modules", NULL, NULL, NULL, 1,
        "ARM64e requires pointer authentication support");
    run("--audit", "/opt/ios/core-foundation", NULL, NULL, 0,
        "0 unresolved strong, 0 unresolved weak (app code was not executed)");
    run("--audit", "/opt/ios/unsupported", NULL, NULL, 1,
        "libSystem symbol is not implemented: _mach_msg_server");
    puts("iOS PASS: import audit reports missing dependencies without executing app code");
    run("/opt/ios/lazy", NULL, NULL, NULL, 0, "IOS-LAZY: unused unavailable framework call did not block entry");
    run("/opt/ios/lazy", "call", NULL, NULL, 1, "unsupported API reached by app:");
    puts("iOS PASS: lazy function imports defer unsupported calls");
    run("/opt/ios/stdio", NULL, NULL, NULL, 0, "IOS-STDIO: FILE layout, buffers, varargs and sysctl queries");
    puts("iOS PASS: Darwin stdio, varargs and system queries");
    run("/opt/ios/SceneFixture.app/SceneFixture", NULL, NULL, NULL, 0,
        "IOS-SCENE: native app delegate, manifest scene connection and window");
    puts("iOS PASS: native UIKit scene and application launch");
    run("/opt/ios/SceneFixture.app/SceneFixture", "/opt/ios/launch name#é%?.bin", NULL, NULL, 0,
        "IOS-SCENE-FILE: launch options, scene URL contexts, percent encoding and ARC lifetime");
    puts("iOS PASS: native file launch and scene URL ownership");
    if (!access("/opt/ios/PPSSPP", R_OK)) {
        run("--inspect", "/opt/ios/PPSSPP", NULL, NULL, 0, "Imports: 767 (symbol table)");
        if (!access("/opt/ios/gles", R_OK)) test_ppsspp_ui();
        else run("/opt/ios/PPSSPP", NULL, NULL, NULL, 1,
                "unimplemented Objective-C method EAGLContext initWithAPI:");
        if (access("/opt/ios/ppsspp-muted", F_OK)) puts("iOS BLOCKED: upstream PPSSPP unsupported API reached at runtime");
    }
    if (!access("/opt/ios/cxx", R_OK)) {
        run("/opt/ios/cxx", NULL, NULL, NULL, 0, "IOS-CXX: destructor\n");
        run("/opt/ios/cxx", "throw", NULL, NULL, 1, "C++ exception unwinding through Mach-O frames is not implemented");
        puts("iOS PASS: native C++ strings, streams, regex and lifetime");
        run("/opt/ios/cxx-extended", NULL, NULL, NULL, 0,
            "IOS-CXX-EXTENDED: legacy strings, integer sorts, futures, weak ownership and Darwin entropy");
        run("/opt/ios/cxx-extended", "abort", NULL, NULL, -SIGABRT,
            "IOS-CXX-ABORT: stack 17 1099511627776 2.500 0x1234\n");
        puts("iOS PASS: extended C++ ABI, Darwin entropy and variadic abort");
        run_program(1, "/opt/ios/cxx-native", NULL, NULL, NULL, 0,
            "IOS-CXX-EXTENDED: native vector exception types and messages");
        puts("iOS PASS: native ELF vector exception helpers");
        run("/opt/ios/startup", NULL, NULL, NULL, 0, "IOS-STARTUP: load, categories, initialize, ObjC++ lifetime and UTF-16");
        run("/opt/ios/startup", "verify-preferences", NULL, NULL, 0, "IOS-STARTUP: preferences persisted across native Mach-O executions");
        puts("iOS PASS: Objective-C image startup and C++ ivars");
    }
    run(calculator, "1", "/", "0", 3, "IOS-CALCULATOR: division by zero\n");
    run(calculator, "1", "?", "2", 2, "IOS-CALCULATOR: unknown operator\n");
    run(calculator, NULL, NULL, NULL, 2, "usage: calculator");
    run("/opt/ios/unsupported", NULL, NULL, NULL, 1, "libSystem symbol is not implemented: _mach_msg_server");
    puts("iOS PASS: return status and unsupported imports");
    run("/opt/ios/calculator-fat", "19", "+", "23", 0, "IOS-CALCULATOR: 42\n");
    puts("iOS PASS: universal executable selects ARM64");
    run("/opt/ios/calculator-arm64e", NULL, NULL, NULL, 1, "ARM64e requires pointer authentication support");
    run("/opt/ios/truncated", NULL, NULL, NULL, 1, "file range exceeds input");
    puts("iOS PASS: ARM64e and malformed images rejected");
    test_uikit();
    if (!access("/opt/ios/model-tests", R_OK)) {
        run("/opt/ios/model-tests", NULL, NULL, NULL, 0, "iOS PASS: upstream 2048 eight model merge tests");
        test_2048();
    }
    puts("VINIX iOS GUEST: PASS");
    for (;;) pause();
}
