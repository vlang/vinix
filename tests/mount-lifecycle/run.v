// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct Receipt {
	architecture string
	case_name string
	context string = 'native Vinix QEMU guest; private tmpfs mounts; root and UID/GID 1000 checks; networking disabled'
	inputs map[string]string
	exit_code int
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--case', value: true, choices: ['flags', 'move', 'identities', 'id-0', 'id-1', 'id-2', 'id-3', 'id-4', 'id-5', 'id-6', 'admission', 'ad-0', 'ad-1', 'ad-2', 'ad-3', 'ad-4', 'ad-5', 'ad-6', 'ad-7', 'propagation', 'pr-0', 'pr-1', 'pr-2', 'pr-3', 'pr-4', 'pivot', 'pv-0', 'pv-1', 'pv-2', 'pv-3', 'pv-4', 'pv-5', 'pv-6', 'pivot-life', 'pl-0', 'pl-1', 'pl-2', 'pl-3', 'pivot-alias', 'pa-0', 'pa-1', 'pa-2', 'pa-3', 'pa-4', 'pivot-threads', 'pt-0', 'pt-1', 'pt-2', 'pt-3', 'pt-4', 'pt-5', 'pt-6', 'bind-policy', 'bp-0', 'bp-1', 'bp-2', 'bp-3', 'bp-4', 'truncate', 'tr-0', 'tr-1', 'tr-2', 'tr-3', 'tr-4', 'tr-5', 'metadata', 'mp-0', 'mp-1', 'mp-2', 'mp-3', 'mp-4', 'mp-5', 'mp-6', 'times', 'tp-0', 'tp-1', 'tp-2', 'tp-3', 'tp-4', 'tp-5', 'tp-6', 'tp-7', 'xattrs', 'xp-0', 'xp-1', 'xp-2', 'xp-3', 'xp-4', 'xp-5', 'xp-6', 'xp-7', 'inode-flags', 'ip-0', 'ip-1', 'ip-2', 'ip-3', 'ip-4', 'ip-5', 'ip-6', 'ip-7', 'symlinks', 'sp-0', 'sp-1', 'sp-2', 'sp-3', 'sp-4', 'sp-5', 'sp-6', 'sp-7', 'unlinks', 'up-0', 'up-1', 'up-2', 'up-3', 'up-4', 'up-5', 'up-6', 'up-7', 'links', 'lp-0', 'lp-1', 'lp-2', 'lp-3', 'lp-4', 'lp-5', 'lp-6', 'lp-7', 'lp-8', 'lp-9', 'renames', 'rp-0', 'rp-1', 'rp-2', 'rp-3', 'rp-4', 'rp-5', 'rp-6', 'rp-7', 'rp-8', 'rp-9', 'writers', 'wr-0', 'wr-1', 'wr-2', 'wr-3', 'wr-4', 'wr-5', 'wr-6', 'wr-7', 'wr-8', 'wr-9', 'nodes', 'nd-0', 'nd-1', 'nd-2', 'nd-3', 'nd-4', 'nd-5', 'nd-6', 'nd-7', 'access', 'ac-0', 'ac-1', 'ac-2', 'ac-3', 'ac-4', 'ac-5', 'ac-6', 'ac-7', 'ac-8', 'ac-9', 'fsflags', 'sf-0', 'sf-1', 'sf-2', 'sf-3', 'sf-4', 'sf-5', 'sf-6', 'sf-7', 'sf-8', 'sf-9', 'descmeta', 'dm-0', 'dm-1', 'dm-2', 'dm-3', 'dm-4', 'dm-5', 'dm-6', 'dm-7', 'desctimes', 'dt-0', 'dt-1', 'dt-2', 'dt-3', 'dt-4', 'dt-5', 'dt-6', 'dt-7', 'descxattrs', 'dx-0', 'dx-1', 'dx-2', 'dx-3', 'dx-4', 'dx-5', 'dx-6', 'dx-7', 'descflags', 'df-0', 'df-1', 'df-2', 'df-3', 'df-4', 'df-5', 'descmaps', 'mm-0', 'mm-1', 'mm-2', 'mm-3', 'mm-4', 'mm-5', 'descaccess', 'da-0', 'da-1', 'da-2', 'da-3', 'da-4', 'da-5', 'da-6', 'da-7', 'descexec', 'de-0', 'de-1', 'de-2', 'de-3', 'de-4', 'de-5', 'de-6', 'de-7', 'descwx', 'dw-0', 'dw-1', 'dw-2', 'dw-3', 'dw-4', 'dw-5', 'dw-6', 'dw-7', 'all'] },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--probe-state', value: true },
	], [], 'Usage: run.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR [--case flags|move|identities|id-0..id-6|admission|ad-0..ad-7|propagation|pr-0..pr-4|pivot|pv-0..pv-6|pivot-life|pl-0..pl-3|pivot-alias|pa-0..pa-4|pivot-threads|pt-0..pt-6|bind-policy|bp-0..bp-4|truncate|tr-0..tr-5|metadata|mp-0..mp-6|times|tp-0..tp-7|xattrs|xp-0..xp-7|inode-flags|ip-0..ip-7|symlinks|sp-0..sp-7|unlinks|up-0..up-7|links|lp-0..lp-9|renames|rp-0..rp-9|writers|wr-0..wr-9|nodes|nd-0..nd-7|access|ac-0..ac-9|fsflags|sf-0..sf-9|descmeta|dm-0..dm-7|desctimes|dt-0..dt-7|descxattrs|dx-0..dx-7|descflags|df-0..df-5|descmaps|mm-0..mm-5|descaccess|da-0..da-7|descexec|de-0..de-7|descwx|dw-0..dw-7|all] [--timeout SECONDS] [--probe-state RECEIPT-DIR]')!
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) { eprintln('missing ' + key); exit(2) }
	}
	arch := options.value('--arch', '')
	selected := options.value('--case', 'all')
	probe_state := options.value('--probe-state', '')
	state := os.abs_path(options.value('--state-dir', ''))
	timeout := options.integer('--timeout', 180)!
	if os.exists(state) || timeout <= 0 { eprintln('state must be fresh and timeout positive'); exit(2) }
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(kernel[18]) + (int(kernel[19]) << 8) != machine {
		eprintln('kernel must be matching little-endian ELF64'); exit(2)
	}
	os.mkdir_all(state + '/kernel/bin')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	os.mkdir_all(state + '/sources')!
	hosttest.module_copy_tree(@DIR + '/mountfixture', state + '/sources/mountfixture')!
	mut inputs := {
		'kernel': sha256.sum(kernel).hex()
		'fixture': digest(state + '/sources/mountfixture/core.v')!
		'identities_fixture': digest(state + '/sources/mountfixture/identities.v')!
		'admission_fixture': digest(state + '/sources/mountfixture/admission.v')!
		'propagation_fixture': digest(state + '/sources/mountfixture/propagation.v')!
		'pivot_fixture': digest(state + '/sources/mountfixture/pivot.v')!
		'pivot_lifecycle_fixture': digest(state + '/sources/mountfixture/pivot_lifecycle.v')!
		'pivot_alias_fixture': digest(state + '/sources/mountfixture/pivot_aliases.v')!
		'pivot_thread_fixture': digest(state + '/sources/mountfixture/pivot_threads.v')!
		'bind_policy_fixture': digest(state + '/sources/mountfixture/bind_policy.v')!
		'truncate_fixture': digest(state + '/sources/mountfixture/truncate_policy.v')!
		'metadata_fixture': digest(state + '/sources/mountfixture/metadata_policy.v')!
		'times_fixture': digest(state + '/sources/mountfixture/timestamp_policy.v')!
		'xattr_fixture': digest(state + '/sources/mountfixture/xattr_policy.v')!
		'inode_flags_fixture': digest(state + '/sources/mountfixture/inode_flags.v')!
		'symlink_fixture': digest(state + '/sources/mountfixture/symlink_policy.v')!
		'unlink_fixture': digest(state + '/sources/mountfixture/unlink_policy.v')!
		'link_fixture': digest(state + '/sources/mountfixture/link_policy.v')!
		'rename_fixture': digest(state + '/sources/mountfixture/rename_policy.v')!
		'writer_fixture': digest(state + '/sources/mountfixture/writer_policy.v')!
		'node_fixture': digest(state + '/sources/mountfixture/mknod_policy.v')!
		'access_fixture': digest(state + '/sources/mountfixture/access_policy.v')!
		'statfs_fixture': digest(state + '/sources/mountfixture/statfs_policy.v')!
		'descriptor_metadata_fixture': digest(state + '/sources/mountfixture/descriptor_metadata.v')!
		'descriptor_times_fixture': digest(state + '/sources/mountfixture/descriptor_timestamp.v')!
		'descriptor_xattrs_fixture': digest(state + '/sources/mountfixture/descriptor_xattr.v')!
		'descriptor_flags_fixture': digest(state + '/sources/mountfixture/descriptor_flags.v')!
		'descriptor_mmaps_fixture': digest(state + '/sources/mountfixture/descriptor_mmap.v')!
		'descriptor_access_fixture': digest(state + '/sources/mountfixture/descriptor_access.v')!
		'descriptor_exec_fixture': digest(state + '/sources/mountfixture/descriptor_exec.v')!
		'descriptor_wx_fixture': digest(state + '/sources/mountfixture/descriptor_wx.v')!
		'controller': digest(@FILE)!
	}
	if probe_state != '' { inputs['probe_receipt'] = digest(os.abs_path(probe_state) + '/receipt.json')! }
	code := run_guest(state, arch, selected, timeout, probe_state) or { eprintln(err.msg()); 1 }
	for name, path in {'init': state + '/init', 'iso': state + '/test.iso', 'fixture_c': state + '/fixture.c'} {
		inputs[name] = digest(path) or { '' }
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		architecture: arch, case_name: selected, inputs: inputs, exit_code: code
	}, prettify: true) + '\n')!
	exit(code)
}

