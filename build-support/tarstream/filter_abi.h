/* SPDX-License-Identifier: GPL-2.0-only */
/* Declaration-only boundary for libarchive's decompressed byte stream. */
#ifndef VINIX_TARSTREAM_FILTER_ABI_H
#define VINIX_TARSTREAM_FILTER_ABI_H
#include <stddef.h>
#include <sys/types.h>
#if __has_include(<archive.h>)
#include <archive.h>
#else
/* The macOS SDK supplies the library without public headers. */
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_filter_none(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
const char *archive_error_string(struct archive *);
int archive_read_free(struct archive *);
#endif
#endif
