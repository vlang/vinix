/* Native SDK types only; all workload and checking policy lives in V. */
#ifndef VINIX_BIG_IO_NATIVE_ABI_H
#define VINIX_BIG_IO_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define BIG_IO_ERRNO() (&errno)
struct big_io_pages { unsigned long long value; };
_Static_assert(sizeof(struct big_io_pages) == 8, "native scanf/printf width");
#endif
