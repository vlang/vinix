// SPDX-License-Identifier: GPL-2.0-or-later
extern int mach_msg_server(void *, unsigned int, unsigned int, unsigned int);
int main(void) {
    return mach_msg_server((void *)0, 0, 0, 0);
}
