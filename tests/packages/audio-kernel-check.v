// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only controls for the reviewed matched-kernel admission gate.
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tests.packages.audiokernel
import tests.packages.audioprepare

const copy_limit = u64(128) << 20
const expected_controls = 27

struct Counter {
mut:
	entries int
	bytes u64
}

struct Report {
	format int = 1
	result string = 'PASS'
	checker_sha256 string
	checker_source_sha256 string
	kernel_helper_sha256 string
	evidence_root string
	selected_kernel_sha256 string
	copy_logical_bytes u64
	control_count int
	controls []string
	original_before map[string]string
	original_after map[string]string
	audit_before map[string]string
	audit_after map[string]string
	scope string = 'Host admission and local independent-copy refusals; no target compilation, package admission or guest execution. The complete original audit remains required.'
}

fn hex(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path
		|| path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute control path: ' + path)
	}
}

fn inside(path string, root string) bool {
	return path == root || path.starts_with(root + '/')
}

fn bound(started i64, depth int, mut counter Counter) ! {
	counter.entries++
	if depth > 64 || counter.entries > 250000
		|| (time.sys_mono_now() - started) / 1_000_000 > 120000 || hwhost.interrupted() {
		return error('kernel control tree exceeds bounded scope or was interrupted')
	}
}

fn snapshot_walk(root string, name string, depth int, started i64, mut counter Counter,
	mut entries map[string]string) ! {
	bound(started, depth, mut counter)!
	path := if name == '' { root } else { root + '/' + name }
	stat := os.lstat(path)!
	kind := stat.mode & 0o170000
	if kind == 0o040000 {
		entries[name] = 'directory|' + (stat.mode & 0o7777).str()
		mut children := os.ls(path)!
		children.sort()
		for child in children {
			snapshot_walk(root, if name == '' { child } else { name + '/' + child }, depth + 1,
				started, mut counter, mut entries)!
		}
	} else if kind == 0o100000 && stat.nlink == 1 {
		counter.bytes += u64(stat.size)
		if counter.bytes >= copy_limit { return error('minimal kernel control copy must be smaller than 128 MiB') }
		entries[name] = 'file|' + (stat.mode & 0o7777).str() + '|' + stat.size.str() + '|'
			+ audioprepare.digest(path)!
	} else {
		return error('kernel controls require independent ordinary files and directories: ' + path)
	}
}

fn snapshot(root string) !(map[string]string, u64) {
	canonical(root)!
	if os.lstat(root)!.mode & 0o170000 != 0o040000 { return error('kernel control root is not an ordinary directory') }
	mut entries := map[string]string{}
	mut counter := Counter{}
	snapshot_walk(root, '', 0, time.sys_mono_now(), mut counter, mut entries)!
	return entries, counter.bytes
}

fn copy_tree(source string, target string, depth int, started i64, mut counter Counter) ! {
	bound(started, depth, mut counter)!
	stat := os.lstat(source)!
	kind := stat.mode & 0o170000
	if kind == 0o040000 {
		os.mkdir(target, mode: 0o700)!
		mut children := os.ls(source)!
		children.sort()
		for child in children { copy_tree(source + '/' + child, target + '/' + child, depth + 1, started, mut counter)! }
		os.chmod(target, int(stat.mode & 0o7777))!
	} else if kind == 0o100000 && stat.nlink == 1 {
		counter.bytes += u64(stat.size)
		if counter.bytes >= copy_limit { return error('minimal kernel control copy must be smaller than 128 MiB') }
		os.cp(source, target)!
		os.chmod(target, int(stat.mode & 0o7777))!
		if os.lstat(target)!.nlink != 1 || audioprepare.digest(target)! != audioprepare.digest(source)! {
			return error('kernel control copy is not independent and byte-identical: ' + target)
		}
	} else { return error('nonordinary or shared source in kernel control copy: ' + source) }
}

