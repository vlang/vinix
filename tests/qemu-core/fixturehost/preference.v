// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

fn C.posix_spawnattr_setbinpref_np(voidptr, usize, &i32, &usize) i32

// The SDK setter copies both values into its owned attribute object. The final
// CPU_TYPE_ANY keeps normal grading for binaries with one available slice.
fn apply_arch_preference(attributes voidptr, host_arch string) ! {
	$if darwin {
		cpu := match host_arch.to_lower() {
			'arm64', 'aarch64' { i32(C.CPU_TYPE_ARM64) }
			'x86_64', 'amd64' { i32(C.CPU_TYPE_X86_64) }
			else { return }
		}
		preferences := [cpu, i32(C.CPU_TYPE_ANY)]!
		mut copied := usize(0)
		status := C.posix_spawnattr_setbinpref_np(attributes, 2, &preferences[0], &copied)
		if status != 0 { return file_error('', status) }
		if copied != 2 { return error('Incomplete SDK binary preference') }
	}
}
