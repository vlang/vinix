// SPDX-License-Identifier: GPL-2.0-or-later
// Finite host fixtures only. No original input is changed and no VM is launched.
module reuseprofile

import os

fn control_original() Original {
	return Original{root: runtime_root, base: base_root, arguments: arguments(),
		command: command_for(origin_state + '/root.ext2', original_socket), socket: original_socket,
		inputs: required_original_pins(), base_manifest: base_manifest_sha, staged_manifest: staged_manifest_sha,
		storage: 'apfs-clone', sysroot: sysroot, sysroot_manifest: sysroot_manifest_sha,
		gcc: gcc_root, gcc_manifest: gcc_manifest_sha}
}

fn refused_original(p Original) ! {
	mut refused := false
	validate_original(p) or { refused = true }
	require(refused, 'changed original document was accepted')!
}

fn refused_prepared(c Contract, p Prepared) ! {
	mut refused := false
	c.validate_document(p) or { refused = true }
	require(refused, 'changed prepared document was accepted')!
}

fn refused_disk(state string, expected string) ! {
	mut failure := ''
	verify_new_disk(state) or { failure = err.msg() }
	require(failure == expected, 'disk refusal differs: ' + failure)!
}

pub fn selfcheck(state string) ![]string {
	require(state == canonical_destination(state)! && !os.exists(state) && !os.is_link(state),
		'host contract controls require fresh canonical directory')!
	os.mkdir(state)!
	mut checks := []string{}
	original := control_original()
	validate_original(original)!
	checks << 'positive fixed original document (fixture only, no original authority claim)'
	for changed in [
		Original{...original, root: runtime_root + '-other'},
		Original{...original, base: base_root + '-other'},
		Original{...original, storage: 'copy'},
		Original{...original, base_manifest: '0'.repeat(64)},
		Original{...original, staged_manifest: '0'.repeat(64)},
		Original{...original, sysroot: sysroot + '-other'},
		Original{...original, gcc: gcc_root + '-other'},
		Original{...original, sysroot_manifest: '0'.repeat(64)},
		Original{...original, gcc_manifest: '0'.repeat(64)},
		Original{...original, socket: original_socket + '-other'},
	] { refused_original(changed)! }
	checks << 'ten original root/storage/manifest/socket alterations refused'
	for index in 0 .. original.arguments.len {
		mut args := original.arguments.clone()
		args[index] += '-altered'
		refused_original(Original{...original, arguments: args})!
	}
	checks << 'every fixed workload argument alteration refused'
	for index in 0 .. original.command.len {
		mut command := original.command.clone()
		command[index] += '-altered'
		refused_original(Original{...original, command: command})!
	}
	checks << 'every fixed QEMU argument alteration refused'
	for path, _ in required_original_pins() {
		mut pins := original.inputs.clone()
		pins.delete(path)
		refused_original(Original{...original, inputs: pins})!
	}
	checks << 'every required original content pin omission refused'
	c := Contract{original: original, state: retry_root + '/synthetic-contract-control',
		adapter: os.real_path(os.executable()), adapter_sha256: hash(os.executable())!}
	p := c.prepared('a'.repeat(64))!
	c.validate_document(p)!
	require(p.command == expected_command(c.state) && p.inputs[origin_state + '/root.ext2'] == frozen_origin_disk_sha
		&& p.inputs[disk_path(c.state)] == 'a'.repeat(64), 'new writable and frozen historical disk identities differ')!
	checks << 'positive new document preserves historical disk and distinct new mutable disk'
	for changed in [
		Prepared{...p, arch: 'aarch64'}, Prepared{...p, root: runtime_root + '-other'},
		Prepared{...p, base: base_root + '-other'}, Prepared{...p, storage: 'apfs-clone'},
		Prepared{...p, socket: original_socket}, Prepared{...p, reuse_origin: retry_root},
		Prepared{...p, reuse_prepared_sha256: '0'.repeat(64)},
		Prepared{...p, reuse_manifest_sha256: '0'.repeat(64)},
	] { refused_prepared(c, changed)! }
	checks << 'eight new-document authority/storage alterations refused'
	for index in 0 .. p.command.len {
		mut command := p.command.clone()
		command[index] += '-altered'
		refused_prepared(c, Prepared{...p, command: command})!
	}
	checks << 'every new QEMU argument alteration refused'
	mut missing := p.inputs.clone()
	missing.delete(origin_manifest)
	refused_prepared(c, Prepared{...p, inputs: missing})!
	mut extra := p.inputs.clone()
	extra[c.state + '/another-mutable.ext2'] = 'b'.repeat(64)
	refused_prepared(c, Prepared{...p, inputs: extra})!
	mut old_disk := p.inputs.clone()
	old_disk[origin_state + '/root.ext2'] = original_disk_sha
	refused_prepared(c, Prepared{...p, inputs: old_disk})!
	checks << 'missing authority, extra mutable key and historical disk reset refused'
	mut bad_digest := false
	c.prepared('not-a-sha256') or { bad_digest = true }
	require(bad_digest, 'invalid initial disk digest accepted')!
	checks << 'invalid initial workload digest refused'
	for path in [origin_state + '/new', retry_root, retry_root + '/../escape', retry_root + '//double',
		retry_root + '/trailing/', retry_root + '/nul\x00suffix'] {
		mut refused := false
		validate_contract(Contract{...c, state: path}) or { refused = true }
		require(refused, 'invalid prepared output path accepted')!
	}
	checks << 'outside, parent, dot, doubled, trailing and NUL outputs refused'
	os.mkdir(state + '/real-parent')!
	os.symlink(state + '/real-parent', state + '/alias-parent')!
	require(canonical_destination(state + '/alias-parent/new')! != state + '/alias-parent/new',
		'output ancestor symlink escaped canonicalization')!
	checks << 'real ancestor symlink detected'
	fresh_destination(state + '/absent-prepared')!
	os.mkdir(state + '/existing-prepared')!
	mut existing_refused := false
	fresh_destination(state + '/existing-prepared') or { existing_refused = true }
	require(existing_refused, 'existing prepared directory was accepted')!
	os.symlink('/absent-owned-prepared-fixture', state + '/prepared-link')!
	mut link_refused := false
	fresh_destination(state + '/prepared-link') or { link_refused = true }
	require(link_refused, 'prepared destination symlink was accepted')!
	checks << 'shared fresh-prepared guard accepts absent and refuses existing/symlink outputs'
	os.write_file(state + '/hash-input', 'independent tiny original\n')!
	pin := hash(state + '/hash-input')!
	os.cp(state + '/hash-input', state + '/hash-copy', fail_if_exists: true)!
	os.write_file(state + '/hash-copy', 'altered independent copy\n')!
	require(hash(state + '/hash-input')! == pin && hash(state + '/hash-copy')! != pin,
		'copy alteration changed original or escaped hashing')!
	checks << 'real independent-file alteration leaves input unchanged'
	os.mkdir(state + '/small-disk')!
	os.write_file(state + '/small-disk/root.ext2', 'small')!
	refused_disk(state + '/small-disk', 'fresh workload disk size differs')!
	checks << 'real short ordinary disk refused by size guard'
	os.mkdir(state + '/hardlink-disk')!
	os.link(state + '/small-disk/root.ext2', state + '/hardlink-disk/root.ext2')!
	refused_disk(state + '/hardlink-disk', 'fresh workload disk must be ordinary and unaliased')!
	checks << 'real hard-linked workload disk refused before size check'
	os.mkdir(state + '/symlink-disk')!
	os.symlink(state + '/small-disk/root.ext2', state + '/symlink-disk/root.ext2')!
	refused_disk(state + '/symlink-disk', 'fresh workload disk path follows an alias')!
	checks << 'real symlink workload disk refused'
	return checks
}
