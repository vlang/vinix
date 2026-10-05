/* SPDX-License-Identifier: GPL-2.0-or-later */
/* The host test's stand-in for the CPU's random number generator. */
#include <stdint.h>

static int hardware_on;
static uint64_t hardware_state = 0x243f6a8885a308d3ULL;

void vinix_test_set_hardware(int on)
{
	hardware_on = on;
}

int vinix_hw_random64(uint64_t *out)
{
	if (!hardware_on)
		return 0;
	hardware_state = hardware_state * 6364136223846793005ULL + 1442695040888963407ULL;
	*out = hardware_state;
	return 1;
}

#include <stdarg.h>
#include <stdio.h>

int kprintf(const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	int ret = vprintf(fmt, args);
	va_end(args);
	return ret;
}
