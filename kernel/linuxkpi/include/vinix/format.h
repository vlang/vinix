/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_FORMAT_H
#define VINIX_LINUXKPI_FORMAT_H

#include <linux/sprintf.h>

/* Keep hosted sanitizer/libc formatting independent of this kernel runtime.
 * This option is only for the isolated formatter fixtures, never native code. */
#ifdef VINIX_LINUXKPI_FORMAT_HOST_TEST
int vinix_linuxkpi_format_test_snprintf(char *, size_t, const char *, ...);
int vinix_linuxkpi_format_test_vsnprintf(char *, size_t, const char *, va_list);
int vinix_linuxkpi_format_test_scnprintf(char *, size_t, const char *, ...);
int vinix_linuxkpi_format_test_vscnprintf(char *, size_t, const char *, va_list);
int vinix_linuxkpi_format_test_sprintf(char *, const char *, ...);
int vinix_linuxkpi_format_test_vsprintf(char *, const char *, va_list);
#define snprintf vinix_linuxkpi_format_test_snprintf
#define vsnprintf vinix_linuxkpi_format_test_vsnprintf
#define scnprintf vinix_linuxkpi_format_test_scnprintf
#define vscnprintf vinix_linuxkpi_format_test_vscnprintf
#define sprintf vinix_linuxkpi_format_test_sprintf
#define vsprintf vinix_linuxkpi_format_test_vsprintf
#endif

#define VINIX_FORMAT_INVALID 1U
#define VINIX_FORMAT_UNSUPPORTED 2U
#define VINIX_FORMAT_TRUNCATED 4U

/* Like vsnprintf, with optional diagnostic metadata for owned log records.
 * Invalid conversions stop without fetching their argument. Unsupported
 * pointer extensions emit a bounded diagnostic and stop. The implementation
 * never allocates, queues work, wakes a task, or calls the console. */
int vinix_linuxkpi_vformat(char *buf, size_t size, const char *fmt,
    va_list args, unsigned int *status);

/* Process-only one-shot publication of a key supplied by secure native RNG.
 * The caller keeps this input alive only until return; no pointer is retained.
 * Returns 0, -EINVAL, -EWOULDBLOCK or -EALREADY. EWOULDBLOCK also permits
 * retry while another setter publishes; EALREADY means immutable READY. */
int vinix_linuxkpi_format_set_key(const u64 key[2]);
#endif
