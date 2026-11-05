// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed audio namespace endpoint counter; no producer or process owner.
module main

import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

const plan_sha = 'd939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290'
const namespace_cap = u64(2048) << 20
const report_reserve = u64(64) << 10
const state_parent = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01'
const host_phase = state_parent + '/audio-continuation-host-01'
const charged_roots = [
	'/Users/alex/code/vinix/build/package-audio-a4-independent-prepare-worktree',
	'/Users/alex/code/vinix/build/package-audio-a4-independent-fixtures-worktree',
	'/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-kernel-20261026',
	'/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026',
	'/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026-seal-01',
	state_parent]

// Keep the complete historical typed encoding. The exact SHA binds every
// field; the counter does not retain another copy of the fifteen-MiB maps.
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

struct Namespace {
mut:
	entries int
	allocated_bytes u64
	apparent_bytes u64
	conservative_apparent_bytes u64
}

struct RootUsage {
	root string
	usage Namespace
}

struct Report {
	format int = 1
	scope string = 'Quiescent endpoint observation of the exact six retained roots. Every pathname is charged, including repeated hard links, directories and literal symlinks. Symlinks are never traversed. This observation precedes its own exclusive report publication; cap assessment adds64KiB for that report and the final log tail. No continuous bound, free-space admission, producer, guest or qualification is claimed.'
	plan_path string
	plan_sha256 string = plan_sha
	source_sha256 string
	executable_sha256 string
	roots []RootUsage
	total Namespace
	cap_bytes u64 = namespace_cap
	report_reserve_bytes u64 = report_reserve
	within_both_caps_with_report_reserve bool
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }

// These three helpers and namespace below are copied unchanged from the
// qualified audio-portal-prepare-estimate.v accounting implementation.
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

fn canonical(path string, directory bool) ! {
	require(os.is_abs_path(path) && path != '/' && os.real_path(path) == path
		&& !path.bytes().any(it < 32 || it == 127) && !path.contains('|'),
		'requires canonical absolute ordinary path')!
	bits := os.lstat(path)!.mode & 0o170000
	require(bits == if directory { u32(0o040000) } else { u32(0o100000) },
		'path kind differs')!
}

fn output_parent(path string) ! {
	canonical(host_phase, true)!
	canonical(path, true)!
	require(path.starts_with(host_phase + '/'), 'writes require a private subdirectory of fixed host phase')!
}

fn digest(path string) !string {
	canonical(path, false)!
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn new_output(path string, text string) ! {
	output_parent(os.dir(path))!
	require(path == os.join_path(os.dir(path), os.base(path))
		&& os.base(path) !in ['', '.', '..'] && !path.bytes().any(it < 32 || it == 127),
		'output requires one new ordinary leaf')!
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, i32(0o600))
	if fd < 0 { return error('requires fresh output; preserve existing evidence') }
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
	require(os.lstat(path)!.nlink == 1 && os.read_file(path)! == text, 'written report differs')!
}

fn measure(plan_path string, sha string, output string) ! {
	require(sha == plan_sha, 'requires the exact reviewed legacy Plan SHA256')!
	canonical(plan_path, false)!
	require(plan_path.starts_with(state_parent + '/'), 'Plan must remain in charged preparation parent')!
	require(os.lstat(plan_path)!.size <= u64(32) << 20, 'Plan exceeds32MiB')!
	text := os.read_file(plan_path)!
	require(sha256.hexhash(text) == plan_sha, 'reviewed Plan digest differs')!
	p := json2.decode[Plan](text, strict: true)!
	require(text == json2.encode(p) + '\n' && p.format == 1 && p.cap_bytes == namespace_cap
		&& p.charged_roots == charged_roots && p.inputs.len == 43
		&& p.profile == 'matched-peer-frame-atomic-fresh-20261026',
		'requires exact canonical fixed six-root reviewed profile')!
	output_parent(os.dir(output))!
	require(!os.exists(output) && !os.is_link(output), 'report must be fresh')!
	mut total := Namespace{}
	mut roots := []RootUsage{}
	device := os.lstat(host_phase)!.dev
	for root in charged_roots {
		canonical(root, true)!
		before := total
		namespace(root, device, time.sys_mono_now(), 0, mut total)!
		roots << RootUsage{root: root, usage: Namespace{
			entries: total.entries - before.entries,
			allocated_bytes: total.allocated_bytes - before.allocated_bytes,
			apparent_bytes: total.apparent_bytes - before.apparent_bytes,
			conservative_apparent_bytes: total.conservative_apparent_bytes - before.conservative_apparent_bytes}}
	}
	within := add(total.allocated_bytes, report_reserve)! <= namespace_cap
		&& add(total.conservative_apparent_bytes, report_reserve)! <= namespace_cap
	report := Report{plan_path: plan_path,
		source_sha256: sha256.hexhash($embed_file('audio-continuation-namespace.v').to_string()),
		executable_sha256: digest(os.executable())!, roots: roots, total: total,
		within_both_caps_with_report_reserve: within}
	encoded := json2.encode(report) + '\n'
	require(encoded.len < 32 * 1024, 'counter report exceeds reserved publication size')!
	new_output(output, encoded)!
	if !within { return error('six-root endpoint plus report reserve exceeds fixed aggregate cap') }
	println('AUDIO CONTINUATION NAMESPACE PASS')
}

fn one(path string, device u64) !Namespace {
	mut n := Namespace{}
	namespace(path, device, time.sys_mono_now(), 0, mut n)!
	return n
}

