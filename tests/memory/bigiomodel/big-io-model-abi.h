/* Native syscall-model declarations and aliases; implementation is V. */
#ifndef VINIX_BIG_IO_MODEL_ABI_H
#define VINIX_BIG_IO_MODEL_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef const char bgi_const_char;
typedef const void bgi_const_void;
#ifndef BIG_IO_MODEL_PROVIDER
int bgi_open(const char *, int);
ssize_t bgi_read(int, void *, size_t);
ssize_t bgi_write(int, const void *, size_t);
int bgi_close(int);
unsigned int bgi_sleep(unsigned int);
int bgi_pause(void);
#define open(path, flags) bgi_open(path, flags)
#define read bgi_read
#define write bgi_write
#define close bgi_close
#define sleep bgi_sleep
#define pause bgi_pause
#endif
#define BGI_ERRNO() (&errno)
#endif
