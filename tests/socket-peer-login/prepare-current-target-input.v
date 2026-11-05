// SPDX-License-Identifier: GPL-2.0-or-later
// Draft fixed input freezer. Child ownership is the existing nativeguard API.
@[has_globals]
module main

import crypto.sha1
import crypto.sha256
import json2
import nativeguard
import os
import sourcecommand
import time

#include <errno.h>
#include <sys/stat.h>
fn C.umask(u16) u16

const repository = '/Users/alex/code/vinix'
const section = '/Users/alex/Library/Caches/vinix-codex/section14'
const state = section + '/current-peer-frame-integration-20261105-01'
const seal_state = state + '-seal-01'
const worktree = repository + '/build/package-peer-frame-current-20261105-worktree'
const donor = repository + '/build/package-peer-login-atomic-fresh-worktree'
const git_admin = repository + '/.git/worktrees/package-peer-frame-current-20261105-worktree'
const setup = state + '/target-freeze-host-01'
const input = section + '/current-target-v-2f91-20261105-01'
const audit = input + '-seal-01'
const target = input + '/toolchain'
const source_root = '/Users/alex/code/v-worktrees/vox-parallel-cc'
const source_revision = '2f91a8f4e9b360f3aa1d63aad1595f5a889985c1'
const git = '/Library/Developer/CommandLineTools/usr/bin/git'
const compiler_sha = '482d0c3b5fe591e4b72c613e032c5bc212126c3a0708e18db87dc36e7d907d40'
const archive_sha = '1c25e7abd519486a894a5e18226f67c4cf529ab5976447d57b889073e0514c70'
const archive_size = u64(32885933)
const original_sealer = section + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const host_compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
const input_cap = u64(256) << 20
const input_reserve = u64(8) << 20
const kernel_cap = u64(512) << 20
const kernel_tail = u64(1) << 20
const setup_growth = u64(16) << 20
const freeze_wall = i64(600) * time.second
__global profile_started = i64(0)
__global last_owned_sample = i64(0)
__global sample_count = int(0)

