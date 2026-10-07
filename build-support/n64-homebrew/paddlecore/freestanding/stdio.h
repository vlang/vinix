/* SPDX-License-Identifier: MIT */
/* Declarations for unused compiler diagnostics; no hosted implementation. */
#ifndef VINIX_N64_PADDLE_UNUSED_STDIO_H
#define VINIX_N64_PADDLE_UNUSED_STDIO_H
typedef struct N64_UNUSED_FILE FILE;
extern FILE *stderr;
int fprintf(FILE *, const char *, ...);
#endif
