// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import os

fn check(state string, build guesthost.AbiBuild) ! {
	os.mkdir(state)!
	init := guesthost.build_abi_guest(state, build)!
	bytes := os.read_bytes(init) or { panic(err) }
	assert bytes[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
	assert int(bytes[18]) + (int(bytes[19]) << 8) == if build.arch == 'aarch64' { 183 } else { 62 }
	receipt := (hosttest.decode_json(os.read_file(state + '/inputs.json') or { panic(err) }) or { panic(err) }).as_map()
	assert (receipt['fixture_elf_sha256'] or { panic('missing ELF digest') }).str() == sha256.sum(bytes).hex()
	assert (receipt['kernel_rebuilt_by_runner'] or { panic('missing rebuild policy') }).bool() == false
	if build.baseline {
		assert os.is_file(state + '/rootfs/' + if build.family == 'socket-io' {
			'socket-io-baseline'
		} else {
			'proc-leaks-baseline'
		})
	}
	if build.family == 'procfs-allocs' {
		assert (os.ls(state + '/rootfs/many') or { panic(err) }).len == 1400
		assert os.is_file(state + '/rootfs/many/f0000') && os.is_file(state + '/rootfs/many/f1399')
	}
	println('BUILT ' + state)
}

fn record(state string, build guesthost.AbiBuild, mut failures []string) {
	check(state, build) or {
		eprintln('BUILD FAILED ' + state + ': ' + err.msg())
		failures << state
	}
}

fn matrix() int {
	state_arg := if os.args.len > 1 { os.args[1] } else { '' }
	work := hosttest.work_dir(state_arg, 'vinix-abi-build-check-') or { panic(err) }
	defer { if state_arg == '' { hosttest.remove_work_dir(work) or { panic(err) } } }
	mut failures := []string{}
	for arch in ['aarch64', 'x86_64'] {
		for family in guesthost.abi_suites() {
			if family == 'clock-control' && arch != 'aarch64' { continue }
			record(work + '/' + arch + '-' + family, guesthost.AbiBuild{ family: family, arch: arch }, mut failures)
			if family in ['socket-io', 'procfs-allocs'] {
				record(work + '/' + arch + '-' + family + '-baseline', guesthost.AbiBuild{ family: family, arch: arch, baseline: true }, mut failures)
			}
			if family == 'execute-only' {
				record(work + '/' + arch + '-' + family + '-readable', guesthost.AbiBuild{ family: family, arch: arch, expect_readable: true }, mut failures)
			}
			if family == 'procfs-mount' {
				record(work + '/' + arch + '-' + family + '-reuse', guesthost.AbiBuild{ family: family, arch: arch, case_name: 'reuse' }, mut failures)
			}
		}
	}
	if failures.len > 0 {
		eprintln('Failed ABI build profiles: ' + failures.str())
		return 1
	}
	println('Native ABI builds, ELF receipts and rootfs cases: PASS')
	return 0
}

fn main() { exit(matrix()) }
