// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only pathname budget for the pinned AArch64 audio preparation producer.
// A forecast is not a continuous resource guard or permission to run a producer.
module main

import crypto.sha256
import json2
import os
import time
import tests.packages.audioinputs
import tests.packages.audioprepare

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, i32, ...int) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

const producer_sha = '24ca64ca7d591b4d6e63c14e9ed83b917af2e1c1f12bf8b1d0bdedb34dc693c7'
const namespace_cap = u64(2048) << 20
const output_reserve = u64(128) << 20
const source_trees = ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring',
	'tools/sandbox', 'build-support/native-compat-tools/compathost', 'tests/qemu-core/fixturehost',
	'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy',
	'tests/native-policy-tools/cpufixture', 'tests/host-policy/policyhost', 'tests/hardware-platform/hwhost',
	'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone', 'tests/packages/audiotest',
	'tests/packages/audioinputs', 'tests/packages/audioprepare', 'tests/packages/audiokernel']
const source_files = ['tests/packages/audio-portal-runtime-check.v',
	'tests/packages/audio-portal-retain.v', 'tests/packages/audio-portal-evidence-check.v',
	'tests/packages/audio-portal-wave-check.v', 'build-support/native-compat-tools/main.v',
	'build-support/security-tools/compile-v-core', 'build-support/run-v-tool.sh',
	'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v', 'tests/packages/audio-input-check.v',
	'tests/packages/audio-cross-probe.v', 'tests/packages/audio-portal-prepare-check.v', 'build-support/limine.conf']
const runtime_tools = ['cp', 'tar', 'mformat', 'mmd', 'mcopy']

// Match the maintained runner's serialization, including every inventoried role.
struct Plan {
	format int
	profile string
	source_revision string
	state_root string
	audit_root string
	kernel_seal_sha256 string
	kernel_sha256 string
	roots map[string]string
	files map[string]string
	inputs map[string]map[string]string
	charged_roots []string
	cap_bytes u64
	prepare_wall_ms int
}

struct Copy {
	path string
	original string
	sha256 string
	bytes u64
	rounded_bytes u64
}

struct Namespace {
mut:
	entries int
	allocated_bytes u64
	apparent_bytes u64
	conservative_apparent_bytes u64
}

struct Budget {
mut:
	paths map[string]Copy
	expected map[string]string
	unique map[string]Copy
	directories map[string]int
	state string
	store string
	visited int
	started i64
}

fn tick(started i64, depth int, entries int) ! {
	if depth > 64 || entries > 250000 || time.sys_mono_now() - started > i64(120000) * 1000000 {
		return error('projection traversal exceeds depth, count or 120-second bound')
	}
}

fn add(a u64, b u64) !u64 {
	if b > ~u64(0) - a { return error('projection integer overflow') }
	return a + b
}

fn rounded(value u64) !u64 {
	return (add(value, 4095)! / 4096) * 4096
}

fn checked(path string, expected string) !Copy {
	audioprepare.regular(path)!
	before := os.lstat(path)!
	sum := audioprepare.digest(path)!
	after := os.lstat(path)!
	// Reading may update atime; identity, mode, ownership, size and other captured
	// source timestamps must remain unchanged.
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.uid != after.uid || before.gid != after.gid || before.nlink != after.nlink
		|| before.rdev != after.rdev || before.size != after.size || before.mtime != after.mtime
		|| before.ctime != after.ctime
		|| 'file|' + (before.mode & 0o7777).str() + '|' + sum != expected {
		return error('selected input differs from reviewed map: ' + path)
	}
	return Copy{original: path, sha256: sum, bytes: before.size, rounded_bytes: rounded(before.size)!}
}

fn (mut b Budget) parent_entries(path string) ! {
	mut part := path
	for _ in 0 .. 65 {
		parent := os.dir(part)
		if parent == part || !(parent == b.state || parent.starts_with(b.state + '/')
			|| parent == b.store || parent.starts_with(b.store + '/')) {
			return error('projected copy escaped fresh preparation/store')
		}
		b.directories[parent]++
		if parent == b.state || parent == b.store { return }
		part = parent
	}
	return error('projected parent depth exceeds bound')
}

