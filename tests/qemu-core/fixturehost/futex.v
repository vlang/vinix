// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest

fn parse_futex_number(macros string) !string {
	for line in macros.split_into_lines() {
		if !line.starts_with('#define SYS_futex ') { continue }
		number := line['#define SYS_futex '.len..]
		if number.len > 0 && number.bytes().all(it.is_digit()) { return number }
	}
	return error('Target SDK has no numeric SYS_futex definition')
}

fn futex_number(output string, arch string) !string {
	sysroot := hosttest.env_default('VINIX_AARCH64_SYSROOT', hosttest.root() + '/build-aarch64-userland/sysroot')
	cc := if arch == 'arm64' {
		[hosttest.env_default('CC', 'clang'), '--target=aarch64-linux-musl', '--sysroot=' + sysroot]
	} else {
		[hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc')]
	}
	macros := command([...cc, '-dM', '-E', '-include', 'sys/syscall.h', '-x', 'c', '/dev/null'], '')!
	number := parse_futex_number(macros)!
	write(output + '/native-syscall-macros.txt', macros)!
	return number
}

fn validate_futex_observations(result string) ! {
	rows := result.split_into_lines()
	if rows.len != 15 { return error('Original/V futex diagnostics differ: ' + result) }
	for i := 0; i < 14; i += 2 {
		if rows[i] != rows[i + 1] { return error('Original/V futex diagnostics differ: ' + result) }
	}
}
