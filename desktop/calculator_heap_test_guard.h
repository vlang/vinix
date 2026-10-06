// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_CALCULATOR_HEAP_TEST_GUARD_H
#define VINIX_CALCULATOR_HEAP_TEST_GUARD_H

// Test-only checks after heap_tracker.h; both survive disabled V assertions.
static void vinix_calculator_heap_require_tracking(void) {
	if (!vinix_heap_tracking || vinix_heap_count() == 0 || vinix_heap_live_bytes == 0)
		__builtin_trap();
}

static void vinix_calculator_heap_require_clean(void) {
	unsigned long long live = vinix_heap_end();
	if (live != 0 || vinix_heap_count() != 0) __builtin_trap();
}

#endif
