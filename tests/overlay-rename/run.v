// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

#include <unistd.h>

fn C.truncate(&char, i64) int

struct Receipt {
	architecture string
	case_name    string
	context      string = 'native Vinix QEMU guest; UID 1000 overlay workload; networking disabled'
	inputs       map[string]string
	exit_code    int
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{
			name:    '--case'
			value:   true
			choices: ['atomic', 'failure', 'disk', 'opaque', 'opaque-full', 'all']
		},
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: run.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR [--case atomic|failure|disk|opaque|opaque-full|all] [--timeout SECONDS]')!
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) {
			eprintln('missing ' + key)
			exit(2)
		}
	}
	arch := options.value('--arch', '')
	case_name := options.value('--case', 'all')
	state := os.abs_path(options.value('--state-dir', ''))
	timeout := options.integer('--timeout', 180)!
	if os.exists(state) || timeout <= 0 {
		eprintln('state must be fresh and timeout positive')
		exit(2)
	}
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	expected := if arch == 'aarch64' { 183 } else { 62 }
	if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(kernel[18]) + (int(kernel[19]) << 8) != expected {
		eprintln('kernel must be matching little-endian ELF64')
		exit(2)
	}
	os.mkdir_all(state + '/kernel/bin')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	os.mkdir_all(state + '/sources')!
	hosttest.module_copy_tree(@DIR + '/overlayfixture', state + '/sources/overlayfixture')!
	mut inputs := {
		'kernel':              sha256.sum(kernel).hex()
		'fixture':             digest(state + '/sources/overlayfixture/core.v')!
		'opaque_fixture':      digest(state + '/sources/overlayfixture/opaque.v')!
		'opaque_full_fixture': digest(state + '/sources/overlayfixture/opaque_full.v')!
		'abi_header':          digest(state + '/sources/overlayfixture/native-abi.h')!
	}
	disk := state + '/store.ext2'
	if case_name != 'atomic' {
		os.write_file(disk, '')!
		size_mb := if case_name == 'opaque-full' { 4 } else { 128 }
		if unsafe { C.truncate(disk.str, i64(size_mb) * 1024 * 1024) } != 0 {
			eprintln('cannot size private volume')
			exit(1)
		}
		mut formatter := os.getenv('VINIX_MKE2FS')
		if formatter == '' {
			for candidate in ['mke2fs', 'mkfs.ext2', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs'] {
				formatter = os.find_abs_path_of_executable(candidate) or { continue }
				break
			}
		}
		if formatter == '' {
			eprintln('mke2fs is required')
			exit(2)
		}
		mut child := os.new_process(formatter)
		child.set_args(['-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
			'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
			disk])
		child.run()
		child.wait()
		if child.code != 0 {
			eprintln('formatting private volume failed')
			exit(1)
		}
		child.close()
		inputs['disk_before'] = digest(disk)!
	}
	code := run_guest(state, arch, case_name, disk, timeout) or {
		eprintln(err.msg())
		1
	}
	for name, path in {
		'init': state + '/init'
		'iso':  state + '/test.iso'
	} {
		inputs[name] = digest(path) or { '' }
	}
	if case_name != 'atomic' { inputs['disk_after'] = digest(disk) or { '' } }
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		architecture: arch
		case_name:    case_name
		inputs:       inputs
		exit_code:    code
	},
		prettify: true
	) + '\n')!
	exit(code)
}

fn run_guest(state string, arch string, case_name string, disk string, timeout int) !int {
	init := guesthost.compile_init(state + '/sources/overlayfixture/core.v', state, arch, false)!
	os.mkdir_all(state + '/rootfs')!
	os.write_file(state + '/rootfs/overlay-case', case_name)!
	archive := guesthost.image(init, state)!
	if arch == 'x86_64' && case_name != 'atomic' {
		os.setenv('VINIX_CMDLINE', os.getenv('VINIX_CMDLINE') + ' vinix.disk=auto', true)
	}
	configured := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	mut command := configured.command.clone()
	if case_name != 'atomic' {
		command << if arch == 'aarch64' {
			['-drive', 'if=none,format=raw,file=' + disk + ',id=overlay-data', '-device',
				'virtio-blk-device,drive=overlay-data']
		} else {
			['-drive', 'if=ide,format=raw,file=' + disk]
		}
	}
	mut expected := ['OVERLAY GUEST: PASS']
	if case_name in ['atomic', 'all'] { expected << 'OVERLAY REPLACE: PASS' }
	if case_name in ['failure', 'all'] { expected << 'OVERLAY BACKEND FAILURE: PASS' }
	if case_name in ['disk', 'all'] {
		expected << ['OVERLAY DISK: PASS', 'OVERLAY PERSISTENCE: PASS', 'OVERLAY WHITEOUT: PASS',
			'OVERLAY PRIVATE WORK: PASS', 'OVERLAY RECREATION PERSISTENCE: PASS']
	}
	if case_name == 'all' { expected << 'OVERLAY REMOVED WORK: PASS' }
	if case_name in ['opaque', 'all'] {
		expected << ['OVERLAY OPAQUE CHANGES: PASS', 'OVERLAY OPAQUE REMOUNT: PASS']
	}
	if case_name == 'opaque-full' { expected << 'OVERLAY OPAQUE STORAGE FULL: PASS' }
	positive, negative := guesthost.verdict_policy(expected, ['FAIL: overlay'], false)
	return guesthost.boot(command, configured.env, state, positive, negative, timeout, true)!
}
