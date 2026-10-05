// SPDX-License-Identifier: GPL-2.0-or-later
extern int printf(const char *, ...);
int main(void) {
    return printf("must fail to link before this code runs\n");
}
