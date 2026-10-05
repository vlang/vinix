// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: BSD-2-Clause */
#include "execinfo_compat.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(expression) do {                                               \
	if (!(expression)) {                                                   \
		fprintf(stderr, "execinfo test failed at line %d: %s\n",       \
		    __LINE__, #expression);                                      \
		return 1;                                                       \
	}                                                                       \
} while (0)

__attribute__((noinline))
static int capture_and_check(void)
{
	void *frames[32];
	int count = backtrace(frames, 32);
	CHECK(count >= 2);

	char **symbols = backtrace_symbols(frames, count);
	CHECK(symbols != NULL);
	for (int index = 0; index < count; index++) {
		char address[64];
		snprintf(address, sizeof(address), "[0x%zx]",
		    (size_t)(uintptr_t)frames[index]);
		CHECK(symbols[index] != NULL);
		CHECK(strstr(symbols[index], address) != NULL);
	}
	free(symbols);

	int descriptors[2];
	CHECK(pipe(descriptors) == 0);
	backtrace_symbols_fd(frames, count, descriptors[1]);
	CHECK(close(descriptors[1]) == 0);
	char output[8192];
	ssize_t length = read(descriptors[0], output, sizeof(output));
	CHECK(length > 0);
	CHECK(close(descriptors[0]) == 0);
	int newlines = 0;
	for (ssize_t index = 0; index < length; index++) {
		if (output[index] == '\n')
			newlines++;
	}
	CHECK(newlines == count);
	return 0;
}

int main(void)
{
	CHECK(backtrace(NULL, 8) == 0);
	CHECK(backtrace_symbols(NULL, 8) == NULL);
	CHECK(capture_and_check() == 0);
	puts("execinfo compatibility: PASS");
	return 0;
}