fn audit_bindings(seal audiokernel.Seal) !map[string]string {
	mut result := map[string]string{}
	for path in [seal.audit.checker_path, seal.audit.manifest_path, seal.audit.checker_source_path] {
		canonical(path)!
		result[path] = audioprepare.digest(path)!
	}
	return result
}

fn refuse(root string, architecture string, selected string, label string, mut controls []string) ! {
	audiokernel.validate(root, architecture, selected) or {
		if err.msg() == '' { return error('kernel control returned an empty refusal: ' + label) }
		controls << label
		return
	}
	return error('kernel admission accepted invalid control: ' + label)
}

fn restore(source string, target string) ! {
	audioprepare.regular(source)!
	if os.lstat(source)!.nlink != 1 { return error('restore source is shared') }
	if os.exists(target) || os.is_link(target) { os.rm(target)! }
	os.cp(source, target)!
	os.chmod(target, int(os.lstat(source)!.mode & 0o7777))!
	if os.lstat(target)!.nlink != 1 || audioprepare.digest(target)! != audioprepare.digest(source)! {
		return error('restored kernel control file differs')
	}
}

fn mutation(original string, copy string, relative string, selected string, label string,
	mut controls []string) ! {
	source := original + '/' + relative
	target := copy + '/' + relative
	audioprepare.regular(target)!
	if os.lstat(target)!.nlink != 1 { return error('refusing to mutate a shared control file') }
	mut bytes := os.read_bytes(target)!
	if bytes.len == 0 { return error('cannot mutate an empty reviewed kernel input') }
	bytes[0] ^= 1
	// Detach even the independent control path before every write. Never write
	// through a retained source or complete-audit pathname.
	mode := os.lstat(target)!.mode & 0o7777
	os.rm(target)!
	os.write_file_array(target, bytes)!
	os.chmod(target, int(mode))!
	mut failure := ''
	refuse(copy, 'aarch64', selected, label, mut controls) or { failure = err.msg() }
	restore(source, target)!
	audiokernel.validate(copy, 'aarch64', selected)!
	if failure != '' { return error(failure) }
}

