/* SPDX-License-Identifier: MIT */
/* Declarations for unused compiler diagnostics; no hosted implementation. */
#ifndef VINIX_PS2_HOMEBREW_UNUSED_STDIO_H
#define VINIX_PS2_HOMEBREW_UNUSED_STDIO_H
typedef struct PS2_UNUSED_FILE FILE;
extern FILE *stderr;
int fprintf(FILE *, const char *, ...);
#endif
