// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import os

fn C.posix_spawnattr_getbinpref_np(voidptr, usize, &i32, &usize) i32

fn test_sdk_preference_is_copied_and_default_is_unchanged() {
	$if darwin {
		mut attributes := C.posix_spawnattr_t{}
		assert C.posix_spawnattr_init(&attributes) == 0
		defer { C.posix_spawnattr_destroy(&attributes) }
		apply_arch_preference(&attributes, 'x86_64') or { panic(err) }
		mut values := [i32(0), i32(0)]!
		mut count := usize(0)
		assert C.posix_spawnattr_getbinpref_np(&attributes, 2, &values[0], &count) == 0
		assert count == 2 && values[0] == i32(C.CPU_TYPE_X86_64) && values[1] == i32(C.CPU_TYPE_ANY)
		apply_arch_preference(&attributes, '') or { panic(err) }
		assert C.posix_spawnattr_getbinpref_np(&attributes, 2, &values[0], &count) == 0
		assert count == 2 && values[0] == i32(C.CPU_TYPE_X86_64) && values[1] == i32(C.CPU_TYPE_ANY)
	}
}

fn test_universal_child_selects_explicit_preference_and_preserves_environment() {
	$if darwin {
		mut env := os.environ()
		env['VINIX_PREFERENCE_CONTROL'] = 'owned environment'
		for arch in ['arm64', 'x86_64'] {
			value := capture_preferred(['/usr/bin/uname', '-m'], '', env, false, arch) or { panic(err) }
			assert value == arch + '\n'
			inherited_command_environment_preferred(['/bin/sh', '-c',
				'test "$VINIX_PREFERENCE_CONTROL" = "owned environment"'], env, arch) or { panic(err) }
		}
		assert capture(['/usr/bin/uname', '-m'], '', env, false) or { panic(err) } == os.uname().machine + '\n'
	}
}
