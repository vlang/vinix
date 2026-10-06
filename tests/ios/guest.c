// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
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

static void run(const char *image, const char *left, const char *op,
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
        execv(arguments[0], arguments);
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
    int status;
    while (waitpid(child, &status, 0) < 0) if (errno != EINTR) fail("waitpid");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != expected_status || !strstr(output, expected_output)) {
        printf("image=%s expression=%s %s %s status=%d output=%s\n", image,
            left ? left : "", op ? op : "", right ? right : "", status, output);
        fail("Mach-O result/status mismatch");
    }
    if (!strcmp(image, "/opt/ios/PPSSPP") && (!strstr(output, "SceneDelegate: Launching PPSSPP") ||
        !strstr(output, "V panic: iOS:") || (!strstr(output, "unimplemented") && !strstr(output, "unsupported") && !strstr(output, "not implemented"))))
        fail("PPSSPP did not reach scene launch or explicit unsupported API failure");
    printf("iOS RESULT: %s", output);
}

extern void test_uikit(void);
extern void test_2048(void);

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
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
    run("/opt/ios/lazy", NULL, NULL, NULL, 0, "IOS-LAZY: unused unavailable framework call did not block entry");
    run("/opt/ios/lazy", "call", NULL, NULL, 1, "unsupported API reached by app:");
    puts("iOS PASS: lazy function imports defer unsupported calls");
    run("/opt/ios/stdio", NULL, NULL, NULL, 0, "IOS-STDIO: FILE layout, buffers, varargs and sysctl queries");
    puts("iOS PASS: Darwin stdio, varargs and system queries");
    run("/opt/ios/SceneFixture.app/SceneFixture", NULL, NULL, NULL, 0,
        "IOS-SCENE: native app delegate, manifest scene connection and window");
    puts("iOS PASS: native UIKit scene and application launch");
    if (!access("/opt/ios/PPSSPP", R_OK)) {
        run("--inspect", "/opt/ios/PPSSPP", NULL, NULL, 0, "Imports: 767 (symbol table)");
        run("/opt/ios/PPSSPP", NULL, NULL, NULL, 1, "SceneDelegate class was loaded!");
        puts("iOS BLOCKED: upstream PPSSPP unsupported API reached at runtime");
    }
    if (!access("/opt/ios/cxx", R_OK)) {
        run("/opt/ios/cxx", NULL, NULL, NULL, 0, "IOS-CXX: destructor\n");
        run("/opt/ios/cxx", "throw", NULL, NULL, 1, "C++ exception unwinding through Mach-O frames is not implemented");
        puts("iOS PASS: native C++ strings, streams, regex and lifetime");
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
