/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
static int calls, command, execution, labeling;
static unsigned long domain, kind, mask;
static int mock_prctl(int option, ...)
{
    assert(option == 0x56584d41);
    va_list args;
    va_start(args, option);
    command = (int)va_arg(args, unsigned long);
    domain = va_arg(args, unsigned long);
    kind = va_arg(args, unsigned long);
    mask = va_arg(args, unsigned long);
    va_end(args);
    ++calls;
    return 0;
}
static int mock_lsetxattr(const char *path, const char *name, const void *value, size_t size, int flags)
{
    assert(!strcmp(path, "/test") && !strcmp(name, "security.vinix"));
    assert(size == 2 && !memcmp(value, "28", 2) && flags == 0);
    ++labeling;
    return 0;
}
int mock_execvp(const char *path, char *const argv[]);
#define VINIX_MAC_HOST_TEST
#define prctl mock_prctl
#define lsetxattr mock_lsetxattr
#define execvp mock_execvp
#define main cli_main
#include "../../tools/security-mac/mac.c"
#undef main
int mock_execvp(const char *path, char *const argv[])
{
    assert(command == 3 && domain == 15 && kind == 0 && mask == 0);
    assert(!strcmp(path, "/program") && !strcmp(argv[0], path) && !strcmp(argv[1], "argument") && argv[2] == NULL);
    ++execution;
    errno = ENOENT;
    return -1;
}
static int invoke(int count, const char *const *arguments)
{
    char *argv[8];
    assert(count < 8);
    for (int i = 0; i < count; ++i) argv[i] = (char *)arguments[i];
    argv[count] = NULL;
    return cli_main(count, argv);
}
int main(void)
{
    unsigned value;
    assert(!number("0", 32, &value) && value == 0);
    assert(!number("31", 32, &value) && value == 31);
    const char *bad[] = { "", "01", "-1", "+1", "32", "99999999999999", " 1", "1x" };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) assert(number(bad[i], 32, &value));
    assert(!permissions("inspect,read,write,execute,search,create,remove,metadata,ioctl", &value) && value == 511);
    assert(!permissions("none", &value) && value == 0);
    const char *bad_permissions[] = { "", "read,", ",read", "read,,write", "read,read", "unknown", "all", "none,read" };
    for (size_t i = 0; i < sizeof(bad_permissions) / sizeof(bad_permissions[0]); ++i) assert(permissions(bad_permissions[i], &value));
    const char *rule[] = { "vinix-mac", "rule", "15", "31", "inspect,read,search" };
    assert(!invoke(5, rule) && calls == 1 && command == 1 && domain == 15 && kind == 31 && mask == 259);
    const char *invalid_rule[] = { "vinix-mac", "rule", "0", "31", "read" };
    assert(invoke(5, invalid_rule) == 2 && calls == 1);
    const char *seal[] = { "vinix-mac", "seal" };
    assert(!invoke(2, seal) && calls == 2 && command == 2 && !domain && !kind && !mask);
    const char *labels[] = { "vinix-mac", "label", "28", "/test" };
    assert(!invoke(4, labels) && labeling == 1);
    const char *run[] = { "vinix-mac", "run", "15", "/program", "argument" };
    assert(invoke(5, run) == 1 && calls == 3 && execution == 1);
    puts("security MAC CLI tests passed");
    return 0;
}
