// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module clifixture

#include <native-abi.h>

@[typedef]
struct C.mac_cli_const_char {}
@[typedef]
struct C.mac_cli_const_void {}
@[typedef]
struct C.mac_cli_const_pointer {}

@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.puts(&char) i32
fn C.__builtin_alloca(usize) voidptr
fn C.vm_main(i32, &&char) i32
fn C.vm_number(&char, u32, &u32) i32
fn C.vm_permissions(&char, &u32) i32

__global mac_fixture_calls i32
__global mac_fixture_command i32
__global mac_fixture_execution i32
__global mac_fixture_labeling i32
__global mac_fixture_domain u64
__global mac_fixture_kind u64
__global mac_fixture_mask u64

// The native variadic entry transports four unsigned-long words to this
// fixed-argument callback. Assertions and captured state remain in V.
@[export: 'vinix_mac_cli_capture']
pub fn capture(option i32, command u64, domain u64, kind u64, mask u64) i32 {
	C.assert(option == 0x56584d41)
	mac_fixture_command = i32(command)
	mac_fixture_domain = domain
	mac_fixture_kind = kind
	mac_fixture_mask = mask
	mac_fixture_calls++
	return 0
}

@[export: 'mock_lsetxattr']
pub fn label(path &C.mac_cli_const_char, name &C.mac_cli_const_char, value &C.mac_cli_const_void, size usize, flags i32) i32 {
	C.assert(C.strcmp(unsafe { &char(path) }, c'/test') == 0 && C.strcmp(unsafe { &char(name) }, c'security.vinix') == 0)
	C.assert(size == 2 && C.memcmp(unsafe { voidptr(value) }, c'28', 2) == 0 && flags == 0)
	mac_fixture_labeling++
	return 0
}

@[export: 'mock_execvp']
pub fn execute(path &C.mac_cli_const_char, argv &C.mac_cli_const_pointer) i32 {
	unsafe {
		words := &&char(argv)
		C.assert(mac_fixture_command == 3 && mac_fixture_domain == 15 && mac_fixture_kind == 0 && mac_fixture_mask == 0)
		C.assert(C.strcmp(&char(path), c'/program') == 0 && C.strcmp(words[0], &char(path)) == 0 && C.strcmp(words[1], c'argument') == 0 && words[2] == nil)
		mac_fixture_execution++
		C.errno = C.ENOENT
	}
	return -1
}

fn invoke(count i32, arguments &&char) i32 {
	mut argv := [8]&char{}
	C.assert(count < 8)
	unsafe {
		for i := i32(0); i < count; i++ { argv[i] = arguments[i] }
		argv[count] = nil
		return C.vm_main(count, &argv[0])
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		// Preserve the original uninitialized automatic output word: only the
		// production parser initializes it before each successful assertion.
		value := &u32(C.__builtin_alloca(sizeof(u32)))
		C.assert(C.vm_number(c'0', 32, value) == 0 && *value == 0)
		C.assert(C.vm_number(c'31', 32, value) == 0 && *value == 31)
		mut bad := [&char(c''), &char(c'01'), &char(c'-1'), &char(c'+1'), &char(c'32'), &char(c'99999999999999'), &char(c' 1'), &char(c'1x')]!
		for i := usize(0); i < usize(bad.len); i++ { C.assert(C.vm_number(bad[i], 32, value) != 0) }
		C.assert(C.vm_permissions(c'inspect,read,write,execute,search,create,remove,metadata,ioctl', value) == 0 && *value == 511)
		C.assert(C.vm_permissions(c'none', value) == 0 && *value == 0)
		mut bad_permissions := [&char(c''), &char(c'read,'), &char(c',read'), &char(c'read,,write'), &char(c'read,read'), &char(c'unknown'), &char(c'all'), &char(c'none,read')]!
		for i := usize(0); i < usize(bad_permissions.len); i++ { C.assert(C.vm_permissions(bad_permissions[i], value) != 0) }
		mut rule := [&char(c'vinix-mac'), &char(c'rule'), &char(c'15'), &char(c'31'), &char(c'inspect,read,search')]!
		C.assert(invoke(5, &rule[0]) == 0 && mac_fixture_calls == 1 && mac_fixture_command == 1 && mac_fixture_domain == 15 && mac_fixture_kind == 31 && mac_fixture_mask == 259)
		mut invalid_rule := [&char(c'vinix-mac'), &char(c'rule'), &char(c'0'), &char(c'31'), &char(c'read')]!
		C.assert(invoke(5, &invalid_rule[0]) == 2 && mac_fixture_calls == 1)
		mut seal := [&char(c'vinix-mac'), &char(c'seal')]!
		C.assert(invoke(2, &seal[0]) == 0 && mac_fixture_calls == 2 && mac_fixture_command == 2 && mac_fixture_domain == 0 && mac_fixture_kind == 0 && mac_fixture_mask == 0)
		mut labels := [&char(c'vinix-mac'), &char(c'label'), &char(c'28'), &char(c'/test')]!
		C.assert(invoke(4, &labels[0]) == 0 && mac_fixture_labeling == 1)
		mut run := [&char(c'vinix-mac'), &char(c'run'), &char(c'15'), &char(c'/program'), &char(c'argument')]!
		C.assert(invoke(5, &run[0]) == 1 && mac_fixture_calls == 3 && mac_fixture_execution == 1)
		C.puts(c'security MAC CLI tests passed')
	}
	return 0
}
