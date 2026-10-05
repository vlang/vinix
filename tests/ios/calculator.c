// SPDX-License-Identifier: GPL-2.0-or-later
// Original iOS-targeted executable probe, not Apple's Calculator.
// No Apple headers or libraries are needed: only the documented Mach-O ABI.
typedef unsigned long size_t;
extern int puts(const char *);
extern int atoi(const char *);
extern void *malloc(size_t);
extern void free(void *);
extern size_t strlen(const char *);
extern int strcmp(const char *, const char *);

// This pointer lives in __DATA and must be rebased to the anonymous mapping.
static const char *volatile banner = "IOS-CALCULATOR: ";
static volatile long long bss_check[32];

static void print_result(long long value) {
    char *output = malloc(64);
    if (!output) return;
    size_t length = strlen(banner);
    for (size_t i = 0; i < length; i++) output[i] = banner[i];
    if (value < 0) {
        output[length++] = '-';
        value = -value;  // Inputs are signed int, so even their product fits.
    }
    char digits[32];
    int count = 0;
    do {
        digits[count++] = '0' + value % 10;
        value /= 10;
    } while (value);
    while (count) output[length++] = digits[--count];
    output[length] = 0;
    puts(output);
    free(output);
}

int main(int argc, char **argv, char **envp, char **apple) {
    if (!envp || !apple || envp[0] || apple[0]) return 10;
    for (int i = 0; i < 32; i++) if (bss_check[i]) return 11;
    if (argc != 4) {
        puts("usage: calculator <integer> <+|-|*|/|%> <integer>");
        return 2;
    }
    long long left = atoi(argv[1]), right = atoi(argv[3]), result;
    if (!strcmp(argv[2], "+")) result = left + right;
    else if (!strcmp(argv[2], "-")) result = left - right;
    else if (!strcmp(argv[2], "*")) result = left * right;
    else if (!strcmp(argv[2], "/") || !strcmp(argv[2], "%")) {
        if (!right) {
            puts("IOS-CALCULATOR: division by zero");
            return 3;
        }
        result = argv[2][0] == '/' ? left / right : left % right;
    } else {
        puts("IOS-CALCULATOR: unknown operator");
        return 2;
    }
    print_result(result);
    return 0;
}
