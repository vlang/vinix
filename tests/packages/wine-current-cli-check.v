// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tests.packages.winecurrent
import tests.packages.winesource

struct Report {
	scope string
	checks []string
	inputs map[string]string
}

fn fixture(path string, marker u8) !string {
	mut bytes := []u8{len: 128}
	defer { unsafe { bytes.free() } }
	bytes[0] = 0x7f
	bytes[1] = `E`
	bytes[2] = `L`
	bytes[3] = `F`
	bytes[4] = 2
	bytes[5] = 1
	bytes[6] = 1
	bytes[16] = 2
	bytes[18] = 62
	bytes[127] = marker
	os.write_file_array(path, bytes)!
	os.chmod(path, 0o755)!
	return sha256.sum(bytes).hex()
}

fn refused_admission(path string, digest string, message string) ! {
	selection := winecurrent.admit(path, digest) or {
		if !err.msg().contains(message) { return err }
		return
	}
	winecurrent.close_selection(selection)
	return error('expected current CLI admission refusal')
}

fn refused_stage(selection winecurrent.Selection, root string, message string) ! {
	staged := winecurrent.stage(selection, root) or {
		if !err.msg().contains(message) { return err }
		return
	}
	winecurrent.close_staged(staged)
	return error('expected current CLI staging refusal')
}

fn check() ! {
	if os.args.len != 2 { return error('usage: wine-current-cli-check FRESH_OUTPUT') }
	work := os.abs_path(os.args[1])
	if os.exists(work) { return error('control output already exists') }
	os.mkdir_all(work)!
	mut inputs := map[string]string{}
	for path in [@FILE, os.dir(@FILE) + '/winecurrent/admission.v', os.executable()] {
		inputs[path] = winesource.file_digest(path)!
	}
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	mut checks := []string{}
	for mode in ['process', 'metadata', 'server'] {
		if winecurrent.requested(['check', mode, 'out', 'kernel', 'extras', 'sysroot', 'gcc'])! {
			return error('historical mode selected override')
		}
	}
	checks << 'all three historical modes retain original arguments'
	if !winecurrent.requested(['check', 'server', 'o', 'k', 'e', 's', 'g', '/cli', 'digest'])! {
		return error('server override was not selected')
	}
	for mode in ['process', 'metadata'] {
		winecurrent.requested(['check', mode, 'o', 'k', 'e', 's', 'g', '/cli', 'digest']) or { continue }
		return error('override accepted outside server mode')
	}
	checks << 'override explicit and server-only'
	source := work + '/selected'
	digest := fixture(source, 1)!
	selection := winecurrent.admit(source, digest)!
	defer { winecurrent.close_selection(selection) }
	wrong := '0'.repeat(64)
	refused_admission(source, wrong, 'digest mismatch')!
	refused_admission(source, digest.to_upper(), 'lowercase SHA-256')!
	checks << 'wrong digest and noncanonical digest refused'
	os.symlink(source, work + '/source-link')!
	refused_admission(work + '/source-link', digest, 'ordinary executable')!
	checks << 'symlink input refused'
	mut malformed := os.read_bytes(source)!
	malformed[18] = 183
	os.write_file_array(work + '/arm', malformed)!
	os.chmod(work + '/arm', 0o755)!
	arm_digest := sha256.sum(malformed).hex()
	refused_admission(work + '/arm', arm_digest, 'x86_64 ELF')!
	malformed[0] = 0
	os.write_file_array(work + '/non-elf', malformed)!
	os.chmod(work + '/non-elf', 0o755)!
	non_elf_digest := sha256.sum(malformed).hex()
	refused_admission(work + '/non-elf', non_elf_digest, 'x86_64 ELF')!
	unsafe { malformed.free(); arm_digest.free(); non_elf_digest.free() }
	checks << 'wrong architecture and non-ELF refused'
	plain_digest := fixture(work + '/no-exec', 1)!
	os.chmod(work + '/no-exec', 0o644)!
	refused_admission(work + '/no-exec', plain_digest, 'ordinary executable')!
	unsafe { plain_digest.free() }
	checks << 'nonexecutable input refused'
	root := work + '/cloned'
	os.mkdir_all(root + '/usr/bin')!
	target := root + '/usr/bin/vinix-package'
	frozen := work + '/frozen-cli'
	frozen_digest := fixture(frozen, 2)!
	old_digest := fixture(target, 2)!
	staged := winecurrent.stage(selection, root)!
	defer { winecurrent.close_staged(staged) }
	if staged.previous_digest != old_digest || staged.selected_digest != digest
		|| winesource.file_digest(target)! != digest || winesource.file_digest(frozen)! != frozen_digest {
		return error('selected staging or frozen input byte comparison failed')
	}
	winecurrent.verify_staged(selection, staged, root)!
	checks << 'selected bytes staged with original target and frozen input digests retained'
	os.rm(target)!
	os.symlink(frozen, target)!
	refused_stage(selection, root, 'ordinary executable')!
	if winesource.file_digest(frozen)! != frozen_digest { return error('target link referent changed') }
	os.rm(target)!
	fixture(target, 2)!
	checks << 'target link refused without changing referent'
	os.mv(root + '/usr/bin', root + '/usr/real-bin')!
	os.symlink(root + '/usr/real-bin', root + '/usr/bin')!
	refused_stage(selection, root, 'ordinary directories')!
	os.rm(root + '/usr/bin')!
	os.mv(root + '/usr/real-bin', root + '/usr/bin')!
	checks << 'target parent link refused'
	self_root := work + '/self'
	os.mkdir_all(self_root + '/usr/bin')!
	self_digest := fixture(self_root + '/usr/bin/vinix-package', 1)!
	self_selection := winecurrent.admit(self_root + '/usr/bin/vinix-package', self_digest)!
	refused_stage(self_selection, self_root, 'must not overwrite')!
	winecurrent.close_selection(self_selection)
	checks << 'selected source cannot also be staging target'
	staged_again := winecurrent.stage(selection, root)!
	defer { winecurrent.close_staged(staged_again) }
	fixture(target, 3)!
	mut refused := false
	winecurrent.verify_staged(selection, staged_again, root) or { refused = true }
	if !refused { return error('changed staged bytes were accepted') }
	checks << 'post-stage target modification refused'
	fixture(source, 3)!
	refused_stage(selection, root, 'current CLI')!
	checks << 'changed selected input refused'
	fixture(work + '/replacement', 1)!
	os.rm(source)!
	os.mv(work + '/replacement', source)!
	refused_stage(selection, root, 'identity changed')!
	checks << 'same bytes at a replacement inode refused'
	for path, expected in inputs {
		if winesource.file_digest(path)! != expected { return error('control source or binary changed') }
	}
	os.write_file(work + '/inputs-after.json', json2.encode(inputs))!
	os.write_file(work + '/result.json', json2.encode(Report{
		scope: 'host-only synthetic ELF headers; no CLI execution, image staging or Wine qualification'
		checks: checks
		inputs: inputs
	}))!
	println('WINE CURRENT CLI controls PASS: ' + checks.len.str())
}

fn main() { check() or { eprintln(err.msg()); exit(1) } }
