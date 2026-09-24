// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later
 * execinfo compatibility for the musl-linked Vinix desktop.
 *
 * musl deliberately does not provide backtrace(3).  GCC's unwinder already
 * has everything needed to walk the .eh_frame tables emitted by clang, so use
 * that rather than relying on frame pointers (which optimized builds may
 * omit).  The symbol strings use glibc's shape because that is what V's panic
 * formatter consumes.
 */
#define _GNU_SOURCE

#include "execinfo_compat.h"

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <unwind.h>

struct vinix_backtrace_state {
	void **buffer;
	int size;
	int count;
	int skip;
};

static _Unwind_Reason_Code vinix_backtrace_step(
	struct _Unwind_Context *context, void *argument)
{
	struct vinix_backtrace_state *state = argument;
	uintptr_t instruction = (uintptr_t)_Unwind_GetIP(context);

	if (state->skip != 0) {
		state->skip--;
		return _URC_NO_REASON;
	}
	if (instruction == 0)
		return _URC_END_OF_STACK;
	if (state->count == state->size)
		return _URC_END_OF_STACK;
	state->buffer[state->count++] = (void *)instruction;
	return _URC_NO_REASON;
}

__attribute__((noinline))
int backtrace(void **buffer, int size)
{
	if (buffer == NULL || size <= 0)
		return 0;

	struct vinix_backtrace_state state = {
		.buffer = buffer,
		.size = size,
		.count = 0,
		/* The first unwind context belongs to backtrace itself. */
		.skip = 1,
	};
	_Unwind_Backtrace(vinix_backtrace_step, &state);
	return state.count;
}

static int vinix_format_backtrace_frame(char *destination, size_t capacity,
	const void *address)
{
	Dl_info information;
	char executable[PATH_MAX];
	const char *image = "/proc/self/exe";
	const char *symbol = NULL;
	uintptr_t instruction = (uintptr_t)address;
	uintptr_t offset = instruction;
	ssize_t executable_length = readlink("/proc/self/exe", executable,
	    sizeof(executable) - 1);
	if (executable_length > 0 && (size_t)executable_length < sizeof(executable)) {
		executable[executable_length] = '\0';
		image = executable;
	}

	memset(&information, 0, sizeof(information));
	if (dladdr(address, &information) != 0) {
		if (information.dli_fname != NULL && information.dli_fname[0] != '\0')
			image = information.dli_fname;
		if (information.dli_sname != NULL && information.dli_saddr != NULL &&
		    instruction >= (uintptr_t)information.dli_saddr) {
			symbol = information.dli_sname;
			offset = instruction - (uintptr_t)information.dli_saddr;
		} else if (information.dli_fbase != NULL &&
		    instruction >= (uintptr_t)information.dli_fbase) {
			offset = instruction - (uintptr_t)information.dli_fbase;
		}
	}

	if (symbol != NULL) {
		return snprintf(destination, capacity, "%s(%s+0x%zx) [0x%zx]",
		    image, symbol, (size_t)offset, (size_t)instruction);
	}
	return snprintf(destination, capacity, "%s(+0x%zx) [0x%zx]", image,
	    (size_t)offset, (size_t)instruction);
}

char **backtrace_symbols(void *const *buffer, int size)
{
	if (buffer == NULL || size <= 0)
		return NULL;

	size_t pointer_bytes = (size_t)size * sizeof(char *);
	if (pointer_bytes / sizeof(char *) != (size_t)size)
		return NULL;

	size_t allocation_size = pointer_bytes;
	for (int index = 0; index < size; index++) {
		int length = vinix_format_backtrace_frame(NULL, 0, buffer[index]);
		if (length < 0 || (size_t)length >= SIZE_MAX - allocation_size)
			return NULL;
		allocation_size += (size_t)length + 1;
	}

	char **symbols = malloc(allocation_size);
	if (symbols == NULL)
		return NULL;

	char *text = (char *)symbols + pointer_bytes;
	size_t remaining = allocation_size - pointer_bytes;
	for (int index = 0; index < size; index++) {
		int length = vinix_format_backtrace_frame(text, remaining,
		    buffer[index]);
		if (length < 0 || (size_t)length >= remaining) {
			free(symbols);
			return NULL;
		}
		symbols[index] = text;
		text += (size_t)length + 1;
		remaining -= (size_t)length + 1;
	}
	return symbols;
}

static void vinix_write_all(int fd, const char *text, size_t length)
{
	while (length != 0) {
		ssize_t written = write(fd, text, length);
		if (written > 0) {
			text += written;
			length -= (size_t)written;
		} else if (written < 0 && errno == EINTR) {
			continue;
		} else {
			return;
		}
	}
}

void backtrace_symbols_fd(void *const *buffer, int size, int fd)
{
	if (buffer == NULL || size <= 0)
		return;

	for (int index = 0; index < size; index++) {
		char line[1024];
		int length = vinix_format_backtrace_frame(line, sizeof(line),
		    buffer[index]);
		if (length < 0)
			continue;
		if ((size_t)length >= sizeof(line)) {
			length = snprintf(line, sizeof(line),
			    "/proc/self/exe(+0x%zx) [0x%zx]",
			    (size_t)(uintptr_t)buffer[index],
			    (size_t)(uintptr_t)buffer[index]);
		}
		if (length > 0)
			vinix_write_all(fd, line, (size_t)length);
		vinix_write_all(fd, "\n", 1);
	}
}
