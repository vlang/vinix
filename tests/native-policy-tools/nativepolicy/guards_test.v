// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

#include <errno.h>
#include <sys/wait.h>
fn C.waitpid(i32, &i32, i32) i32

fn test_fixture_timeout_kills_and_reaps_the_child() {
	timed_inherited(['/usr/bin/true'], 2) or { panic(err) }
	mut failed := false
	timed_inherited(['/usr/bin/false'], 2) or {
		failed = true
		assert err.msg().contains('Fixture failed: 1')
	}
	assert failed
	mut timed_out := false
	timed_inherited(['/bin/sleep', '5'], 0) or {
		timed_out = true
		assert err.msg().contains('Fixture timed out after 0 seconds')
	}
	assert timed_out
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1
	assert C.errno == C.ECHILD
}

fn test_darwin_assembly_adapter_changes_only_native_symbol_and_section_directives() {
	before := '#include "varargs.inc"\n.text\nVINIX_VARIADIC printf, vinix_printf_entry, 1\n' +
		'.global vp_format\n.type vp_format, @function\nvp_format:\n    jmp npf_vpprintf\n' +
		'.size vp_format, .-vp_format\n.data\n.global stderr\nstderr:\n    .quad .Lstderr_file\n' +
		'.section .note.GNU-stack,"",@progbits\n'
	assert console_darwin_abi(before) == '#include "varargs.inc"\n.text\n' +
		'VINIX_VARIADIC ABI_SYMBOL(printf), ABI_SYMBOL(vinix_printf_entry), 1\n' +
		'.global ABI_SYMBOL(vp_format)\nABI_SYMBOL(vp_format):\n    jmp ABI_SYMBOL(npf_vpprintf)\n' +
		'.section __DATA,__data\n.global ABI_SYMBOL(stderr)\nABI_SYMBOL(stderr):\n    .quad .Lstderr_file\n'
}

fn test_allocator_guards_keep_original_symbol_sets_and_unicode_boundaries() {
	for name in ['malloc', '_calloc', 'new_array_from_c_array', '_new_array', 'realloc', 'memdup'] {
		assert allocator_imports(' U ' + name + '\r\n', ['malloc', 'calloc', 'realloc', 'memdup'], ['new_array', 'array_new'])
	}
	assert !allocator_imports('_free', ['malloc', 'calloc', 'realloc', 'memdup'], ['new_array', 'array_new'])
	assert !allocator_imports('é_malloc mallocé new_array_é', ['malloc', 'calloc', 'realloc', 'memdup'], []string{})
	assert allocator_imports(' U array_new_é', []string{}, ['array_new'])
	assert !allocator_imports('array_new', []string{}, ['new_array'])
	assert !allocator_imports('malloc_extra __malloc', ['malloc'], []string{})
	assert allocator_call('new_array_é\u2003(')
	assert allocator_call('malloc\n(')
	assert !allocator_call('é_malloc( mallocé( __malloc(')
	assert !allocator_call('free( aligned_alloc(')
	assert !allocator_call('malloc.value;')
	assert pri_token('PRIu64')
	assert !pri_token('éPRIu64 PRI_u64 PRI')
}

fn test_reference_adapter_keeps_control_bodies_and_first_closing_line() {
	source := 'typedef unsigned long u64;\ntypedef long i64;\n' +
		'static inline i64 syscall1(u64 nr,u64 a0) {\n original_register();\n}\n' +
		'static inline i64 syscall5(u64 nr,u64 a0,u64 a1,u64 a2,u64 a3,u64 a4) {\n registers();\n}\n' +
		'__attribute__((naked)) static void signal_restorer(void) {\n asm_boundary();\n}\n' +
		'void _start(void) { original_algorithm(); }\n'
	converted := reference_init(source, 'shell') or { panic(err) }
	assert converted == 'typedef unsigned long u64;\ntypedef long i64;\n' +
		'extern i64 vinit_syscall(u64,u64,u64,u64,u64,u64);\n' +
		'static inline i64 syscall1(u64 nr,u64 a0) { return vinit_syscall(nr,a0,0,0,0,0); }\n' +
		'static inline i64 syscall5(u64 nr,u64 a0,u64 a1,u64 a2,u64 a3,u64 a4) { return vinit_syscall(nr,a0,a1,a2,a3,a4); }\n' +
		'\n\n\nstatic void signal_restorer(void) {}\nvoid vinix_init_shell(void) { original_algorithm(); }\n'
	assert (reference_init('typedef long i64;\nstatic inline i64 syscall1() {\n x();\n}\n', 'shell') or { panic(err) }).contains('syscall1()')
	assert (reference_init('typedef long i64;\nstatic inline i64 syscall6(u64 nr) {\n x();\n}\n', 'shell') or { panic(err) }).contains('syscall6')
	assert replace_word('requested_power_signal érequested_power_signal requested_power_signalé',
		'requested_power_signal', 'vinit_power') == 'vinit_power érequested_power_signal requested_power_signalé'
}