fn fixture_init(state string, arch string, probe_state string) !string {
	if probe_state == '' { return guesthost.compile_init(state + '/sources/mountfixture/core.v', state, arch, false)! }
	prior := os.abs_path(probe_state)
	receipt := json2.decode[Receipt](os.read_file(prior + '/receipt.json')!)!
	if receipt.architecture != arch { return error('cached probe architecture differs') }
	for key, file in {'fixture': 'sources/mountfixture/core.v', 'identities_fixture': 'sources/mountfixture/identities.v', 'admission_fixture': 'sources/mountfixture/admission.v', 'propagation_fixture': 'sources/mountfixture/propagation.v', 'pivot_fixture': 'sources/mountfixture/pivot.v', 'pivot_lifecycle_fixture': 'sources/mountfixture/pivot_lifecycle.v', 'pivot_alias_fixture': 'sources/mountfixture/pivot_aliases.v', 'pivot_thread_fixture': 'sources/mountfixture/pivot_threads.v', 'bind_policy_fixture': 'sources/mountfixture/bind_policy.v', 'truncate_fixture': 'sources/mountfixture/truncate_policy.v', 'metadata_fixture': 'sources/mountfixture/metadata_policy.v', 'times_fixture': 'sources/mountfixture/timestamp_policy.v', 'xattr_fixture': 'sources/mountfixture/xattr_policy.v', 'inode_flags_fixture': 'sources/mountfixture/inode_flags.v', 'symlink_fixture': 'sources/mountfixture/symlink_policy.v', 'unlink_fixture': 'sources/mountfixture/unlink_policy.v', 'link_fixture': 'sources/mountfixture/link_policy.v', 'rename_fixture': 'sources/mountfixture/rename_policy.v', 'writer_fixture': 'sources/mountfixture/writer_policy.v', 'node_fixture': 'sources/mountfixture/mknod_policy.v', 'access_fixture': 'sources/mountfixture/access_policy.v', 'statfs_fixture': 'sources/mountfixture/statfs_policy.v', 'descriptor_metadata_fixture': 'sources/mountfixture/descriptor_metadata.v', 'descriptor_times_fixture': 'sources/mountfixture/descriptor_timestamp.v', 'descriptor_xattrs_fixture': 'sources/mountfixture/descriptor_xattr.v', 'descriptor_flags_fixture': 'sources/mountfixture/descriptor_flags.v', 'descriptor_mmaps_fixture': 'sources/mountfixture/descriptor_mmap.v', 'descriptor_access_fixture': 'sources/mountfixture/descriptor_access.v', 'descriptor_exec_fixture': 'sources/mountfixture/descriptor_exec.v', 'descriptor_wx_fixture': 'sources/mountfixture/descriptor_wx.v'} {
		if receipt.inputs[key] != digest(prior + '/' + file)! || receipt.inputs[key] != digest(state + '/' + file)! {
			return error('cached probe source differs: ' + file)
		}
	}
	for key, file in {'init': 'init', 'fixture_c': 'fixture.c'} {
		if receipt.inputs[key] != digest(prior + '/' + file)! { return error('cached probe artifact differs: ' + file) }
		os.cp(prior + '/' + file, state + '/' + file)!
	}
	bytes := os.read_bytes(state + '/init')!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(bytes[18]) + (int(bytes[19]) << 8) != machine { return error('cached probe ELF architecture differs') }
	return state + '/init'
}

