// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_NOTES_HEAP_TEST_GUARD_H
#define VINIX_NOTES_HEAP_TEST_GUARD_H

// Test-only guards retain an executable failure even if V assertions vanish.
static void vinix_notes_heap_require_tracking(void) {
	if (!vinix_heap_tracking || vinix_heap_count() == 0 || vinix_heap_live_bytes == 0)
		__builtin_trap();
}

static void vinix_notes_heap_require_clean(void) {
	unsigned long long live = vinix_heap_end();
	if (live != 0 || vinix_heap_count() != 0) __builtin_trap();
}
#endif
