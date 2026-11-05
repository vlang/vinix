// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only v2 plan/original-input admission. No process or state writer lives
// here. The engine separately claims a fresh state and performs real admission.
module audiocontinue

import crypto.sha256
import json2
import os
import time

const legacy2_v = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const legacy2_root_roles = ['source', 'compiler', 'sysroot', 'gcc', 'kernel-evidence', 'llvm-runtime', 'cross-runtime', 'sdk']
const legacy2_file_roles = ['runner', 'controller', 'host-build-receipt', 'clang', 'backend', 'qemu',
	'firmware', 'firmware-vars', 'limine', 'git', 'cp', 'tar', 'mformat', 'mmd', 'mcopy',
	'sh', 'cc', 'arch', 'uname', 'file', 'mktemp', 'rm', 'df', 'cc1', 'collect2', 'as', 'ld',
	'lto-wrapper', 'lto-plugin', 'overlay-before', 'overlay-changes', 'overlay-bundle',
	'audit-checker', 'audit-checker-source', 'audit-manifest']

struct LegacyCompilerPin2 {
	path string
	sha256 string
}

fn plan2_hex(value string, length int) bool {
	return value.len == length && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn plan2_contains(root string, path string) bool {
	return path == root || path.starts_with(root + '/')
}

fn plan2_overlap(a string, b string) bool {
	return plan2_contains(a, b) || plan2_contains(b, a)
}

fn plan2_tick(started i64, depth int, entries int) ! {
	if depth > 64 || entries > 250000 || time.sys_mono_now() - started > i64(120000) * 1000000 {
		return error('v2 original-input inventory exceeds depth, entry or120-second bound')
	}
}

fn plan2_same(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.nlink == b.nlink
		&& a.uid == b.uid && a.gid == b.gid && a.rdev == b.rdev && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn plan2_digest(path string) !string {
	ordinary2(path, 'file')!
	before := os.lstat(path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	started := time.sys_mono_now()
	for {
		plan2_tick(started, 0, 0)!
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	if !plan2_same(before, os.lstat(path)!) { return error('original input changed while hashing: ' + path) }
	mut bytes := sum.sum([]u8{})
	result := bytes.hex()
	unsafe { bytes.free() }
	return result
}

fn plan2_text(path string, expected string) !string {
	canonical2(path)!
	ordinary2(path, 'file')!
	if !plan2_hex(expected, 64) { return error('v2 plan digest must be lowercase SHA256') }
	before := os.lstat(path)!
	if before.size > u64(32) << 20 { return error('v2 typed input exceeds32MiB') }
	text := os.read_file(path)!
	if text.len > 32 * 1024 * 1024 || sha256.hexhash(text) != expected
		|| !plan2_same(before, os.lstat(path)!) {
		return error('v2 typed input changed or its reviewed digest differs')
	}
	return text
}

fn plan2_keys(actual []string, expected []string) ! {
	mut a := actual.clone()
	mut b := expected.clone()
	a.sort()
	b.sort()
	if a != b { return error('v2 original-input roles differ from the reviewed profile') }
}

fn legacy2_schema(l LegacyPlan2) ! {
	if sha256.hexhash(json2.encode(l) + '\n') != reviewed_legacy_plan2
		|| l.format != 1 || l.profile != 'matched-peer-frame-atomic-fresh-20261026'
		|| !plan2_hex(l.source_revision, 40) || !plan2_hex(l.kernel_seal_sha256, 64)
		|| !plan2_hex(l.kernel_sha256, 64) || l.cap_bytes != aggregate_cap2
		|| l.prepare_wall_ms <= 0 || l.prepare_wall_ms > 3000000 || l.charged_roots.len != 6 {
		return error('v2 original tool Plan differs from the exact reviewed legacy profile')
	}
	plan2_keys(l.roots.keys(), legacy2_root_roles)!
	plan2_keys(l.files.keys(), legacy2_file_roles)!
	mut roles := []string{}
	for role in legacy2_root_roles { roles << 'tree:' + role }
	for role in legacy2_file_roles { roles << 'file:' + role }
	plan2_keys(l.inputs.keys(), roles)!
	for _, root in l.roots { canonical2(root)!; ordinary2(root, 'directory')! }
	for _, path in l.files { canonical2(path)!; ordinary2(path, 'file')! }
	for root in l.charged_roots {
		canonical2(root)!
		ordinary2(root, 'directory')!
		if l.charged_roots.filter(it == root).len != 1
			|| l.charged_roots.any(it != root && plan2_contains(it, root)) {
			return error('v2 original charged roots overlap or repeat')
		}
	}
	for path in [l.state_root, l.audit_root] { canonical2(path)!; ordinary2(path, 'directory')! }
	store := os.dir(l.state_root) + '/audio-input-store'
	canonical2(store)!
	ordinary2(store, 'directory')!
	for path in [l.roots['source'], l.roots['kernel-evidence'], l.state_root, l.audit_root,
		store, l.files['runner'], l.files['controller'], l.files['audit-manifest']] {
		if !l.charged_roots.any(plan2_contains(it, path)) { return error('v2 original selected input is outside charged roots') }
	}
	if l.roots['compiler'] != os.dir(legacy2_v) { return error('v2 original compiler root differs') }
}

pub fn load_legacy2(p Plan2) !LegacyPlan2 {
	if p.legacy_plan_sha256 != reviewed_legacy_plan2 { return error('v2 requires the exact reviewed original tool Plan') }
	text := plan2_text(p.legacy_plan_path, reviewed_legacy_plan2)!
	l := json2.decode[LegacyPlan2](text, strict: true)!
	if text != json2.encode(l) + '\n' { return error('v2 original tool Plan must retain its exact canonical encoding') }
	legacy2_schema(l)!
	return l
}

fn plan2_schema(p Plan2) ! {
	if p.format != 2 || p.profile != format2_profile || p.architecture != 'aarch64'
		|| !plan2_hex(p.source_base_revision, 40) || !plan2_hex(p.controller_sha256, 64)
		|| !plan2_hex(p.donor_manifest_sha256, 64) || !plan2_hex(p.source_manifest_sha256, 64)
		|| p.legacy_plan_sha256 != reviewed_legacy_plan2 || p.wall_ms <= 0 || p.wall_ms > 3000000 {
		return error('invalid fixed v2 plan identity, architecture or wall limit')
	}
	if p.preparation_reserve_bytes < u64(200) << 20 || p.receipt_reserve_bytes < u64(16) << 20 {
		return error('v2 Plan must retain the separate200MiB preparation and16MiB receipt planning floors')
	}
}

// Read-only verification may load an existing ordinary state. Preparation must
// separately refuse an existing state before its exclusive initial claim.
pub fn load_plan2(path string, sha string) !Plan2 {
	text := plan2_text(path, sha)!
	p := decode_plan2(text)!
	l := load_legacy2(p)!
	parent := os.dir(l.state_root)
	canonical2(parent)!
	ordinary2(parent, 'directory')!
	if !os.is_abs_path(p.state_root) || os.dir(p.state_root) != parent
		|| p.state_root != os.join_path(parent, os.base(p.state_root))
		|| os.base(p.state_root) in ['', '.', '..']
		|| p.state_root.bytes().any(it < 32 || it == 127 || it == `|`) {
		return error('v2 state must be one ordinary direct child name below the original charged parent')
	}
	if os.is_link(p.state_root) { return error('v2 state may not be a symlink') }
	if os.exists(p.state_root) { canonical2(p.state_root)!; ordinary2(p.state_root, 'directory')! }
	canonical2(p.source_root)!
	ordinary2(p.source_root, 'directory')!
	store := parent + '/audio-input-store'
	if !p.source_root.starts_with(parent + '/') {
		return error('v2 source must remain below the charged preparation parent')
	}
	for root in [l.state_root, store, p.state_root] {
		if plan2_overlap(p.source_root, root) { return error('v2 source overlaps donor/store/state') }
	}
	mut input_roots := l.roots.values()
	input_roots << [l.state_root, store, l.audit_root, p.source_root]
	for root in input_roots {
		if plan2_overlap(p.state_root, root) { return error('v2 state overlaps an immutable input root') }
	}
	for _, original in l.files {
		if plan2_contains(p.state_root, original) || plan2_contains(p.source_root, original) {
			return error('v2 state/source would absorb an original selected tool')
		}
	}
	for manifest in [path, p.donor_manifest_path, p.legacy_plan_path, p.source_manifest_path] {
		canonical2(manifest)!
		ordinary2(manifest, 'file')!
		if !plan2_contains(parent, manifest) {
			return error('all versioned Plans and manifests must remain in the charged preparation root')
		}
		for root in [l.state_root, store, p.state_root, p.source_root] {
			if plan2_contains(root, manifest) { return error('v2 Plan/manifest must stay outside immutable donor/store/source and new state') }
		}
	}
	if plan2_digest(p.donor_manifest_path)! != p.donor_manifest_sha256
		|| plan2_digest(p.source_manifest_path)! != p.source_manifest_sha256 {
		return error('v2 reviewed manifest binding differs')
	}
	return p
}

fn decode_plan2(text string) !Plan2 {
	p := json2.decode[Plan2](text, strict: true)!
	if text != json2.encode(p) + '\n' { return error('v2 Plan requires its exact canonical typed encoding') }
	plan2_schema(p)!
	return p
}

// Preserve the historical map representation, including the pinned V's
// self-identical unresolved host path for a guest-absolute musl loader link.
// Complete donor verification separately checks guest-rooted captured bytes.
fn legacy2_inventory(path string, independent bool, depth int, started i64,
	mut result map[string]string) ! {
	plan2_tick(started, depth, result.len)!
	if path in result { return }
	if path.contains('|') || path.bytes().any(it < 32 || it == 127) { return error('invalid v2 original input path') }
	stat := os.lstat(path)!
	kind := stat.mode & 0o170000
	if kind == 0o040000 {
		result[path] = 'directory|' + (stat.mode & 0o7777).str()
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if independent && depth == 0 && name == '.git' { continue }
			legacy2_inventory(path + '/' + name, independent, depth + 1, started, mut result)!
		}
	} else if kind == 0o100000 {
		if independent && stat.nlink != 1 { return error('original v2 source requires independent regular files') }
		result[path] = 'file|' + (stat.mode & 0o7777).str() + '|' + plan2_digest(path)!
	} else if kind == 0o120000 && independent {
		result[path] = 'link|' + os.readlink(path)!
	} else if kind == 0o120000 {
		real := os.real_path(path)
		result[path] = 'link|' + os.readlink(path)! + '|' + real
		legacy2_inventory(real, false, depth + 1, started, mut result)!
	} else { return error('nonordinary v2 original input: ' + path) }
}

pub fn verify_legacy_inputs2(l LegacyPlan2) ! {
	legacy2_schema(l)!
	mut actual := map[string]map[string]string{}
	for role, root in l.roots {
		mut entries := map[string]string{}
		legacy2_inventory(root, role == 'source', 0, time.sys_mono_now(), mut entries)!
		actual['tree:' + role] = entries
	}
	for role, path in l.files {
		mut entries := map[string]string{}
		legacy2_inventory(path, false, 0, time.sys_mono_now(), mut entries)!
		ordinary2(path, 'file')!
		actual['file:' + role] = entries
	}
	if actual != l.inputs { return error('complete43-role original input maps differ from reviewed v2 legacy bindings') }
	for path, expected in {legacy2_v: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5',
		l.files['overlay-before']: '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f',
		l.files['overlay-changes']: '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21',
		l.files['overlay-bundle']: '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976',
		l.roots['kernel-evidence'] + '/kernel-seal.json': l.kernel_seal_sha256,
		l.roots['kernel-evidence'] + '/kernel-aarch64/bin/vinix': l.kernel_sha256} {
		if plan2_digest(path)! != expected { return error('qualified v2 compiler/overlay/kernel identity differs: ' + path) }
	}
	mut compiler_expected := map[string]string{}
	overlay := os.read_file(l.files['overlay-before'])!
	if overlay.len > 32 * 1024 * 1024 { return error('original compiler overlay exceeds32MiB') }
	for pin in json2.decode[[]LegacyCompilerPin2](overlay, strict: true)! {
		if pin.path in compiler_expected { return error('duplicate original compiler overlay path') }
		compiler_expected[pin.path] = pin.sha256
	}
	mut compiler_actual := map[string]string{}
	for path, entry in actual['tree:compiler'] {
		if path == l.roots['compiler'] { continue }
		name := path.all_after(l.roots['compiler'] + '/')
		if entry.starts_with('directory|') { compiler_actual[name] = 'directory' }
		else if entry.starts_with('file|') { compiler_actual[name] = entry.all_after_last('|') }
		else { return error('qualified v2 compiler root contains an unqualified link') }
	}
	if compiler_actual != compiler_expected { return error('complete qualified v2 compiler root differs from overlay map') }
}

// Space forecast only. This does not perform a df admission, establish that a
// future write stays within its assumptions, or launch anything. The engine
// must still admit actual free space and use the existing native guard.
pub fn check_budget2(p Plan2, l LegacyPlan2, run bool) !u64 {
	plan2_schema(p)!
	legacy2_schema(l)!
	proof_reserve := proof_reserve2(l, load_donor2(p, l)!, load_source2(p)!)!
	if p.receipt_reserve_bytes < proof_reserve {
		return error('versioned Plan receipt reserve is below complete known proof requirement ' + proof_reserve.str())
	}
	current := usage2(l.charged_roots)!
	mut boot := u64(0)
	mut vars := u64(0)
	if run {
		kernel := l.state_root + '/inputs/kernel'
		canonical2(kernel)!
		ordinary2(kernel, 'file')!
		if plan2_digest(kernel)! != l.kernel_sha256 { return error('borrowed v2 kernel differs from reviewed original') }
		loader := l.files['limine']
		ordinary2(loader, 'file')!
		kernel_size := os.lstat(kernel)!.size
		loader_size := os.lstat(loader)!.size
		if kernel_size >= u64(4) << 30 || loader_size >= u64(4) << 30
			|| p.rootfs_archive_bytes_per_scenario >= u64(4) << 30 {
			return error('proposed v2 boot inputs exceed an individual FAT file limit')
		}
		payload := budget2_add(budget2_add(budget2_add(kernel_size, loader_size)!, 4096)!,
			p.rootfs_archive_bytes_per_scenario)!
		boot = boot_image_budget2(payload)!
		ordinary2(l.files['firmware-vars'], 'file')!
		vars = os.lstat(l.files['firmware-vars'])!.size
		if vars < u64(64) << 20 { return error('v2 firmware vars require the full64MiB original') }
	}
	return assess_budget2(Projection2{
		current_allocated: current.allocated, current_apparent: current.apparent,
		preparation_reserve: p.preparation_reserve_bytes, receipt_reserve: p.receipt_reserve_bytes,
		scenario_count: 3, boot_image_bytes: boot, firmware_vars_bytes: vars,
		rootfs_archive_bytes_per_scenario: p.rootfs_archive_bytes_per_scenario,
		wave_bytes_per_scenario: p.wave_bytes_per_scenario,
		logs_bytes_per_scenario: p.logs_bytes_per_scenario, cap: aggregate_cap2
	}, run)
}
