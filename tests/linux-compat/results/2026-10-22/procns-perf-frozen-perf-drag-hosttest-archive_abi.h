/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Declaration-only boundary for the system libarchive library. */
#ifndef VINIX_HOSTTEST_ARCHIVE_ABI_H
#define VINIX_HOSTTEST_ARCHIVE_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#if __has_include(<archive.h>) && __has_include(<archive_entry.h>)
#include <archive.h>
#include <archive_entry.h>
#else
/* The macOS SDK ships libarchive 3.x without its public headers.
 * These declarations match libarchive's archive.h and archive_entry.h. */
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_filter_xz(struct archive *);
int archive_read_support_format_tar(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
ssize_t archive_read_data(struct archive *, void *, size_t);
const char *archive_error_string(struct archive *);
int archive_read_free(struct archive *);
#endif
#endif