fn (mut b Budget) copy(path string, original string, retained bool) ! {
	b.visited++
	tick(b.started, 0, b.visited)!
	entry := b.expected[original] or { return error('selected original absent from reviewed map: ' + original) }
	if !entry.starts_with('file|') { return error('selected original is not a reviewed regular file: ' + original) }
	if path in b.paths { return error('duplicate projected copy path: ' + path) }
	c := checked(original, entry)!
	b.paths[path] = Copy{...c, path: path}
	b.parent_entries(path)!
	if retained {
		if prior := b.unique[c.sha256] {
			if prior.bytes != c.bytes { return error('equal digests have different sizes') }
		} else {
			store_path := b.store + '/' + c.sha256
			b.unique[c.sha256] = Copy{...c, path: store_path}
			b.parent_entries(store_path)!
		}
	}
}

fn (mut b Budget) retained_tree(original string, relative string, ancestors []string, depth int) ! {
	b.visited++
	tick(b.started, depth, b.visited)!
	// Reserve every traversed target directory, including empty inputs. The
	// producer currently creates only parents of copied files; this is a
	// conservative allowance if a directory contains no selected file.
	b.directories[b.state + '/inputs/' + relative] += 0
	canonical := os.real_path(original)
	if canonical in ancestors || ancestors.len > 32 { return error('cyclic or excessive retained tree: ' + original) }
	mut chain := ancestors.clone()
	chain << canonical
	mut names := os.ls(original)!
	names.sort()
	for name in names {
		path := original + '/' + name
		key := relative + '/' + name
		if os.is_dir(path) { b.retained_tree(path, key, chain, depth + 1)! }
		else { b.copy(b.state + '/inputs/' + key, os.real_path(path), true)! }
	}
}

fn (mut b Budget) source_tree(root string, relative string, depth int) ! {
	b.visited++
	tick(b.started, depth, b.visited)!
	b.directories[b.state + '/inputs/source/' + relative] += 0
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := relative + '/' + name
		path := root + '/' + key
		kind := os.lstat(path)!.mode & 0o170000
		if kind == 0o040000 { b.source_tree(root, key, depth + 1)! }
		else if kind == 0o100000 {
			if !name.ends_with('_test.v') { b.copy(b.state + '/inputs/source/' + key, path, false)! }
		} else { return error('nonregular producer source: ' + path) }
	}
}

fn namespace(path string, device u64, started i64, depth int, mut n Namespace) ! {
	n.entries++
	tick(started, depth, n.entries)!
	mut st := C.stat{}
	if unsafe { C.lstat(&char(path.str), &st) } != 0 {
		return error('namespace lstat failed: ' + path)
	}
	if u64(st.st_dev) != device || st.st_blocks < 0 || st.st_size < 0 {
		return error('namespace device or storage size refused')
	}
	n.allocated_bytes = add(n.allocated_bytes, u64(st.st_blocks) * 512)!
	n.apparent_bytes = add(n.apparent_bytes, u64(st.st_size))!
	// Admission uses du's apparent accounting, whose per-entry unit rounding
	// differs from raw byte sums. A 4KiB charge for each entry bounds those
	// observed 1KiB units, including directories and literal symlinks.
	n.conservative_apparent_bytes = add(n.conservative_apparent_bytes, rounded(u64(st.st_size))!)!
	if st.st_mode & C.S_IFMT == C.S_IFDIR {
		for name in os.ls(path)! { namespace(path + '/' + name, device, started, depth + 1, mut n)! }
	} else if st.st_mode & C.S_IFMT != C.S_IFREG && st.st_mode & C.S_IFMT != C.S_IFLNK {
		return error('nonordinary charged namespace entry')
	}
}

fn new_output(path string, text string) ! {
	if !os.is_abs_path(path) || os.real_path(os.dir(path)) != os.dir(path)
		|| os.lstat(os.dir(path))!.mode & 0o170000 != 0o040000 {
		return error('requires existing canonical ordinary output parent')
	}
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('requires fresh output') }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		n := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 || n > isize(text.len - offset) { return error('report write failed; preserve partial output') }
		offset += int(n)
	}
	closed = true
	if C.close(fd) != 0 { return error('report close failed') }
	if os.read_file(path)! != text { return error('written report differs') }
}