fn controls(parent string) ! {
	output_parent(parent)!
	root := parent + '/namespace-controls-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(root, mode: 0o700)!
	// All created ordinary fixtures and their report remain retained. The
	// sparse file is only65,537 logical bytes, below the bootstrap allowance.
	data := root + '/data'
	os.write_file(data, 'x'.repeat(4097))!
	os.link(data, root + '/hardlink')!
	os.write_file(root + '/empty-file', '')!
	os.mkdir(root + '/empty-directory')!
	os.symlink('data', root + '/file-link')!
	os.symlink('empty-directory', root + '/directory-link')!
	os.symlink('not-created', root + '/dangling-link')!
	sparse_path := root + '/sparse'
	sparse_fd := C.open(sparse_path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, i32(0o600))
	require(sparse_fd >= 0, 'cannot exclusively create sparse fixture')!
	// The pinned V library already declares this symbol with a u64 length.
	// This fixed positive value converts exactly to the SDK's signed off_t64.
	truncated := C.ftruncate(sparse_fd, u64(65537))
	closed := C.close(sparse_fd)
	require(truncated == 0 && closed == 0, 'native sparse fixture truncate or close failed')!
	device := os.lstat(root)!.dev
	for value, expected in {u64(0): u64(0), 1: 4096, 4095: 4096, 4096: 4096, 4097: 8192} {
		require(rounded(value)! == expected, '4KiB rounding boundary differs')!
	}
	mut overflow_refused := false
	_ := add(~u64(0), 1) or { overflow_refused = true; u64(0) }
	require(overflow_refused, 'addition overflow was accepted')!
	overflow_refused = false
	_ := rounded(~u64(0)) or { overflow_refused = true; u64(0) }
	require(overflow_refused, 'rounding overflow was accepted')!
	for pair in [[65, 0], [0, 250001]] {
		mut refused := false
		tick(time.sys_mono_now(), pair[0], pair[1]) or { refused = true }
		require(refused, 'traversal bound was accepted')!
	}
	mut expired := false
	tick(time.sys_mono_now() - i64(121000) * 1000000, 0, 0) or { expired = true }
	require(expired, 'expired traversal was accepted')!
	tick(time.sys_mono_now(), 64, 250000)!
	file := one(data, device)!
	require(file.entries == 1 && file.apparent_bytes == 4097
		&& file.conservative_apparent_bytes == 8192 && os.lstat(data)!.nlink == 2,
		'regular file size or fixture hard-link count differs')!
	mut twice := Namespace{}
	namespace(data, device, time.sys_mono_now(), 0, mut twice)!
	namespace(root + '/hardlink', device, time.sys_mono_now(), 0, mut twice)!
	require(twice.entries == 2 && twice.allocated_bytes == file.allocated_bytes * 2
		&& twice.apparent_bytes == 8194 && twice.conservative_apparent_bytes == 16384,
		'counter deduplicated hard-link pathnames')!
	sparse_usage := one(root + '/sparse', device)!
	require(sparse_usage.apparent_bytes == 65537 && sparse_usage.conservative_apparent_bytes == 69632
		&& sparse_usage.allocated_bytes < sparse_usage.conservative_apparent_bytes,
		'sparse apparent accounting differs or filesystem did not preserve a hole')!
	for name in ['file-link', 'directory-link', 'dangling-link'] {
		link := one(root + '/' + name, device)!
		require(link.entries == 1 && link.apparent_bytes == u64(os.readlink(root + '/' + name)!.len)
			&& link.conservative_apparent_bytes == 4096, 'literal link was followed or rounded incorrectly')!
	}
	mut expected := Namespace{}
	for name in ['', '/data', '/hardlink', '/empty-file', '/empty-directory', '/sparse',
		'/file-link', '/directory-link', '/dangling-link'] {
		path := root + name
		mut st := C.stat{}
		require(unsafe { C.lstat(&char(path.str), &st) } == 0, 'fixture lstat failed')!
		expected.entries++
		expected.allocated_bytes += u64(st.st_blocks) * 512
		expected.apparent_bytes += u64(st.st_size)
		expected.conservative_apparent_bytes += ((u64(st.st_size) + 4095) / 4096) * 4096
	}
	actual := one(root, device)!
	require(actual == expected, 'complete fixture tree does not charge every entry exactly once')!
	mut mismatch := false
	_ := one(data, device ^ u64(1)) or { mismatch = true; Namespace{} }
	require(mismatch, 'foreign-device fixture was accepted')!
	mut existing := false
	new_output(data, 'must not overwrite\n') or { existing = true }
	require(existing && os.read_file(data)! == 'x'.repeat(4097), 'exclusive writer changed existing fixture')!
	mut alias_refused := false
	new_output(root + '/directory-link/refused', 'must not follow parent alias\n') or { alias_refused = true }
	require(alias_refused && !os.exists(root + '/empty-directory/refused'), 'report followed a symlink parent')!
	mut phase_root_refused := false
	output_parent(host_phase) or { phase_root_refused = true }
	require(phase_root_refused, 'report root must be a private phase subdirectory')!
	new_output(root + '.json', json2.encode({'fixture_root': root,
		'namespace': json2.encode(actual), 'controls': 'rounding, overflow, bounds, regular, empty, hardlinks, sparse, literal symlinks, complete directories, device, exclusive report'}) + '\n')!
	println('AUDIO CONTINUATION NAMESPACE CONTROLS PASS')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--controls' {
		controls(os.args[2]) or { eprintln('audio-continuation-namespace: ' + err.msg()); exit(1) }
		return
	}
	if os.args.len != 4 { eprintln('use PLAN REVIEWED_D939_SHA NEW_REPORT | --controls CHARGED_HOST_FIXTURE_ROOT'); exit(2) }
	measure(os.args[1], os.args[2], os.args[3]) or {
		eprintln('audio-continuation-namespace: ' + err.msg())
		exit(1)
	}
}
