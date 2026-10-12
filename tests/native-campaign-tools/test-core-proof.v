// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import coreboot
import corevm.corepolicy
import crypto.sha256
import hosttest
import os

fn cases() ! {
	root := hosttest.root()
	base := root + '/tests/alloc-bench/results/2026-10-03-userspace-v6/validation'
	source_path := root + '/build/useralloc-kernel-speed-v5/core-x86_64/test.c'
	assert campaignhost.digest(source_path)! == campaignhost.core_test
	source := campaignhost.text(source_path)!
	for mode in ['x86_64', 'x86_64-four-level', 'aarch64'] {
		state := base + '/core-' + mode
		bytes := os.read_bytes(state + '/serial.log')!
		manifest := campaignhost.read_json(state + '/run.json')!
		actual := campaignhost.core_records(bytes, source, mode, manifest)!
		for key in ['all_source_core_pass_marker_count', 'la57_256tib_boundary_pass', 'cpuid_la57_disabled_explicit_skip', 'boundary_supplement_pass', 'all_core_markers_pass', 'pagetable_check_pass_count', 'persistent_second_boot_pass', 'required_marker_count'] {
			if key in actual { assert actual[key]! == manifest[key]!, mode + ' ' + key }
		}
		mut required := corepolicy.required(false, mode != 'aarch64')
		required << campaignhost.source_markers(source).filter(mode != 'aarch64' || !it.contains('QEMU CORE PASS: x86-64 '))
		required << 'PAGETABLE CHECK: PASS'
		if mode == 'aarch64' { required << 'VINIX QEMU CORE PERSIST: PASS' }
		for marker in required {
			for changed in [bytes.bytestr().replace(marker, ''), bytes.bytestr() + '\n' + marker + '\n'] {
				campaignhost.core_records(changed.bytes(), source, mode, manifest) or { continue }
				return error('missing or duplicate core marker accepted: ' + mode + ' ' + marker)
			}
		}
		for marker in [...corepolicy.core_fail_markers, 'PAGETABLE FAIL', 'ERROR:'] {
			campaignhost.core_records((bytes.bytestr() + '\n' + marker).bytes(), source, mode, manifest) or { continue }
			return error('core failure marker accepted: ' + marker)
		}
		mut failure := campaignhost.copy_record(manifest)!
		failure['harness_exit_code'] = u64(4294967296)
		campaignhost.core_records(bytes, source, mode, failure) or { continue }
		return error('wide nonzero core exit was narrowed to zero')
	}
	assert campaignhost.source_markers('puts("QEMU CORE PASS: one"); puts("QEMU CORE PASS:"); puts("QEMU CORE PASS: two\nthree"); puts("QEMU CORE PASS: one");') == ['QEMU CORE PASS: one', 'QEMU CORE PASS: one']
	println('CORE PROOF / three immutable full guest modes / exact source-derived and harness markers / every missing and duplicate marker / failure records and wide exits: PASS')
	boot := root + '/third_party/useralloc-speed-v5/run-aarch64.sh'
	bytes := os.read_bytes(boot)!
	original_hash := sha256.sum(bytes).hex()
	server := "/tmp/native package's server"
	translated := coreboot.translated(bytes.bytestr(), '/private/frozen kernel', server)!
	assert !translated.contains('python3')
	assert translated.contains('SCRIPT_DIR=' + hosttest.shell_quote('/private/frozen kernel'))
	assert translated.contains(hosttest.shell_quote(server) + ' \\\n    --store')
	assert translated.contains(hosttest.shell_quote(root + '/build-support/venus/prepare-qemu'))
	assert sha256.sum(os.read_bytes(boot)!).hex() == original_hash
	for pattern in ['python3 "$SCRIPT_DIR/tools/qemu-package-store.py"', 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"'] {
		coreboot.translated(bytes.bytestr().replace(pattern, ''), '/root', '/server') or { continue }
		return error('changed boot adapter grammar was accepted')
	}
	processes := campaignhost.qemu_observations('12 10 /usr/bin/qemu-system-x86_64 -cdrom /state/core-x86_64/test.iso\n13 10 /usr/bin/other qemu-system-x86_64 /state/core-x86_64\n14 10 /usr/bin/qemu-system-aarch64 -drive /state/core-aarch64/vm/boot.img\n', '/state/core-x86_64', 'x86_64', '/state/core-x86_64')!
	assert processes == ['12 10 /usr/bin/qemu-system-x86_64 -cdrom /state/core-x86_64/test.iso']
	println('CORE ADAPTER / frozen boot bytes unchanged / native package and Venus commands / literal roots and quoted executable paths / altered inputs rejected / actual QEMU process filtering: PASS')
}

fn file_cases() ! {
	root := hosttest.root()
	work := hosttest.work_dir('', 'vinix-core-proof')!
	defer { hosttest.remove_work_dir(work) or {} }
	path := work + '/serial.log'
	campaignhost.create_capture(path)!
	os.write_file(path, 'retained failed capture')!
	campaignhost.create_capture(path) or {
		assert os.read_file(path)! == 'retained failed capture'
		os.symlink(path, work + '/link')!
		campaignhost.create_capture(work + '/link') or {
			assert os.read_file(path)! == 'retained failed capture'
			for arch in ['x86_64', 'aarch64'] {
				source := root + '/build/useralloc-core-v6/core-' + arch
				expected := campaignhost.read_json(root + '/tests/alloc-bench/results/2026-10-03-userspace-v6/validation/core-' + arch + '/compile.json')!
				assert campaignhost.digest(source + '/initramfs.tar')! == expected['initramfs_sha256']!.str()
				output := work + '/' + arch + '.tar'
				campaignhost.deterministic_archive(source + '/rootfs', output)!
				assert campaignhost.digest(output)! == expected['initramfs_sha256']!.str(), 'deterministic core archive differs: ' + arch
			}
			println('CORE FILES / exclusive capture admission / existing logs and destination links retained / byte-identical immutable ARM and x86 USTAR images: PASS')
			return
		}
		return error('existing capture link was accepted')
	}
	return error('existing capture was overwritten')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--files' { file_cases() or { eprintln(err); exit(1) }; return }
	cases() or { eprintln(err); exit(1) }
	file_cases() or { eprintln(err); exit(1) }
}
