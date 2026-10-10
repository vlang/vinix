// SPDX-License-Identifier: GPL-2.0-or-later
module hostcompiler

fn test_integer_printf_guard_matches_whole_tokens() {
	for text in ['PRId64', ' PRIu32;', '#define PRIabc 1', 'PRIx8'] {
		assert has_printf_macro(text)
	}
	for text in ['', 'PRI', 'beforePRId64', '_PRId64', 'PRI_with_underscore', 'PRId64_'] {
		assert !has_printf_macro(text)
	}
}
