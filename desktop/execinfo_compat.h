/* SPDX-License-Identifier: GPL-2.0-or-later
 * The execinfo API used by V's panic reporter. */
#ifndef VINIX_DESKTOP_EXECINFO_COMPAT_H
#define VINIX_DESKTOP_EXECINFO_COMPAT_H

#ifdef __cplusplus
extern "C" {
#endif

int backtrace(void **buffer, int size);
char **backtrace_symbols(void *const *buffer, int size);
void backtrace_symbols_fd(void *const *buffer, int size, int fd);

#ifdef __cplusplus
}
#endif

#endif
