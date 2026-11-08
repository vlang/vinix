// SPDX-License-Identifier: GPL-2.0-or-later
// One fixed host bootstrap at a time; historical attempts remain untouched.
module main

import crypto.sha256
import json2
import nativeguard
import os
import sourcecommand
import time

const repo = '/Users/alex/code/vinix'
const section = '/Users/alex/Library/Caches/vinix-codex/section14'
const state = section + '/current-peer-frame-integration-20261105-01'
const scope = state + '/target-consumer-host-01'
const host_root = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain'
const host = host_root + '/v'
const auditor = section + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const host_map = state + '/observer-host-01/maps-02/host-v/inventory.json'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const timeout = '/opt/homebrew/Cellar/coreutils/9.12/bin/timeout'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
const guard_root = state + '/target-freeze-host-01/source/tests/software-hosted-x11'
const target_root = section + '/current-target-v-2f91-20261105-01'
const old_maps = scope + '/bootstrap-inputs-03'
const mib = u64(1024 * 1024)

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn never() bool { return false }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn owned() ![]string {
	text := os.read_file(repo + '/tests/socket-peer-login/qualify-current-target-consumer.v')!
	start := text.index('fn owned_sources() []string {') or { return error('owned source declaration missing') }
	end := text[start..].index('\n}') or { return error('owned source declaration end missing') }
	mut paths := []string{}
	for line in text[start..start + end].split_into_lines() {
		if line.contains("repository + '/") { paths << repo + '/' + line.all_after("repository + '/").all_before("'") }
	}
	require(paths.len == 16 && repo + '/tests/socket-peer-login/resume-current-target-host.v' in paths,
		'complete 16 owned sources including runner required')!
	return paths
}
fn roots() ![]string {
	return [repo + '/build/package-peer-login-atomic-fresh-worktree',
		repo + '/build/package-peer-frame-current-20261105-worktree', state, state + '-seal-01',
		repo + '/.git/worktrees/package-peer-frame-current-20261105-worktree', ...owned()!]
}
fn apparent(paths []string) !u64 {
	r := sourcecommand.capture_combined(['/usr/bin/du', '-skAl', ...paths], os.environ(), 30, 65536, never)!
	rows := r.stdout.trim_space().split_into_lines()
	require(r.status == 0 && rows.len == paths.len, 'complete apparent-space endpoints required')!
	mut total := u64(0)
	for i, row in rows {
		fields := row.fields()
		require(fields.len == 2 && fields[1] == paths[i] && fields[0].bytes().all(it >= `0` && it <= `9`), 'invalid apparent endpoint')!
		total += fields[0].u64() * 1024
	}
	return total
}
fn endpoint(directory string, label string, admission bool, future u64) !u64 {
	paths := roots()!
	growth_paths := [scope, ...owned()!]
	device := os.lstat(scope)!.dev
	space := nativeguard.actual_df(scope, directory + '/' + label + '-df')!
	used := nativeguard.allocated(paths, device)!
	app := apparent(paths)!
	growth := nativeguard.allocated(growth_paths, device)!
	growth_app := apparent(growth_paths)!
	os.write_file(directory + '/' + label + '.json', json2.encode({
		'kernel_allocated': used.str(), 'kernel_apparent': app.str(),
		'consumer_allocated': growth.str(), 'consumer_apparent': growth_app.str(),
		'admitted_attempt_forecast': future.str(), 'available': space.available.str(),
		'scope': 'Both-space endpoint; 76MiB producer, 4MiB Git, 16MiB tail, 511MiB kernel working. All old attempts and runner outputs remain charged.'}) + '\n')!
	final_used := nativeguard.allocated(paths, device)!
	final_app := apparent(paths)!
	final_growth := nativeguard.allocated(growth_paths, device)!
	final_growth_app := apparent(growth_paths)!
	require(space.available >= if admission { 2048 * mib } else { 1024 * mib }, 'fresh shared free-space floor')!
	require(final_growth <= 76 * mib && final_growth_app <= 76 * mib, '76MiB producer ceiling')!
	require(os.lstat(repo + '/.git/index')!.size + 512 * 1024 <= 4 * mib, '4MiB Git transaction reservation')!
	require(final_used + 96 * mib - final_growth <= 511 * mib
		&& final_app + 96 * mib - final_growth_app <= 511 * mib, 'inclusive 511MiB kernel projection')!
	// Admit only this finite build or stage. Later consumer builds need a new
	// complete forecast; they are not admitted by this runner.
	require(nativeguard.allocated([scope], device)! + future <= 30 * mib
		&& apparent([scope])! + future <= 30 * mib, '30MiB bootstrap row including remaining builds')!
	return final_used + 76 * mib - final_growth
}
fn environment(directory string) map[string]string {
	return {'HOME': directory + '/home', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'V': host, 'VEXE': host,
		'VINIX_V_COMPILER': host, 'V_MACOS_V3_CALLER_VEXE': host,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V1_FALLBACK_CACHE_DIR': scope + '/fallback-forbidden',
		'VFLAGS': '', 'CFLAGS': '', 'CPPFLAGS': '', 'LDFLAGS': '', 'VMODULES': directory + '/modules',
		'V3CACHE': directory + '/cache', 'XDG_CACHE_HOME': directory + '/cache',
		'VTMP': directory + '/tmp', 'TMPDIR': directory + '/tmp', 'CC': clang, 'SDKROOT': sdk,
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools', 'COPYFILE_DISABLE': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'}
}
fn policy() string {
	return '(version 1)\n(allow default)\n(deny network*)\n(deny file-read*\n' +
		' (subpath "/Users/alex/code/v-worktrees/vox-parallel-cc")\n (subpath "/Users/alex/code/v"))\n' +
		'(deny file-write*\n (subpath "' + target_root + '")\n (subpath "' + target_root + '-seal-01")\n' +
		' (subpath "' + host_root + '")\n (subpath "' + scope + '/fallback-forbidden"))\n'
}
fn pins() ! {
	for path, expected in {
		host: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		auditor: 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
		host_map: 'ff729f3d39ad09b0401c2f1e08e69784db5c4781117c1f1480a59ee4ffdd39e9'
		repo + '/kernel/c/heap_benchmark_v.h': 'b2f96c47dcdb435656edafb3cd3cbcaaae95a171894d3ea7415d4471509144aa'
	} { require(digest(path)! == expected, 'pinned trust input differs: ' + path)! }
}
fn resource_files(path string, mut files []string) ! {
	require(files.len <= 326, 'resource header namespace exceeds qualified set')!
	info := os.lstat(path)!
	if info.mode & 0o170000 == 0o040000 {
		for name in os.ls(path)! { resource_files(path + '/' + name, mut files)! }
	} else {
		require(info.mode & 0o170000 == 0o100000, 'resource header alias or special entry refused')!
		files << path
	}
}
fn tools(directory string, label string) ! {
	for name, pin in {
		'direct-tools': 'e519b04cb4532d8eec21fd8995fa15c7a8911b69c62acfffbbfdb255fd22efe2'
		'resource-headers': '0a97f84c238ac3da637c39783264efc7e98b65906b9ea25ae1194eb46f5f7cda'
	} {
		baseline := old_maps + '/' + name + '-before.sha256'
		require(digest(baseline)! == pin, 'qualified tool/resource baseline differs')!
		body := os.read_file(baseline)!
		mut count := 0
		mut expected_paths := []string{}
		for row in body.split_into_lines() {
			fields := row.fields()
			require(fields.len == 2 && fields[0].len == 64 && fields[1].starts_with('/'), 'invalid tool row')!
			require(digest(fields[1])! == fields[0], 'selected tool/resource differs: ' + fields[1])!
			expected_paths << fields[1]
			count++
		}
		require(count == if name == 'direct-tools' { 7 } else { 326 }, 'complete tool/resource count')!
		if name == 'resource-headers' {
			mut actual_paths := []string{}
			resource_files('/opt/homebrew/Cellar/llvm/23.1.0/lib/clang/23/include', mut actual_paths)!
			expected_paths.sort()
			actual_paths.sort()
			require(actual_paths == expected_paths, 'complete resource header file set differs')!
		}
		os.write_file(directory + '/' + name + '-' + label + '.sha256', body)!
	}
}
fn command(directory string, label string, args []string, env map[string]string, seconds int) !int {
	argv := [timeout, '--signal=TERM', '--kill-after=10s', seconds.str() + 's', ...args]
	os.write_file(directory + '/' + label + '-argv.json', json2.encode(argv) + '\n')!
	r := sourcecommand.capture_combined(argv, env, f64(seconds + 15), 1024 * 1024, never)!
	os.write_file(directory + '/' + label + '-child.log', r.stdout)!
	os.write_file(directory + '/' + label + '-status.json', json2.encode({'actual_exit': r.status.str()}) + '\n')!
	return r.status
}
fn check(directory string, label string, root string, manifest string, env map[string]string) ! {
	require(command(directory, label, [auditor, 'check', root, manifest], env, 180)! == 0
		&& os.read_file(directory + '/' + label + '-child.log')! == 'FRAME-PAGE COMPLETE STATE CHECK PASS\n',
		'original full audit refused: ' + label)!
}
fn source_roots() map[string]string {
	return {'socket': repo + '/tests/socket-peer-login', 'generators': repo + '/tests/native-generators',
		'hosttest': repo + '/tests/linuxkpi/hosttest', 'cachecli': repo + '/build-support/cachecli',
		'cachekey': repo + '/build-support/cachekey', 'sourcecommand': repo + '/tools/sourcecommand',
		'heapbench': repo + '/kernel/heapbench', 'nativeguard': guard_root + '/nativeguard',
		'recoveryguard': guard_root + '/diagnostics/recoveryguard'}
}
struct Observation { directory string paths []string cap u64 mut: samples int }
fn observe(pid int, context voidptr) ! {
	mut observation := unsafe { &Observation(context) }
	started := time.sys_mono_now()
	for {
		space := nativeguard.actual_df(scope, observation.directory + '/live-df.' + observation.samples.str())!
		used := nativeguard.allocated(observation.paths, os.lstat(scope)!.dev)!
		require(space.available >= 1024 * mib && used <= observation.cap, 'live shared floor or allocation cap')!
		require(os.file_size(observation.directory + '/child.log') <= 1024 * 1024,
			'bootstrap compiler output exceeds 1MiB')!
		observation.samples++
		require(observation.samples <= 320 && time.sys_mono_now() - started < 315 * time.second, 'bounded bootstrap observation')!
		if sourcecommand.child_exit(pid)!.exited { return }
		time.sleep(time.second)
	}
}
fn build() ! {
	directory := scope + '/bootstrap-04'
	require(!present(directory), 'fresh bootstrap required; preserve prior failure')!
	os.mkdir(directory)!
	mut success := false
	defer { if !success { os.write_file(directory + '/qualification.json', '{"status":"FAIL"}\n') or { eprintln(err) } } }
	for name in ['home', 'cache', 'modules', 'tmp', 'inputs', 'asrun-source'] { os.mkdir(directory + '/' + name)! }
	env := environment(directory)
	os.write_file(directory + '/environment.json', json2.encode(env) + '\n')!
	os.write_file(directory + '/policy.sb', policy())!
	pins()!
	endpoint(directory, 'entry', true, 6 * mib)!
	tools(directory, 'before')!
	check(directory, 'host-before', host_root, host_map, env)!
	for label, root in source_roots() {
		require(command(directory, label + '-seal', [auditor, 'seal', root, directory + '/inputs/' + label], env, 120)! == 0,
			'original complete source seal refused: ' + label)!
	}
	for path in owned()! {
		copy := directory + '/asrun-source/' + path.all_after(repo + '/')
		os.mkdir_all(os.dir(copy))!
		os.cp(path, copy, fail_if_exists: true)!
		require(digest(path)! == digest(copy)! && os.lstat(path)!.inode != os.lstat(copy)!.inode, 'independent as-run source copy differs')!
	}
	output := directory + '/stage-profile'
	module_path := [repo + '/build-support', repo + '/tools', repo + '/tests/linuxkpi',
		repo + '/tests/native-generators', repo + '/tests/socket-peer-login', guard_root,
		guard_root + '/diagnostics', host_root + '/vlib'].join('|')
	argv := [timeout, '--signal=TERM', '--kill-after=10s', '300s', '/usr/bin/sandbox-exec', '-f',
		directory + '/policy.sb', host, '-new-compiler', '-no-retry-compilation', '-b', 'c', '-gc', 'none',
		'-enable-globals', '-nocache', '-no-parallel', '-prod', '-showcc', '-cc', clang,
		'-cflags', '-Werror=incompatible-pointer-types', '-cflags', '-Werror=incompatible-function-pointer-types',
		'-cflags', '-Werror=format', '-cflags', '-isysroot ' + sdk, '-path', module_path,
		'-o', output, repo + '/tests/socket-peer-login/qualify-current-target-consumer.v']
	os.write_file(directory + '/argv.json', json2.encode(argv) + '\n')!
	cap := endpoint(directory, 'launch', true, 6 * mib)!
	mut observation := Observation{directory, roots()!, cap, 0}
	r := sourcecommand.run_logged_owned(argv, env, never, directory + '/child.log', false, repo, observe, &observation, 10)!
	os.write_file(directory + '/actual-status.json', json2.encode({'actual_exit': r.status.str(),
		'samples': observation.samples.str(), 'scope': 'GNU timeout/bootstrap owner; no nativeguard typed child cleanup claim.'}) + '\n')!
	tools(directory, 'after')!
	pins()!
	check(directory, 'host-after', host_root, host_map, env)!
	for label, root in source_roots() { check(directory, label + '-postcheck', root, directory + '/inputs/' + label + '/inventory.json', env)! }
	endpoint(directory, 'compiler-final', false, 0)!
	require(r.status == 0 && present(output) && present(output + '.c'), 'actual compile exit, executable and retained C required')!
	require(os.file_size(directory + '/child.log') <= 1024 * 1024, 'complete compiler output exceeds 1MiB')!
	os.write_file(directory + '/qualification.json', json2.encode({'status': 'COMPILED',
		'generated_c_sha256': digest(output + '.c')!, 'executable_sha256': digest(output)!,
		'scope': 'Strict build and original input checks passed. Independent actual SDK/C-ABI review is required before stage.'}) + '\n')!
	endpoint(directory, 'receipt-final', false, 0)!
	success = true
	println('CURRENT TARGET HOST BUILD COMPILED; SDK REVIEW REQUIRED')
}
fn stage() ! {
	directory := scope + '/stage-02'
	require(!present(directory), 'fresh source stage required')!
	review := json2.decode[map[string]string](os.read_file(scope + '/bootstrap-04/sdk-review.json')!)!
	output := scope + '/bootstrap-04/stage-profile'
	compiled := json2.decode[map[string]string](os.read_file(scope + '/bootstrap-04/qualification.json')!)!
	require(review['status'] == 'PASS' && review['executable_sha256'] == compiled['executable_sha256']
		&& review['generated_c_sha256'] == compiled['generated_c_sha256'], 'independent actual SDK/C-ABI review required')!
	require(compiled['status'] == 'COMPILED' && digest(output)! == compiled['executable_sha256']
		&& digest(output + '.c')! == compiled['generated_c_sha256'], 'reviewed bootstrap executable or C changed')!
	os.mkdir(directory)!
	for name in ['home', 'cache', 'modules', 'tmp'] { os.mkdir(directory + '/' + name)! }
	env := environment(directory)
	os.write_file(directory + '/environment.json', json2.encode(env) + '\n')!
	pins()!
	tools(directory, 'before')!
	endpoint(directory, 'entry', true, mib)!
	status := command(directory, 'stage', [output, '--stage'], env, 120)!
	tools(directory, 'after')!
	endpoint(directory, 'final', false, 0)!
	require(status == 0 && os.read_file(directory + '/stage-child.log')! == 'CURRENT TARGET CONSUMER SOURCE PASS 65\n', 'corrected source staging refused')!
	require(digest(output)! == compiled['executable_sha256']
		&& digest(output + '.c')! == compiled['generated_c_sha256'], 'bootstrap changed during staging')!
	println('CURRENT TARGET HOST STAGE PASS')
}
fn run() ! {
	require(os.args.len == 2 && os.args[1] in ['build-stage', 'stage'], 'fixed build-stage or stage mode required')!
	require(os.read_file(@FILE)! == $embed_file('resume-current-target-host.v').to_string(), 'runner source differs from compiled bytes')!
	if os.args[1] == 'stage' { stage()! } else { build()! }
}
fn main() { run() or { eprintln(err); exit(1) } }