fn clock_guard() ! {
	require(profile_started > 0 && time.sys_mono_now() - profile_started < freeze_wall,
		'600s input freeze entry-through-PASS deadline')!
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn never() bool { return false }
fn kernel_roots() []string { return [donor, worktree, state, seal_state, git_admin] }
fn input_roots() []string { return [input, audit] }

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn ordinary(path string) !os.Stat {
	info := os.lstat(path)!
	require(info.mode & 0o170000 == 0o100000 && info.nlink == 1
		&& info.uid == u32(os.getuid()), 'independent ordinary owned input required: ' + path)!
	return info
}

fn identity(path string) !string {
	info := ordinary(path)!
	hash := digest(path)!
	after := ordinary(path)!
	require(info.dev == after.dev && info.inode == after.inode && info.mode == after.mode
		&& info.uid == after.uid && info.gid == after.gid && info.nlink == after.nlink
		&& info.size == after.size && info.mtime == after.mtime && info.ctime == after.ctime,
		'input identity changed during hash: ' + path)!
	return json2.encode({'dev': info.dev.str(), 'inode': info.inode.str(),
		'mode': info.mode.str(), 'uid': info.uid.str(), 'gid': info.gid.str(),
		'nlink': info.nlink.str(), 'size': info.size.str(),
		'mtime': info.mtime.str(), 'ctime': info.ctime.str(), 'sha256': hash})
}

fn checked(argv []string) !string {
	result := sourcecommand.capture_combined(argv, os.environ(), 30,
		4 * 1024 * 1024, never)!
	require(result.status == 0, 'bounded probe failed: ' + argv.str())!
	return result.stdout
}

fn source_bindings() !map[string]string {
	require(os.read_file(@FILE)! == $embed_file('prepare-current-target-input.v').to_string(),
		'freezer source differs from embedded source')!
	for path, expected in {
		setup + '/source/tests/software-hosted-x11/nativeguard/guard.v': '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
		setup + '/source/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v': '924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'
		setup + '/source/tools/sourcecommand/abi.h': 'a816e3d27024ede2dfba4e04eeb473d81ee0f47f1381ada687edce51a6e32d23'
		setup + '/source/tools/sourcecommand/core.v': '5b5ba4be07027e508ff881602a9a9f100491f0c65164607b39ee58e987117212'
		setup + '/source/tools/sourcecommand/pty.v': '733cd8ebed8e1f358ba4616d9b97d0c0bcb399e1a809aba1ce523b534497fa18'
		setup + '/source/tools/sourcecommand/reader.v': '20c3b6a17589d65e59d6d8a31ce6af4276333757a1db78458d368f84fed38129'
		setup + '/source/tools/sourcecommand/logged.v': 'c09ebbda5f9f76fd2cfc9a17c8ff66442efa16a2210a5bfb83c354b6fd9fcafa'
		setup + '/source/tools/sourcecommand/duplex.v': 'c6b57a59aa570f208b7b8f17d775d6623ca8edf8a525f485039d101c27d97dc2'
		setup + '/source/tools/sourcecommand/pty_test.v': 'fde3a446ff0d242566f015d464210708d5ed7a66455dd63a9cc654571c75ccc3'
		host_compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		original_sealer: 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
		git: '5c5d6527325adcf024e229a9eb540cc0bdd21e1e23ce8f125cf3d8b3704e2659'
		'/usr/bin/gzip': '80c36b28a931410775eb7428b82b8116303b5f178efcc6a89d59454630295794'
		'/usr/bin/tar': '640f174362e1c0bd27450d0cbf77583d1811f8011a6de54de81c3118b7be0863'
	} { require(digest(path)! == expected, 'source/tool pin differs: ' + path)! }
	require(checked([git, '-C', source_root, 'rev-parse', 'HEAD'])!.trim_space()
		== source_revision, 'matching source worktree revision differs')!
	require(checked([git, '-C', source_root, 'diff', '--name-only', 'HEAD', '--',
		'cmd/v', 'vlib', 'thirdparty', 'v.mod'])! == '', 'tracked source worktree differs')!
	mut result := map[string]string{}
	for path in [source_root + '/v'] {
		require(digest(path)! == compiler_sha, 'selected prebuilt executable drifted: ' + path)!
		result[path] = identity(path)!
	}
	return result
}

fn environment(directory string, selected string) map[string]string {
	return {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'V': selected, 'VEXE': selected,
		'V_MACOS_V3_CALLER_VEXE': selected, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VMODULES': directory + '/modules', 'V3CACHE': directory + '/cache',
		'XDG_CACHE_HOME': directory + '/cache', 'VTMP': directory + '/tmp',
		'TMPDIR': directory + '/tmp', 'SDKROOT': sdk,
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools',
		'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_OPTIONAL_LOCKS': '0',
		'COPYFILE_DISABLE': '1'}
}

fn apparent(roots []string) !u64 {
	text := checked(['/usr/bin/du', '-skAl', ...roots])!
	lines := text.trim_space().split_into_lines()
	require(lines.len == roots.len, 'complete apparent rows required')!
	mut total := u64(0)
	for i, line in lines {
		fields := line.fields()
		require(fields.len == 2 && fields[1] == roots[i]
			&& fields[0].bytes().all(it >= `0` && it <= `9`), 'apparent row differs')!
		total += fields[0].u64() * 1024
	}
	return total
}

fn endpoint(directory string, label string, admission bool) ! {
	device := os.lstat(setup)!.dev
	used := nativeguard.allocated(input_roots(), device)!
	input_apparent := apparent(input_roots())!
	kernel_used := nativeguard.allocated(kernel_roots(), device)!
	kernel_apparent := apparent(kernel_roots())!
	setup_used := nativeguard.allocated([setup], device)!
	setup_apparent := apparent([setup])!
	input_body := nativeguard.allocated([input], device)!
	input_body_apparent := apparent([input])!
	proof_body := nativeguard.allocated([audit], device)!
	proof_apparent := apparent([audit])!
	space := nativeguard.actual_df(setup, directory + '/' + label + '-df.log')!
	os.write_file(directory + '/' + label + '-budget.json', json2.encode({
		'input_allocated_bytes': used.str(), 'input_apparent_bytes': input_apparent.str(),
		'kernel_allocated_bytes': kernel_used.str(), 'kernel_apparent_bytes': kernel_apparent.str(),
		'setup_allocated_bytes': setup_used.str(), 'setup_apparent_bytes': setup_apparent.str(),
		'free_bytes': space.available.str(),
		'scope': 'Separate 256MiB input and 512MiB kernel ceilings. Native allocated samples cover input roots during children; both spaces have apparent endpoints only.'}) + '\n')!
	require(used <= input_cap - input_reserve && input_apparent <= input_cap - input_reserve,
		'input phase exceeds 248MiB working ceiling; retain failure')!
	require(input_body <= u64(231) << 20 && input_body_apparent <= u64(231) << 20
		&& proof_body <= u64(17) << 20 && proof_apparent <= u64(17) << 20,
		'input source/archive/binary or complete proof/log allowance exceeded')!
	require(kernel_used <= kernel_cap - kernel_tail && kernel_apparent <= kernel_cap - kernel_tail,
		'kernel cumulative endpoint exceeds 511MiB working ceiling')!
	require(setup_used <= setup_growth && setup_apparent <= setup_growth, 'complete freezer setup exceeds 16MiB')!
	require(space.available >= if admission { u64(2) << 30 } else { u64(1) << 30 }, 'shared free-space floor')!
}

fn action(label string, argv []string, cwd string, selected string, wall int) !string {
	clock_guard()!
	directory := audit + '/' + label
	require(!present(directory), 'fresh action state required: ' + directory)!
	os.mkdir(directory)!
	for name in ['modules', 'cache', 'tmp'] { os.mkdir(directory + '/' + name)! }
	env := environment(directory, selected)
	for key in os.environ().keys() { os.unsetenv(key) }
	for key, value in env { os.setenv(key, value, true) }
	before := source_bindings()!
	os.write_file(directory + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(directory + '/environment.json', json2.encode(env) + '\n')!
	os.write_file(directory + '/source-before.json', json2.encode(before) + '\n')!
	executable_sha := digest(argv[0])!
	endpoint(directory, 'admission', true)!
	remaining_ms := (freeze_wall - (time.sys_mono_now() - profile_started)) / time.millisecond
	require(remaining_ms > 0, 'no input freeze wall remains')!
	action_wall := if remaining_ms < wall { int(remaining_ms) } else { wall }
	result := nativeguard.supervise(argv, cwd, input, input_roots(), directory + '/child.log', directory + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: input_cap - input_reserve, wall_ms: action_wall, sample_ms: 1000})!
	require(result.samples.len > 0, 'actual input observer samples required')!
	for i in 1 .. result.samples.len {
		require(result.samples[i].mono_ns > result.samples[i - 1].mono_ns
			&& result.samples[i].mono_ns - result.samples[i - 1].mono_ns <= 5 * time.second,
			'actual input observation gap exceeds 5s')!
	}
	sample_count += result.samples.len
	last_owned_sample = result.samples[result.samples.len - 1].mono_ns
	os.write_file(directory + '/result.json', json2.encode(result) + '\n')!
	after := source_bindings()!
	os.write_file(directory + '/source-after.json', json2.encode(after) + '\n')!
	endpoint(directory, 'final', false)!
	clock_guard()!
	require(sample_count <= 620, 'input proof sample allocation bound')!
	require(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == int(C.ECHILD) && before == after
		&& digest(argv[0])! == executable_sha, 'owned fixed input operation failed; preserve all outputs')!
	mut logs := u64(0)
	mut results := u64(0)
	for name in os.ls(audit)! {
		path := audit + '/' + name + '/child.log'
		if present(path) { logs += ordinary(path)!.size }
		status := audit + '/' + name + '/result.json'
		if present(status) { results += ordinary(status)!.size }
	}
	require(logs <= 1024 * 1024, 'aggregate fixed input output exceeds 1MiB endpoint bound')!
	require(results <= 1536 * 1024, 'aggregate complete native results exceed 1.5MiB proof bound')!
	return os.read_file(directory + '/child.log')!
}

fn copy_prebuilt() ! {
	before := source_bindings()!
	destination := target + '/v'
	require(!present(destination), 'fresh independent executable destination required')!
	os.cp(source_root + '/v', destination)!
	os.chmod(destination, 0o755)!
	info := ordinary(destination)!
	source := ordinary(source_root + '/v')!
	require(info.mode & 0o7777 == 0o755 && info.size == 15389808 && digest(destination)! == compiler_sha
		&& (info.dev != source.dev || info.inode != source.inode), 'independent prebuilt copy differs')!
	require(source_bindings()! == before, 'prebuilt input changed during copy')!
	println('CURRENT TARGET PREBUILT COPY PASS')
}

fn git_digest(path string, size u64) !string {
	mut hash := sha1.new()
	defer { unsafe { hash.free() } }
	hash.write(('blob ' + size.str() + '\x00').bytes())!
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn collect(path string, relative string, mut files map[string]bool, mut directories map[string]bool) ! {
	require(files.len + directories.len <= 18000, 'source entry bound')!
	info := os.lstat(path)!
	require(info.uid == u32(os.getuid()), 'extracted owner differs')!
	kind := info.mode & 0o170000
	if kind == 0o040000 {
		directories[relative] = true
		for name in os.ls(path)! { collect(path + '/' + name, if relative == '' { name } else { relative + '/' + name }, mut files, mut directories)! }
	} else {
		require(kind == 0o100000 && info.nlink == 1, 'source alias or special entry refused')!
		files[relative] = true
	}
}

fn verify_tree() ! {
	listing := checked([git, '-C', source_root, 'ls-tree', '-r', '-t', '-l', source_revision,
		'--', 'cmd/v', 'vlib', 'thirdparty', 'v.mod'])!
	mut actual := map[string]bool{}
	mut directories := map[string]bool{}
	collect(target, '', mut actual, mut directories)!
	require(actual.len == 16746 && actual['v'], 'exact extracted file count plus prebuilt executable required')!
	require(directories.len == 1246 && directories[''], 'exact Git directory set plus root required')!
	mut count := 0
	mut dir_count := 0
	for line in listing.trim_space().split_into_lines() {
		pair := line.split('\t')
		require(pair.len == 2, 'Git listing path framing differs')!
		fields := pair[0].fields()
		relative := pair[1]
		require(fields.len == 4 && !relative.starts_with('/') && '..' !in relative.split('/'), 'Git source entry differs')!
		if fields[0] == '040000' {
			require(fields[1] == 'tree' && fields[3] == '-' && directories[relative], 'Git source directory differs')!
			dir_count++
			continue
		}
		require(fields[0] in ['100644', '100755'] && fields[1] == 'blob' && actual[relative], 'Git source file differs')!
		path := target + '/' + relative
		info := ordinary(path)!
		require(info.mode & 0o7777 == if fields[0] == '100755' { u32(0o755) } else { u32(0o644) }
			&& info.size == fields[3].u64() && git_digest(path, info.size)! == fields[2], 'source bytes or mode differ: ' + relative)!
		count++
	}
	require(count == 16745 && dir_count == 1245 && digest(target + '/v')! == compiler_sha,
		'complete source/executable closure differs')!
	println('CURRENT TARGET GIT SOURCE COPY PASS 16745')
}

struct ProofProjection {
mut:
	entries int
	bytes u64 = 2048 // Complete original manifest header, root, scope and separators.
}

// This is a size admission calculation, not a replacement inventory/checker.
// Quoting numeric values adds bytes over the original auditor's numeric fields;
// each regular SHA256 contributes exactly 64 ASCII bytes in either encoding.
fn project_inventory(path string, relative string, depth int, mut projection ProofProjection) ! {
	require(depth <= 128 && projection.entries < 18000, 'complete inventory projection nesting/entry bound')!
	projection.entries++
	info := os.lstat(path)!
	kind := info.mode & 0o170000
	require(kind in [u32(0o100000), u32(0o040000)], 'unsupported complete input inventory object')!
	row := json2.encode({'path': relative,
		'kind': if kind == 0o040000 { 'directory' } else { 'file' },
		'mode': info.mode.str(), 'uid': info.uid.str(), 'gid': info.gid.str(),
		'dev': info.dev.str(), 'inode': info.inode.str(),
		'size': if kind == 0o040000 { '0' } else { info.size.str() },
		'mtime': info.mtime.str(), 'ctime': info.ctime.str(),
		'sha256': if kind == 0o100000 { '0'.repeat(64) } else { '' }, 'target': ''})
	projection.bytes += u64(row.len + 1)
	if kind == 0o040000 {
		for name in os.ls(path)! {
			project_inventory(path + '/' + name, if relative == '.' { name } else { relative + '/' + name },
				depth + 1, mut projection)!
		}
	}
}

fn proof_projection() ! {
	mut projection := ProofProjection{}
	project_inventory(input, '.', 0, mut projection)!
	require(projection.bytes <= u64(6) << 20, 'full original inventory does not fit 6MiB proof admission')!
	os.write_file(audit + '/inventory-size-admission.json', json2.encode({
		'entries': projection.entries.str(), 'conservative_complete_inventory_bytes': projection.bytes.str(),
		'limit_bytes': (u64(6) << 20).str(),
		'scope': 'Size upper bound only. Original unchanged full seal and separate full check remain mandatory.'}) + '\n')!
	println('CURRENT TARGET COMPLETE INVENTORY PROJECTION PASS')
}

fn run() ! {
	profile_started = time.sys_mono_now()
	C.umask(0o022)
	require(os.args.len == 2 && os.args[1] in ['freeze', 'copy-prebuilt', 'verify-tree', 'proof-projection'], 'fixed freezer mode required')!
	source_bindings()!
	if os.args[1] == 'copy-prebuilt' { copy_prebuilt()!; return }
	if os.args[1] == 'verify-tree' { verify_tree()!; return }
	if os.args[1] == 'proof-projection' { proof_projection()!; return }
	require(!present(input) && !present(audit), 'fresh input/audit roots required; no retry reuses failed state')!
	parent := os.lstat(section)!
	require(os.real_path(section) == section && parent.mode & 0o170000 == 0o040000
		&& parent.uid == u32(os.getuid()) && parent.mode & 0o022 == 0,
		'canonical owned input parent required')!
	device := os.lstat(setup)!.dev
	kernel_before := nativeguard.allocated(kernel_roots(), device)!
	kernel_apparent_before := apparent(kernel_roots())!
	require(kernel_before + setup_growth <= kernel_cap - kernel_tail
		&& kernel_apparent_before + setup_growth <= kernel_cap - kernel_tail,
		'freezer setup projection does not fit both cumulative kernel space measures')!
	admission := nativeguard.actual_df(setup, setup + '/input-admission-df.log')!
	require(admission.available >= u64(2) << 30, 'fresh source-freeze admission below 2GiB')!
	os.mkdir(input)!; os.mkdir(audit)!; os.mkdir(target)!
	nativeguard.watch_interrupts()!
	archive := input + '/source.tar.gz'
	archive_output := action('archive-01', [git, '-C', source_root,
		'-c', 'tar.tar.gz.command=/usr/bin/gzip -n -c', 'archive', '--format=tar.gz',
		'--output=' + archive, source_revision, 'cmd/v', 'vlib', 'thirdparty', 'v.mod'],
		source_root, host_compiler, 300000)!
	require(archive_output == '' && os.file_size(archive) == archive_size && digest(archive)! == archive_sha,
		'deterministic compressed archive differs; preserve without extraction')!
	require(action('copy-prebuilt-01', [os.executable(), 'copy-prebuilt'], setup, host_compiler, 30000)!
		== 'CURRENT TARGET PREBUILT COPY PASS\n', 'copy marker differs')!
	require(action('extract-01', ['/usr/bin/tar', '-xzf', archive, '-C', target], setup, host_compiler, 300000)! == '', 'extract output differs')!
	require(action('verify-tree-01', [os.executable(), 'verify-tree'], setup, host_compiler, 300000)!
		== 'CURRENT TARGET GIT SOURCE COPY PASS 16745\n', 'source copy marker differs')!
	version_before := action('version-before-01', [source_root + '/v', 'version'], setup, source_root + '/v', 10000)!
	version_after := action('version-after-01', [target + '/v', 'version'], setup, target + '/v', 10000)!
	require(version_before == 'V 0.5.2 2f91a8f\n' && version_after == version_before, 'version output differs')!
	os.write_file(input + '/PREBUILT-INPUT.json', json2.encode({'source_revision': source_revision,
		'compiler_sha256': compiler_sha, 'compressed_archive_sha256': archive_sha,
		'version': version_after.trim_space(),
		'scope': 'Independently copied prebuilt executable and exact Git source/library inputs. No claim that this executable was built from these sources, no relocated-runtime or generated-code qualification.'}) + '\n')!
	require(action('proof-projection-01', [os.executable(), 'proof-projection'], setup, host_compiler, 30000)!
		== 'CURRENT TARGET COMPLETE INVENTORY PROJECTION PASS\n', 'complete inventory projection marker differs')!
	sealed := action('seal-01', [original_sealer, 'seal', input, audit + '/complete-input'], setup, host_compiler, 300000)!
	require(sealed.starts_with('FRAME-PAGE COMPLETE STATE PASS ') && sealed.trim_space().split_into_lines().len == 1, 'original complete seal marker differs')!
	require(ordinary(audit + '/complete-input/inventory.json')!.size <= u64(6) << 20,
		'complete original inventory exceeds admitted proof size; preserve it in full')!
	checked_output := action('check-01', [original_sealer, 'check', input, audit + '/complete-input/inventory.json'], setup, host_compiler, 300000)!
	require(checked_output == 'FRAME-PAGE COMPLETE STATE CHECK PASS\n', 'original complete check marker differs')!
	endpoint(audit + '/check-01', 'receipts-final', false)!
	require(nativeguard.allocated(kernel_roots(), device)! <= kernel_before + setup_growth, 'setup growth exceeded 16MiB bound')!
	require(apparent(kernel_roots())! <= kernel_apparent_before + setup_growth, 'apparent setup growth exceeded 16MiB bound')!
	require(nativeguard.allocated(input_roots(), device)! <= input_cap - input_reserve
		&& apparent(input_roots())! <= input_cap - input_reserve,
		'final complete input receipts exceed 248MiB working cap')!
	clock_guard()!
	require(last_owned_sample > 0 && time.sys_mono_now() - last_owned_sample <= 5 * time.second,
		'final post-check proof and endpoints exceed last observation by 5s')!
	println('CURRENT TARGET PREBUILT INPUT FREEZE PASS')
}

fn main() { run() or { eprintln(err); exit(1) } }
