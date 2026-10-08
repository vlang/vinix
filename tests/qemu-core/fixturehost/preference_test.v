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

fn test_preferred_raw_capture_preserves_directory_and_error_bytes() {
	$if darwin {
		work := os.temp_dir() + '/vinix-preference-' + os.getpid().str()
		os.mkdir(work) or { panic(err) }
		defer { os.rmdir(work) or { panic(err) } }
		for arch in ['arm64', 'x86_64'] {
			assert capture_in_preferred(['/bin/sh', '-c', 'printf "$PWD"'], '', os.environ(), false, work, true, arch) or { panic(err) } == os.real_path(work)
			assert capture_in_preferred(['/usr/bin/uname', '-m'], '', os.environ(), false, work, true, arch) or { panic(err) } == arch + '\n'
			capture_in_preferred(['/bin/sh', '-c', 'printf "raw\\377\\r\\n"; exit 7'], '', os.environ(), false, work, true, arch) or {
				assert err is CommandError && err.binary_output && err.status == 7
				assert err.output.bytes().hex() == '726177ff0d0a'
				continue
			}
			assert false
		}
	}
}
