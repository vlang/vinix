// SPDX-License-Identifier: GPL-2.0-or-later
module memorytools
import os

fn test_exact_compiler_filter_and_allocator_guard() {
	input := ['clang', '-std=c11', '-Werror', '-static', '-nostdlib', '-pie', '-L/s', '-lc', '-Wl,-dead_strip', '-fuse-ld=lld', '-Dfoo', '-fno-builtin']
	assert compile_flags(input) == ['clang', '-std=c11', '-Werror', '-Dfoo', '-fno-builtin']
	for name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc', 'new_array_from_c_array', 'aligned_alloc', 'posix_memalign'] {
		if _ := check_imports('                 U _' + name + '\n', true) { assert false }
	}
	check_imports('                 U _memcpy\n                 U _memset\n', true) or { panic(err) }
	check_imports('                 U _aligned_alloc\n', false) or { panic(err) }
	assert !clean_diagnostics('runtime error: x')
	assert !clean_diagnostics('AddressSanitizer: x')
	assert !clean_diagnostics('LeakSanitizer: x')
	assert clean_diagnostics('ordinary diagnostic')
}

fn test_all_original_fault_domains_and_flags() {
	assert faults == ['none', 'open_zero', 'open_null', 'open_proc', 'read_proc', 'empty_proc', 'missing_large', 'bad_large', 'close_proc', 'warm_read', 'warm_write', 'interrupted_sleep', 'round_read', 'nonzero_payload', 'round_write', 'bad_read_errno', 'bad_read_return', 'bad_write_errno', 'bad_write_return', 'changed_pages', 'close_zero', 'close_null']
	previous := os.getenv_opt('VINIX_MEMORY_SANITIZERS')
	defer { if value := previous { os.setenv('VINIX_MEMORY_SANITIZERS', value, true) } else { os.unsetenv('VINIX_MEMORY_SANITIZERS') } }
	os.setenv('VINIX_MEMORY_SANITIZERS', 'none', true)
	plain := flags('aarch64', false, true)
	assert '-std=gnu99' in plain && '-fno-builtin' in plain && !plain.any(it.starts_with('-fsanitize='))
	assert '-fsanitize=address,undefined' in flags('aarch64', false, false)
	os.setenv('VINIX_MEMORY_SANITIZERS', 'undefined', true)
	assert '-fsanitize=undefined' in flags('aarch64', false, true)
	assert '-fsanitize=undefined' !in flags('aarch64', true, true)
}
