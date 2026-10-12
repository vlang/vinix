// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import os

fn qualify(work string) ! {
	os.mkdir(work)!
	for version in ['v3', 'v4', 'v6'] {
		state := work + '/x86-' + version
		context := campaignhost.Context{root: hosttest.root(), state: state, origin: work + '/origin'}
		assert campaignhost.prepare_x86(context, version)! == 0
		config := campaignhost.read_json(state + '/config.json')!
		assert campaignhost.strings(config['compile_flags']!)! == campaignhost.verification_flags
		assert config['source_sha256']!.str() == campaignhost.digest(hosttest.root() + '/tests/user-alloc/verify.c')!
		assert os.read_file(state + '/rootfs/sbin/init')! == campaignhost.verification_script(version)!
		for policy in ['optimized', 'disabled'] {
			manifest := config['libc_builds']!.as_map()[policy]!.as_map()
			assert campaignhost.digest(state + '/rootfs/root/libcs/' + policy + '/libc.a')! == manifest['libc_a_sha256']!.str()
			assert campaignhost.digest(state + '/rootfs/root/libcs/' + policy + '/libc.so')! == manifest['libc_so_sha256']!.str()
		}
		assert campaignhost.archive_bytes(state + '/initramfs.tar', './sbin/init')!.bytestr() == campaignhost.verification_script(version)!
		mut refused := false
		campaignhost.prepare_x86(context, version) or { refused = true }
		assert refused
		println('REAL X86 PREPARATION / pinned libraries / unchanged guest script / archive payload / protected target: PASS ' + version)
		flush_stdout()
	}
	for version in ['v5', 'v6'] {
		state := work + '/arm-' + version
		os.mkdir(state)!
		context := campaignhost.Context{root: hosttest.root(), state: state, origin: work + '/origin'}
		assert campaignhost.prepare_arm(context, version)! == 0
		build := campaignhost.read_json(state + '/build.json')!
		assert build['compiler']!.str().contains('14.2.0')
		assert build['kernel_sha256']!.str() == campaignhost.digest(state + '/kernel/bin/vinix')!
		assert build['initramfs_sha256']!.str() == campaignhost.digest(state + '/initramfs.tar')!
		for path, hash in build['artifacts_sha256']!.as_map() {
			assert campaignhost.digest(state + '/rootfs/' + path)! == hash.str()
		}
		for value in build['commands']!.as_array() {
			assert campaignhost.strings(value)!.any(it.starts_with(state + '/')), 'compile did not use isolated state'
		}
		println('REAL ARM PREPARATION / preserved cross-GCC commands / isolated rootfs and sysroots / libraries, sources, kernel and archive evidence: PASS ' + version)
		flush_stdout()
	}
	os.write_file(work + '/passed', 'PASS\n')!
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-preparation NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