fn run_guest(state string, arch string, selected string, timeout int, probe_state string) !int {
	init := fixture_init(state, arch, probe_state)!
	os.mkdir_all(state + '/rootfs')!
	os.write_file(state + '/rootfs/mount-case', selected)!
	archive := guesthost.image(init, state)!
	configured := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	mut expected := ['MOUNT LIFECYCLE: PASS']
	if selected in ['flags', 'all'] { expected << 'MOUNT UNMOUNT MODES: PASS' }
	if selected in ['move', 'all'] { expected << ['MOUNT MOVE CYCLES: PASS', 'MOUNT REPARENTED HOLDERS: PASS', 'MOUNT MOVE DEPTH: PASS'] }
	if selected in ['identities', 'all'] {
		expected << 'MOUNT IDENTITIES: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT IDENTITY CASE: ${kind} PASS' }
	} else if selected.starts_with('id-') {
		expected << ['MOUNT IDENTITIES: PASS', 'MOUNT IDENTITY CASE: ' + selected.all_after('id-') + ' PASS']
	}
	if selected in ['admission', 'all'] {
		expected << 'MOUNT ADMISSION: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT ADMISSION CASE: ${kind} PASS' }
	} else if selected.starts_with('ad-') {
		expected << ['MOUNT ADMISSION: PASS', 'MOUNT ADMISSION CASE: ' + selected.all_after('ad-') + ' PASS']
	}
	if selected in ['propagation', 'all'] {
		expected << 'MOUNT PROPAGATION VALIDATION: PASS'
		for kind in 0 .. 5 { expected << 'MOUNT PROPAGATION CASE: ${kind} PASS' }
	} else if selected.starts_with('pr-') {
		expected << ['MOUNT PROPAGATION VALIDATION: PASS', 'MOUNT PROPAGATION CASE: ' + selected.all_after('pr-') + ' PASS']
	}
	if selected in ['pivot', 'all'] {
		expected << 'MOUNT PIVOT ADMISSION: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT PIVOT CASE: ${kind} PASS' }
	} else if selected.starts_with('pv-') {
		expected << ['MOUNT PIVOT ADMISSION: PASS', 'MOUNT PIVOT CASE: ' + selected.all_after('pv-') + ' PASS']
	}
	if selected in ['pivot-life', 'all'] {
		expected << 'MOUNT PIVOT LIFECYCLE: PASS'
		for kind in 0 .. 4 { expected << 'MOUNT PIVOT LIFE CASE: ${kind} PASS' }
	} else if selected.starts_with('pl-') {
		expected << ['MOUNT PIVOT LIFECYCLE: PASS', 'MOUNT PIVOT LIFE CASE: ' + selected.all_after('pl-') + ' PASS']
	}
	if selected in ['pivot-alias', 'all'] {
		expected << 'MOUNT PIVOT ALIASES: PASS'
		for kind in 0 .. 5 { expected << 'MOUNT PIVOT ALIAS CASE: ${kind} PASS' }
	} else if selected.starts_with('pa-') {
		expected << ['MOUNT PIVOT ALIASES: PASS', 'MOUNT PIVOT ALIAS CASE: ' + selected.all_after('pa-') + ' PASS']
	}
	if selected in ['pivot-threads', 'all'] {
		expected << 'MOUNT PIVOT THREADS: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT PIVOT THREAD CASE: ${kind} PASS' }
	} else if selected.starts_with('pt-') {
		expected << ['MOUNT PIVOT THREADS: PASS', 'MOUNT PIVOT THREAD CASE: ' + selected.all_after('pt-') + ' PASS']
	}
	if selected in ['bind-policy', 'all'] {
		expected << 'MOUNT BIND POLICY: PASS'
		for kind in 0 .. 5 { expected << 'MOUNT BIND POLICY CASE: ${kind} PASS' }
	} else if selected.starts_with('bp-') {
		expected << ['MOUNT BIND POLICY: PASS', 'MOUNT BIND POLICY CASE: ' + selected.all_after('bp-') + ' PASS']
	}
	if selected in ['truncate', 'all'] {
		expected << 'MOUNT TRUNCATE: PASS'
		for kind in 0 .. 6 { expected << 'MOUNT TRUNCATE CASE: ${kind} PASS' }
	} else if selected.starts_with('tr-') {
		expected << ['MOUNT TRUNCATE: PASS', 'MOUNT TRUNCATE CASE: ' + selected.all_after('tr-') + ' PASS']
	}
	if selected in ['metadata', 'all'] {
		expected << 'MOUNT METADATA: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT METADATA CASE: ${kind} PASS' }
	} else if selected.starts_with('mp-') {
		expected << ['MOUNT METADATA: PASS', 'MOUNT METADATA CASE: ' + selected.all_after('mp-') + ' PASS']
	}
	if selected in ['times', 'all'] {
		expected << 'MOUNT TIMES: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT TIMES CASE: ${kind} PASS' }
	} else if selected.starts_with('tp-') {
		expected << ['MOUNT TIMES: PASS', 'MOUNT TIMES CASE: ' + selected.all_after('tp-') + ' PASS']
	}
	if selected in ['xattrs', 'all'] {
		expected << 'MOUNT XATTR: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT XATTR CASE: ${kind} PASS' }
	} else if selected.starts_with('xp-') {
		expected << ['MOUNT XATTR: PASS', 'MOUNT XATTR CASE: ' + selected.all_after('xp-') + ' PASS']
	}
	if selected in ['inode-flags', 'all'] {
		expected << 'MOUNT INODE FLAGS: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT INODE FLAGS CASE: ${kind} PASS' }
	} else if selected.starts_with('ip-') {
		expected << ['MOUNT INODE FLAGS: PASS', 'MOUNT INODE FLAGS CASE: ' + selected.all_after('ip-') + ' PASS']
	}
	if selected in ['symlinks', 'all'] {
		expected << 'MOUNT SYMLINK: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT SYMLINK CASE: ${kind} PASS' }
	} else if selected.starts_with('sp-') {
		expected << ['MOUNT SYMLINK: PASS', 'MOUNT SYMLINK CASE: ' + selected.all_after('sp-') + ' PASS']
	}
	if selected in ['unlinks', 'all'] {
		expected << 'MOUNT UNLINK: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT UNLINK CASE: ${kind} PASS' }
	} else if selected.starts_with('up-') {
		expected << ['MOUNT UNLINK: PASS', 'MOUNT UNLINK CASE: ' + selected.all_after('up-') + ' PASS']
	}
	if selected in ['links', 'all'] {
		expected << 'MOUNT LINK: PASS'
		for kind in 0 .. 10 { expected << 'MOUNT LINK CASE: ${kind} PASS' }
	} else if selected.starts_with('lp-') {
		expected << ['MOUNT LINK: PASS', 'MOUNT LINK CASE: ' + selected.all_after('lp-') + ' PASS']
	}
	if selected in ['renames', 'all'] {
		expected << 'MOUNT RENAME: PASS'
		for kind in 0 .. 10 { expected << 'MOUNT RENAME CASE: ${kind} PASS' }
	} else if selected.starts_with('rp-') {
		expected << ['MOUNT RENAME: PASS', 'MOUNT RENAME CASE: ' + selected.all_after('rp-') + ' PASS']
	}
	if selected in ['writers', 'all'] {
		expected << 'MOUNT WRITERS: PASS'
		for kind in 0 .. 10 { expected << 'MOUNT WRITER CASE: ${kind} PASS' }
	} else if selected.starts_with('wr-') {
		expected << ['MOUNT WRITERS: PASS', 'MOUNT WRITER CASE: ' + selected.all_after('wr-') + ' PASS']
	}
	if selected in ['nodes', 'all'] {
		expected << 'MOUNT NODES: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT NODE CASE: ${kind} PASS' }
	} else if selected.starts_with('nd-') {
		expected << ['MOUNT NODES: PASS', 'MOUNT NODE CASE: ' + selected.all_after('nd-') + ' PASS']
	}
	if selected in ['access', 'all'] {
		expected << 'MOUNT ACCESS: PASS'
		for kind in 0 .. 10 { expected << 'MOUNT ACCESS CASE: ${kind} PASS' }
	} else if selected.starts_with('ac-') {
		expected << ['MOUNT ACCESS: PASS', 'MOUNT ACCESS CASE: ' + selected.all_after('ac-') + ' PASS']
	}
	if selected in ['fsflags', 'all'] {
		expected << 'MOUNT FSFLAGS: PASS'
		for kind in 0 .. 10 { expected << 'MOUNT FSFLAGS CASE: ${kind} PASS' }
	} else if selected.starts_with('sf-') {
		expected << ['MOUNT FSFLAGS: PASS', 'MOUNT FSFLAGS CASE: ' + selected.all_after('sf-') + ' PASS']
	}
	if selected in ['descmeta', 'all'] {
		expected << 'MOUNT DESCMETA: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCMETA CASE: ${kind} PASS' }
	} else if selected.starts_with('dm-') {
		expected << ['MOUNT DESCMETA: PASS', 'MOUNT DESCMETA CASE: ' + selected.all_after('dm-') + ' PASS']
	}
	if selected in ['desctimes', 'all'] {
		expected << 'MOUNT DESCTIMES: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCTIMES CASE: ${kind} PASS' }
	} else if selected.starts_with('dt-') {
		expected << ['MOUNT DESCTIMES: PASS', 'MOUNT DESCTIMES CASE: ' + selected.all_after('dt-') + ' PASS']
	}
	if selected in ['descxattrs', 'all'] {
		expected << 'MOUNT DESCXATTR: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCXATTR CASE: ${kind} PASS' }
	} else if selected.starts_with('dx-') {
		expected << ['MOUNT DESCXATTR: PASS', 'MOUNT DESCXATTR CASE: ' + selected.all_after('dx-') + ' PASS']
	}
	if selected in ['descflags', 'all'] {
		expected << 'MOUNT DESCFLAGS: PASS'
		for kind in 0 .. 6 { expected << 'MOUNT DESCFLAGS CASE: ${kind} PASS' }
	} else if selected.starts_with('df-') {
		expected << ['MOUNT DESCFLAGS: PASS', 'MOUNT DESCFLAGS CASE: ' + selected.all_after('df-') + ' PASS']
	}
	if selected in ['descmaps', 'all'] {
		expected << 'MOUNT DESCMAP: PASS'
		for kind in 0 .. 6 { expected << 'MOUNT DESCMAP CASE: ${kind} PASS' }
	} else if selected.starts_with('mm-') {
		expected << ['MOUNT DESCMAP: PASS', 'MOUNT DESCMAP CASE: ' + selected.all_after('mm-') + ' PASS']
	}
	if selected in ['descaccess', 'all'] {
		expected << 'MOUNT DESCACCESS: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCACCESS CASE: ${kind} PASS' }
	} else if selected.starts_with('da-') {
		expected << ['MOUNT DESCACCESS: PASS', 'MOUNT DESCACCESS CASE: ' + selected.all_after('da-') + ' PASS']
	}
	if selected in ['descexec', 'all'] {
		expected << 'MOUNT DESCEXEC: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCEXEC CASE: ${kind} PASS' }
	} else if selected.starts_with('de-') {
		expected << ['MOUNT DESCEXEC: PASS', 'MOUNT DESCEXEC CASE: ' + selected.all_after('de-') + ' PASS']
	}
	if selected in ['descwx', 'all'] {
		expected << 'MOUNT DESCWX: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT DESCWX CASE: ${kind} PASS' }
	} else if selected.starts_with('dw-') {
		expected << ['MOUNT DESCWX: PASS', 'MOUNT DESCWX CASE: ' + selected.all_after('dw-') + ' PASS']
	}
	positive, negative := guesthost.verdict_policy(expected, ['MOUNT LIFECYCLE FAIL:'], false)
	return guesthost.boot(configured.command, configured.env, state, positive, negative, timeout, true)!
}
