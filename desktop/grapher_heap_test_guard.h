// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_GRAPHER_HEAP_TEST_GUARD_H
#define VINIX_GRAPHER_HEAP_TEST_GUARD_H

// Used only by Grapher's heap suite, after heap_tracker.h. Keep these checks
// executable independently of the V compiler's assert settings.
static void vinix_grapher_heap_require_tracking(void) {
	if (!vinix_heap_tracking || vinix_heap_count() == 0 || vinix_heap_live_bytes == 0)
		__builtin_trap();
}

static void vinix_grapher_heap_require_clean(void) {
	unsigned long long live = vinix_heap_end();
	if (live != 0 || vinix_heap_count() != 0) __builtin_trap();
}

#endif