fn run() ! {
	if os.args.len != 4 { return error('use PLAN PLAN_SHA256 NEW_REPORT') }
	plan_path := os.args[1]
	audioprepare.regular(plan_path)!
	if os.lstat(plan_path)!.size > u64(32) << 20 { return error('plan exceeds32MiB') }
	text := os.read_file(plan_path)!
	if sha256.hexhash(text) != os.args[2] { return error('reviewed plan digest differs') }
	p := json2.decode[Plan](text)!
	if text != json2.encode(p) + '\n' || p.format != 1 || p.cap_bytes != namespace_cap
		|| p.profile != 'matched-peer-frame-atomic-fresh-20261026' || p.charged_roots.len != 6
		|| p.source_revision.len != 40 || p.inputs.len != 43 {
		return error('requires exact canonical current six-root reviewed profile')
	}
	source := p.roots['source']
	if audioprepare.digest(source + '/tests/packages/audio-portal-runtime-check.v')! != producer_sha {
		return error('producer differs from the implementation whose selection is mirrored')
	}
	git_marker := os.read_file(source + '/.git')!
	if !git_marker.starts_with('gitdir: ') { return error('source is not the reviewed detached worktree') }
	git_dir := git_marker.all_after('gitdir: ').trim_space()
	if os.read_file(git_dir + '/HEAD')!.trim_space() != p.source_revision { return error('source revision differs') }
	state := p.state_root
	store := os.dir(state) + '/audio-input-store'
	if os.exists(state) || os.is_link(state) || os.lstat(store)!.mode & 0o170000 != 0o040000
		|| os.ls(store)!.len != 0 { return error('requires fresh preparation and empty ordinary input store') }
	if !os.args[3].starts_with(os.dir(state) + '/') { return error('report must stay in charged preparation parent') }
	mut b := Budget{state: state, store: store, started: time.sys_mono_now()}
	for _, entries in p.inputs {
		for path, value in entries {
			if previous := b.expected[path] {
				if previous != value { return error('reviewed maps disagree on a selected path') }
			} else { b.expected[path] = value }
		}
	}
	compiler := p.roots['compiler']
	for name, original in {'kernel': p.roots['kernel-evidence'] + '/kernel-aarch64/bin/vinix',
		'v': compiler + '/v', 'qemu': p.files['qemu'], 'firmware': p.files['firmware'],
		'firmware-vars': p.files['firmware-vars'], 'controller': p.files['controller'],
		'static-c-compiler': p.files['clang'], 'cross-backend': p.files['backend'],
		'cross-adapter.v': source + '/tests/packages/audio-cross-cc.v',
		'adapter-host-cc': p.files['clang'], 'runtime/BOOTAA64.EFI': p.files['limine']} {
		b.copy(state + '/inputs/' + name, original, true)!
	}
	for name in ['snapshot.json', 'v.mod'] { b.copy(state + '/inputs/v-compiler/' + name, compiler + '/' + name, true)! }
	for role in ['cc1', 'collect2', 'as', 'ld', 'lto-wrapper', 'lto-plugin'] {
		b.copy(state + '/inputs/cross-' + role, p.files[role], true)!
	}
	for relative, original in {'vlib': compiler + '/vlib',
		'v-thirdparty/stdatomic': compiler + '/thirdparty/stdatomic',
		'cross-gcc': p.roots['gcc'], 'kernel-evidence': p.roots['kernel-evidence']} {
		b.retained_tree(original, relative, [], 0)!
	}
	// The original helper supplies guest-rooted absolute-link semantics. Its
	// own cycle/link bounds apply; the caller's external timeout bounds this call.
	sysroot := audioinputs.snapshot(p.roots['sysroot'])!
	tick(b.started, 0, b.visited)!
	for name, original in sysroot.files { b.copy(state + '/inputs/cross-sysroot/' + name, original, true)! }
	for tree in source_trees { b.source_tree(source, tree, 0)! }
	for name in source_files { b.copy(state + '/inputs/source/' + name, source + '/' + name, false)! }
	for name in runtime_tools { b.copy(state + '/runtime-bin/' + name, p.files[name], false)! }
	mut pathname_bytes := u64(0)
	mut pathname_rounded := u64(0)
	for _, c in b.paths { pathname_bytes = add(pathname_bytes, c.bytes)!; pathname_rounded = add(pathname_rounded, c.rounded_bytes)! }
	mut store_bytes := u64(0)
	mut store_rounded := u64(0)
	for _, c in b.unique { store_bytes = add(store_bytes, c.bytes)!; store_rounded = add(store_rounded, c.rounded_bytes)! }
	mut directory_reserve := u64(0)
	for _, children in b.directories {
		// Ordinary directory headers plus an explicit conservative per-entry budget.
		directory_reserve = add(directory_reserve, rounded(u64(4096) + u64(children) * 256)!)!
	}
	mut current := Namespace{}
	device := os.lstat(os.dir(state))!.dev
	for root in p.charged_roots {
		if p.charged_roots.filter(it == root).len != 1
			|| p.charged_roots.any(it != root && root.starts_with(it + '/')) { return error('overlapping charged roots') }
		namespace(root, device, time.sys_mono_now(), 0, mut current)!
	}
	// The runner independently copies this Plan and writes both complete input
	// maps. Charge these known large files separately from the 128MiB allowance.
	input_map_bytes := u64(json2.encode(p.inputs).len)
	plan_copy_bytes := u64(text.len)
	runner_map_bytes := add(plan_copy_bytes, add(input_map_bytes, input_map_bytes)!)!
	runner_map_rounded := add(rounded(plan_copy_bytes)!, add(rounded(input_map_bytes)!, rounded(input_map_bytes)!)!)!
	projected_apparent := add(add(add(add(add(current.conservative_apparent_bytes, pathname_rounded)!, store_rounded)!, directory_reserve)!, runner_map_rounded)!, output_reserve)!
	projected_allocated := add(add(add(add(add(current.allocated_bytes, pathname_rounded)!, store_rounded)!, directory_reserve)!, runner_map_rounded)!, output_reserve)!
	report := json2.encode({
		'format': 'audio-prepare-pathname-projection-v1'
		'plan_sha256': os.args[2]
		'producer_sha256': producer_sha
		'source_revision': p.source_revision
		'copied_pathnames': b.paths.len.str()
		'unique_store_objects': b.unique.len.str()
		'current_allocated_bytes': current.allocated_bytes.str()
		'current_apparent_bytes': current.apparent_bytes.str()
		'current_conservative_apparent_bytes': current.conservative_apparent_bytes.str()
		'copied_pathname_bytes': pathname_bytes.str()
		'copied_pathname_rounded_bytes': pathname_rounded.str()
		'new_store_bytes': store_bytes.str()
		'new_store_rounded_bytes': store_rounded.str()
		'directory_reserve_bytes': directory_reserve.str()
		'runner_plan_copy_bytes': plan_copy_bytes.str()
		'runner_input_map_bytes_each': input_map_bytes.str()
		'runner_plan_and_two_input_maps_bytes': runner_map_bytes.str()
		'runner_plan_and_two_input_maps_rounded_bytes': runner_map_rounded.str()
		'generated_temporary_receipt_reserve_bytes': output_reserve.str()
		'projected_allocated_bytes': projected_allocated.str()
		'projected_apparent_bytes': projected_apparent.str()
		'cap_bytes': namespace_cap.str()
		'within_both_projected_caps': (projected_allocated <= namespace_cap && projected_apparent <= namespace_cap).str()
		'scope': 'Observed selected capture sizes plus 4KiB-rounded existing apparent entries/copies and explicit directory/generated/temporary/receipt allowances. Raw apparent bytes are informational; cap comparison uses conservative rounding above the observed 1KiB du units. Existing hardlinks count per pathname. This is a forecast, not proof that future outputs fit, a continuous guard, free-space admission, full input revalidation or target qualification.'
	}) + '\n'
	new_output(os.args[3], report)!
	println('AUDIO PREPARATION PROJECTION ' + if projected_allocated <= namespace_cap && projected_apparent <= namespace_cap { 'WITHIN' } else { 'EXCEEDS' })
}

fn main() { run() or { eprintln('audio-portal-prepare-estimate: ' + err.msg()); exit(1) } }
