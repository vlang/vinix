// SPDX-License-Identifier: GPL-2.0-or-later
extern int puts(const char *);
extern void vinix_test_unavailable(void);
int main(int argc, char **argv) {
    (void)argv;
    if (argc > 1) vinix_test_unavailable();
    puts("IOS-LAZY: unused unavailable framework call did not block entry");
    return 0;
}