fn check() ! {
	$if prod {} $else { return error('compile audio-kernel-check with -prod') }
	if audioprepare.digest(@FILE)! != sha256.hexhash($embed_file('audio-kernel-check.v').to_string()) {
		return error('kernel control source differs from compiled source')
	}
	if os.args.len != 4 { return error('use audio-kernel-check EVIDENCE_ROOT EXPECTED_AARCH64_KERNEL_SHA256 NEW_OUTPUT') }
	root := os.args[1]
	selected := os.args[2]
	out := os.args[3]
	canonical(root)!
	canonical(out)!
	canonical(os.dir(out))!
	if !hex(selected) || os.exists(out) || os.is_link(out)
		|| os.lstat(os.dir(out))!.mode & 0o170000 != 0o040000 {
		return error('requires reviewed kernel SHA256 and fresh output below an ordinary existing parent')
	}
	repository := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if inside(out, repository) || inside(out, root) || inside(root, out) {
		return error('kernel controls require external output disjoint from evidence and repository')
	}
	hwhost.watch_interrupts()
	original_before, logical_bytes := snapshot(root)!
	seal := audiokernel.validate(root, 'aarch64', selected)!
	if inside(out, seal.audit.root) || inside(seal.audit.root, out) {
		return error('kernel control output must be disjoint from the original complete audit')
	}
	audit_before := audit_bindings(seal)!
	mut controls := ['original-aarch64-valid']
	audiokernel.validate(root, 'x86_64', seal.kernels['x86_64'].elf_sha256)!
	controls << 'original-x86_64-valid'
	os.mkdir(out, mode: 0o700)!
	os.write_file(out + '/original-before.json', json2.encode(original_before) + '\n')!
	os.write_file(out + '/audit-before.json', json2.encode(audit_before) + '\n')!
	audiokernel.check_audit(root, 'aarch64', selected, out + '/complete-audit.log')!
	controls << 'complete-original-audit-valid'
	copy := out + '/independent-kernel'
	mut counter := Counter{}
	copy_tree(root, copy, 0, time.sys_mono_now(), mut counter)!
	copy_before, copied_bytes := snapshot(copy)!
	if copy_before != original_before || copied_bytes != logical_bytes {
		return error('independent kernel copy differs from original input map')
	}
	audiokernel.validate(copy, 'aarch64', selected)!
	controls << 'independent-clone-valid'
	mut sources := seal.critical_sources.keys()
	sources.sort()
	for source in sources {
		mutation(root, copy, 'source/' + source, selected, 'changed-critical-source:' + source, mut controls)!
	}
	for arch in ['aarch64', 'x86_64'] {
		build := seal.kernels[arch]
		for kind, path in {'elf': build.elf_path, 'generated-c': build.generated_c_path, 'build-log': build.build_log_path} {
			mutation(root, copy, path, selected, 'changed-' + arch + '-' + kind, mut controls)!
		}
	}
	for kind, path in {'source-patch': seal.source_patch_path, 'source-inventory': seal.source_inventory_path} {
		mutation(root, copy, path, selected, 'changed-' + kind, mut controls)!
	}
	os.rm(copy + '/kernel-seal.json')!
	mut failure := ''
	refuse(copy, 'aarch64', selected, 'missing-kernel-seal', mut controls) or { failure = err.msg() }
	restore(root + '/kernel-seal.json', copy + '/kernel-seal.json')!
	audiokernel.validate(copy, 'aarch64', selected)!
	if failure != '' { return error(failure) }
	wrong := if selected == '0'.repeat(64) { '1'.repeat(64) } else { '0'.repeat(64) }
	refuse(copy, 'aarch64', wrong, 'wrong-selected-sha256', mut controls)!
	refuse(copy, 'unsupported', selected, 'unsupported-architecture', mut controls)!
	refuse(copy, 'x86_64', selected, 'wrong-selected-architecture', mut controls)!
	mutation(root, copy, 'kernel-seal.json', selected, 'changed-kernel-seal', mut controls)!
	audiokernel.validate(copy, 'aarch64', selected)!
	copy_after, final_copied_bytes := snapshot(copy)!
	if copy_after != copy_before || final_copied_bytes != copied_bytes { return error('control copy was not restored exactly') }
	controls << 'restored-clone-valid'
	original_after, final_original_bytes := snapshot(root)!
	os.write_file(out + '/original-after.json', json2.encode(original_after) + '\n')!
	if original_after != original_before || final_original_bytes != logical_bytes { return error('original minimal kernel evidence changed') }
	controls << 'original-map-unchanged'
	audit_after := audit_bindings(seal)!
	os.write_file(out + '/audit-after.json', json2.encode(audit_after) + '\n')!
	if audit_after != audit_before { return error('complete audit checker, manifest or checker source changed') }
	controls << 'audit-bindings-unchanged'
	if controls.len != expected_controls { return error('kernel control count differs: ' + controls.len.str()) }
	os.write_file(out + '/qualification.json', json2.encode(Report{
		checker_sha256: audioprepare.digest(os.executable())!,
		checker_source_sha256: audioprepare.digest(@FILE)!,
		kernel_helper_sha256: audioprepare.digest(repository + '/tests/packages/audiokernel/kernel.v')!,
		evidence_root: root, selected_kernel_sha256: selected, copy_logical_bytes: logical_bytes,
		control_count: controls.len, controls: controls, original_before: original_before,
		original_after: original_after, audit_before: audit_before, audit_after: audit_after
	}) + '\n')!
	println('AUDIO KERNEL HOST CHECK PASS controls=' + controls.len.str() + ' (no guest executed)')
}

fn main() { check() or { eprintln('audio-kernel-check: ' + err.msg()); exit(1) } }
