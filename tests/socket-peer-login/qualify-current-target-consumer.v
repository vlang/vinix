// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed consumer profile. Ownership stays in the qualified nativeguard module.
@[has_globals]
module main

import crypto.sha1
import crypto.sha256
import currenttargetrecord
import generators
import hosttest
import json2
import nativeguard
import os
import sourcecommand
import time

#include <errno.h>

const repository = '/Users/alex/code/vinix'
const section = '/Users/alex/Library/Caches/vinix-codex/section14'
const state = section + '/current-peer-frame-integration-20261105-01'
const worktree = repository + '/build/package-peer-frame-current-20261105-worktree'
const donor = repository + '/build/package-peer-login-atomic-fresh-worktree'
const admin = repository + '/.git/worktrees/package-peer-frame-current-20261105-worktree'
const setup = state + '/target-freeze-host-01'
const consumer = state + '/target-consumer-host-01'
const source = consumer + '/source-03'
const source_receipt = consumer + '/source-03-stage.json'
const input = section + '/current-target-v-2f91-20261105-01'
const audit = input + '-seal-01'
const target = input + '/toolchain/v'
const vlib = input + '/toolchain/vlib'
const compiler_sha = '482d0c3b5fe591e4b72c613e032c5bc212126c3a0708e18db87dc36e7d907d40'
const manifest_sha = 'e9fc44d9c400e810aeed3345467b7b89d097077370050f322fb8b467b9a0e5cf'
const original = section + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const resource_headers = '/opt/homebrew/Cellar/llvm/23.1.0/lib/clang/23/include'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
const sandbox = '/usr/bin/sandbox-exec'
const host_probe = consumer + '/bin/private-probe'
const input_checker = consumer + '/bin/check-inputs'
const callback_controls = consumer + '/bin/callback-controls'
const callback_controls_normal = consumer + '/bin/callback-controls-normal'
const wall = i64(600) * time.second
const working = u64(80) << 20
const ceiling = u64(96) << 20
const git_transaction_reserve = u64(4) << 20
const kernel_working = u64(511) << 20
__global consumer_profile_started_ns = i64(0)
__global consumer_profile_last_sample_ns = i64(0)
__global consumer_profile_sample_total = int(0)
__global consumer_profile_generation_label = ''
__global consumer_profile_action_total = int(0)

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn never() bool { return false }
fn owned_sources() []string {
	return [repository + '/tests/socket-peer-login/qualify-current-target-consumer.v',
		repository + '/tests/socket-peer-login/resume-current-target-host.v',
		repository + '/tests/socket-peer-login/current-target-consumer-sources.txt',
		repository + '/tests/socket-peer-login/current-target-consumer-plan.md',
		repository + '/tests/socket-peer-login/current-target-consumer-checkpoint.md',
		repository + '/tests/socket-peer-login/currenttargetrecord/core.v',
		repository + '/tests/socket-peer-login/currenttargetprobe/main.v',
		repository + '/tests/native-generators/generators/core.v',
		repository + '/tests/native-generators/generators/capture_test.v',
		repository + '/tests/native-generators/callback-controls.v',
		repository + '/tests/native-generators/test-generators.v',
		repository + '/tests/linuxkpi/hosttest/module.v',
		repository + '/tests/linuxkpi/hosttest/module_capture_test.v',
		repository + '/tests/socket-peer-login/preserveoutputs/core.v',
		repository + '/tests/socket-peer-login/preserveoutputs/README.md',
		repository + '/tests/socket-peer-login/preserve-outputs-controls.v']
}
fn roots() []string { return [donor, worktree, state, state + '-seal-01', admin, ...owned_sources()] }
fn growth_roots() []string { return [consumer, ...owned_sources()] }
fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn identity(path string) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.uid == u32(os.getuid())
		&& before.nlink == 1, 'independent owned ordinary file required: ' + path)!
	digest := hash(path)!
	after := os.lstat(path)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime,
		'file identity drift during hash: ' + path)!
	return json2.encode({'dev': before.dev.str(), 'inode': before.inode.str(),
		'mode': before.mode.str(), 'uid': before.uid.str(), 'gid': before.gid.str(),
		'nlink': before.nlink.str(), 'size': before.size.str(), 'mtime': before.mtime.str(),
		'ctime': before.ctime.str(), 'sha256': digest})
}

fn text_probe(argv []string) !string {
	result := sourcecommand.capture_combined(argv, os.environ(), 30, 1024 * 1024, never)!
	need(result.status == 0, 'bounded endpoint probe failed: ' + argv.str())!
	return result.stdout
}

fn apparent(paths []string) !u64 {
	lines := text_probe(['/usr/bin/du', '-skAl', ...paths])!.trim_space().split_into_lines()
	need(lines.len == paths.len, 'one apparent endpoint per charged root required')!
	mut total := u64(0)
	for i, line in lines {
		fields := line.fields()
		need(fields.len == 2 && fields[1] == paths[i]
			&& fields[0].bytes().all(it >= `0` && it <= `9`), 'apparent row differs')!
		total += fields[0].u64() * 1024
	}
	return total
}

fn proof_sizes(path string, mut totals []u64) ! {
	need(totals.len == 5, 'fixed proof counter width')!
	for name in os.ls(path)! {
		full := path + '/' + name
		info := os.lstat(full)!
		if info.mode & 0o170000 == 0o040000 {
			// Complete source snapshots are charged to bootstrap/source rows;
			// rename-01 has its independent complete 10MiB endpoint guard.
			if full == source || full == consumer + '/source' || full == consumer + '/rename-01'
				|| name in ['cache', 'modules', 'tmp', 'asrun-source'] { continue }
			proof_sizes(full, mut totals)!
		} else if info.mode & 0o170000 == 0o100000 {
			if name.starts_with('df.') || name.contains('-df') { totals[4]++ }
			else { totals[3]++ }
			if name == 'child.log' { totals[0] += info.size }
			if name == 'result.json' { totals[1] += info.size }
			if name.ends_with('.json') || name.ends_with('.txt') || name.ends_with('.d')
				|| name.ends_with('.files') || name.ends_with('.stdout') { totals[2] += info.size }
		}
	}
}

fn proof_bounds() ! {
	mut totals := [u64(0), 0, 0, 0, 0]
	proof_sizes(consumer, mut totals)!
	need(totals[0] <= u64(2) << 20, 'aggregate child output exceeds 2MiB endpoint allowance')!
	need(totals[1] <= (u64(3) << 20) / 2, 'complete native result JSON exceeds 1.5MiB')!
	need(totals[2] <= u64(2) << 20, 'complete proof metadata exceeds 2MiB endpoint allowance')!
	need(totals[3] <= 1400 && totals[4] <= 3000,
		'complete proof regular-file rounding forecast exceeded')!
}

fn endpoint(directory string, label string, admission bool) !u64 {
	device := os.lstat(consumer)!.dev
	used := nativeguard.allocated(roots(), device)!
	app := apparent(roots())!
	growth := nativeguard.allocated(growth_roots(), device)!
	growth_app := apparent(growth_roots())!
	space := nativeguard.actual_df(consumer, directory + '/' + label + '-df')!
	os.write_file(directory + '/' + label + '.json', json2.encode({
		'kernel_allocated': used.str(), 'kernel_apparent': app.str(),
		'consumer_allocated': growth.str(), 'consumer_apparent': growth_app.str(),
		'available': space.available.str(), 'working_bytes': working.str(),
		'total_bytes_including_16MiB_reserve': ceiling.str(),
		'scope': 'Reported values precede this endpoint receipt. After writing DF/JSON, fresh allocated/apparent sizes enforce both working ceilings. Complete input C remains a separate read-only 256MiB phase.'}) + '\n')!
	final_used := nativeguard.allocated(roots(), device)!
	final_app := apparent(roots())!
	final_growth := nativeguard.allocated(growth_roots(), device)!
	final_growth_app := apparent(growth_roots())!
	need(final_growth <= working - git_transaction_reserve && final_growth_app <= working - git_transaction_reserve,
		'76MiB producer ceiling; retain 4MiB Git transaction space and full 16MiB final reserve')!
	need(os.lstat(repository + '/.git/index')!.size + (u64(512) << 10) <= git_transaction_reserve,
		'main Git index transaction plus object/metadata projection exceeds reserved 4MiB')!
	need(final_used + ceiling - final_growth <= kernel_working
		&& final_app + ceiling - final_growth_app <= kernel_working,
		'complete inclusive kernel projection plus unspent consumer allowance exceeds 511MiB')!
	need(space.available >= if admission { u64(2) << 30 } else { u64(1) << 30 },
		'fresh shared free-space floor')!
	proof_bounds()!
	if present(consumer + '/rename-01') { rename_size()! }
	return final_used + working - git_transaction_reserve - final_growth
}

fn deadline() ! {
	need(consumer_profile_started_ns > 0 && time.sys_mono_now() - consumer_profile_started_ns < wall,
		'600s consumer entry-through-PASS wall expired')!
}

fn input_bindings() !map[string]string {
	need(hash(target)! == compiler_sha, 'frozen compiler bytes differ')!
	need(hash(audit + '/complete-input/inventory.json')! == manifest_sha,
		'original complete compiler inventory differs')!
	need(os.real_path(input) == input && os.real_path(audit) == audit
		&& os.real_path(vlib) == vlib && os.is_dir(vlib + '/builtin'),
		'canonical private vlib admission; no baked-root fallback')!
	need(hash(original)! == 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6',
		'original complete auditor differs')!
	for path, expected in {
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		sandbox: '10cf4a46a575e4747d2419cf343800db0d11ae6e6e9b8415998d3d8f336b2a92'
		'/bin/cat': '2d839ffe60c9119a8c30256a04dec5a84751d3c07c3a63aa3762215b7c27996d'
		'/usr/bin/false': '098caa8bea93c75c4e149e436626d535a1e00eaff72569194d170e0b95a50bad'
	} { need(hash(path)! == expected, 'selected tool bytes differ: ' + path)! }
	return {target: identity(target)!, audit + '/complete-input/inventory.json': identity(audit + '/complete-input/inventory.json')!,
		input_checker: identity(input_checker)!, callback_controls: identity(callback_controls)!,
		callback_controls_normal: identity(callback_controls_normal)!,
		@FILE: identity(@FILE)!}
}

fn environment(directory string, selected string) map[string]string {
	return {'HOME': consumer + '/home', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'V': selected, 'VEXE': target,
		'VINIX_V_COMPILER': selected, 'V_MACOS_V3_CALLER_VEXE': target,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VFLAGS': '',
		'V1_FALLBACK_CACHE_DIR': consumer + '/fallback-forbidden',
		'VMODULES': directory + '/modules', 'V3CACHE': directory + '/cache',
		'XDG_CACHE_HOME': directory + '/cache', 'VTMP': consumer + '/tmp',
		'TMPDIR': consumer + '/tmp', 'CC': clang, 'SDKROOT': sdk,
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools',
		'COPYFILE_DISABLE': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'}
}

fn action(label string, argv []string, seconds int, expected int, selected string, protected bool) !string {
	deadline()!
	consumer_profile_action_total++
	need(consumer_profile_action_total <= 81, 'fixed consumer action count')!
	directory := consumer + '/actions/' + label
	need(!present(directory), 'fresh action required; retain prior failure: ' + directory)!
	os.mkdir(directory)!
	for name in ['modules', 'cache'] { os.mkdir(directory + '/' + name)! }
	env := environment(directory, selected)
	for key in os.environ().keys() { os.unsetenv(key) }
	for key, value in env { os.setenv(key, value, true) }
	before := input_bindings()!
	mut command := argv.clone()
	if protected { command = [sandbox, '-f', consumer + '/consumer.sb', ...argv] }
	os.write_file(directory + '/argv.json', json2.encode(command) + '\n')!
	os.write_file(directory + '/executable.json', json2.encode({argv[0]: hash(argv[0])!,
		command[0]: hash(command[0])!}) + '\n')!
	os.write_file(directory + '/environment.json', json2.encode(env) + '\n')!
	os.write_file(directory + '/input-before.json', json2.encode(before) + '\n')!
	cap := endpoint(directory, 'admission', true)!
	remaining := (wall - (time.sys_mono_now() - consumer_profile_started_ns)) / time.millisecond
	need(remaining > 0, 'no consumer wall remains')!
	limit := if remaining < i64(seconds) * 1000 { int(remaining) } else { seconds * 1000 }
	result := nativeguard.supervise(command, consumer, consumer, roots(), directory + '/child.log',
		directory + '/df', nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap, wall_ms: limit, sample_ms: 1000})!
	os.write_file(directory + '/result.json', json2.encode(result) + '\n')!
	need(result.samples.len > 0, 'actual owner observations required')!
	if consumer_profile_last_sample_ns > 0 {
		need(result.samples[0].mono_ns > consumer_profile_last_sample_ns
			&& result.samples[0].mono_ns - consumer_profile_last_sample_ns <= 5 * time.second,
			'in-process gap between owned actions exceeds five seconds')!
	} else { need(result.samples[0].mono_ns - consumer_profile_started_ns <= 5 * time.second, 'entry observation gap exceeds five seconds')! }
	for i in 1 .. result.samples.len {
		need(result.samples[i].mono_ns > result.samples[i - 1].mono_ns
			&& result.samples[i].mono_ns - result.samples[i - 1].mono_ns <= 5 * time.second,
			'consumer observation gap exceeds five seconds')!
	}
	consumer_profile_sample_total += result.samples.len
	consumer_profile_last_sample_ns = result.samples[result.samples.len - 1].mono_ns
	need(consumer_profile_sample_total <= 800, 'complete native sample allowance; 200 DF endpoint sets separately reserved')!
	after := input_bindings()!
	os.write_file(directory + '/input-after.json', json2.encode(after) + '\n')!
	need(before == after, 'frozen compiler direct identities changed')!
	endpoint(directory, 'final', false)!
	need(result.reason == '' && result.group_observed && !result.held_pipe_after_leader_exit
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == C.ECHILD && result.cleanup.kill_attempts == 0
		&& result.cleanup.exit_code == expected, 'owned action status or cleanup differs: ' + label)!
	deadline()!
	return os.read_file(directory + '/child.log')!
}

fn policy() string {
	return '(version 1)\n(allow default)\n(deny network*)\n(deny file-read*\n'
		+ ' (subpath "/Users/alex/code/v-worktrees/vox-parallel-cc")\n'
		+ ' (subpath "/Users/alex/code/v"))\n(deny file-write*\n'
		+ ' (subpath "' + input + '")\n (subpath "' + audit + '")\n'
		+ ' (subpath "/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain")\n'
		+ ' (subpath "' + consumer + '/fallback-forbidden"))\n'
}

fn boehm_admission() ! {
	need(present(input + '/toolchain/thirdparty/tcc/lib/libgc.a'),
		'PROFILE ADMISSION REFUSAL: private Boehm libgc.a absent; no compiler launched')!
	return error('fixed missing-library control no longer applies; re-review profile')
}

fn source_rows() ![][]string {
	mut rows := [][]string{}
	mut seen := map[string]bool{}
	for line in $embed_file('current-target-consumer-sources.txt').to_string().split_into_lines() {
		fields := line.fields()
		need(fields.len == 3 && fields[0] in ['100644', '120000'] && fields[1].len == 40
			&& !fields[2].starts_with('/') && !fields[2].split('/').any(it in ['', '.', '..'])
			&& fields[2] !in seen, 'fixed source closure row differs')!
		seen[fields[2]] = true
		rows << fields
	}
	need(rows.len == 65, 'complete fixed source row count')!
	return rows
}

fn blob(path string, link bool) !string {
	bytes := if link { os.readlink(path)!.bytes() } else { os.read_bytes(path)! }
	mut blob_bytes := ('blob ' + bytes.len.str() + '\x00').bytes()
	blob_bytes << bytes
	return sha1.sum(blob_bytes).hex()
}

fn staged_inputs() !map[string]string {
	mut result := map[string]string{}
	for fields in source_rows()! {
		path := source + '/' + fields[2]
		link := fields[0] == '120000'
		need(os.is_link(path) == link && blob(path, link)! == fields[1],
			'captured producer source differs: ' + path)!
		if link {
			need(os.real_path(path).starts_with(source + '/'), 'captured module alias escapes')!
			result[path] = os.readlink(path)!
		} else { result[path] = identity(path)! }
	}
	for relative in ['tests/socket-peer-login/qualify-current-target-consumer.v',
		'tests/socket-peer-login/currenttargetrecord/core.v',
		'tests/socket-peer-login/currenttargetprobe/main.v',
		'tests/socket-peer-login/preserveoutputs/core.v',
		'tests/socket-peer-login/preserveoutputs/README.md',
		'tests/socket-peer-login/preserve-outputs-controls.v',
		'tests/socket-peer-login/current-target-consumer-sources.txt',
		'tests/socket-peer-login/check-current-target-bootstrap-inputs.v',
		'tests/socket-peer-login/check-current-target-consumer-inputs.v'] {
		result[source + '/' + relative] = identity(source + '/' + relative)!
	}
	need(result.len == 74, '65 captured producers and nine independent helpers required')!
	need(hash(source + '/tests/socket-peer-login/check-current-target-bootstrap-inputs.v')!
		== '957b602391c518a14fa1bb1b8d533138a038fc27548eeda8285827112a003918',
		'captured original comparer source differs')!
	mut expected := result.keys()
	for path in result.keys() {
		mut parent := os.dir(path)
		for parent != source {
			need(parent.starts_with(source + '/'), 'source parent escaped')!
			if parent !in expected { expected << parent }
			parent = os.dir(parent)
		}
	}
	expected << source
	mut actual := []string{}
	source_entries(source, mut actual)!
	expected.sort()
	actual.sort()
	need(actual == expected, 'captured source file/directory set differs; no added empty directories')!
	return result
}

fn source_entries(path string, mut actual []string) ! {
	need(actual.len < 512, 'bounded complete private source closure')!
	actual << path
	info := os.lstat(path)!
	if info.mode & 0o170000 == 0o040000 {
		need(os.real_path(path) == path && info.uid == u32(os.getuid()) && info.mode & 0o022 == 0,
			'canonical owned source directory required')!
		for name in os.ls(path)! { source_entries(path + '/' + name, mut actual)! }
	}
}

fn allowed_dependency(path string) bool {
	return [consumer, input + '/toolchain', sdk, resource_headers].any(path.starts_with(it + '/'))
}

// Native lists are evidence only after each literal and resolved path has been
// checked. This deliberately makes no general SDK or dynamic loader claim.
fn dependency_value(path string) !string {
	need(path.starts_with('/') && !path.contains('\x00') && allowed_dependency(path),
		'undeclared dependency literal path: ' + path)!
	resolved := os.real_path(path)
	need(resolved != '' && allowed_dependency(resolved), 'dependency resolves outside declared roots: ' + path)!
	before := os.lstat(resolved)!
	need(before.mode & 0o170000 == 0o100000 && before.nlink > 0, 'ordinary dependency required')!
	digest := hash(resolved)!
	after := os.lstat(resolved)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime,
		'dependency changed during hash: ' + path)!
	return json2.encode({'resolved': resolved, 'literal_mode': os.lstat(path)!.mode.str(),
		'literal_link': if os.is_link(path) { os.readlink(path)! } else { '' },
		'dev': before.dev.str(), 'inode': before.inode.str(), 'mode': before.mode.str(),
		'uid': before.uid.str(), 'gid': before.gid.str(), 'nlink': before.nlink.str(),
		'size': before.size.str(), 'mtime': before.mtime.str(), 'ctime': before.ctime.str(),
		'sha256': digest})
}

fn dependency_lines(text string) !map[string]string {
	need(text.len > 0 && text.len <= 1024 * 1024, 'bounded complete dependency list required')!
	mut result := map[string]string{}
	for path in text.split_into_lines() {
		need(path != '' && path !in result && result.len < 4096, 'duplicate or excess dependency rows')!
		result[path] = dependency_value(path)!
	}
	need(result.len > 0, 'positive dependency closure required')!
	return result
}

fn native_dependencies(text string) !map[string]string {
	need(text.len > 0 && text.len <= 1024 * 1024 && !text.contains('\x00')
		&& !text.contains('$') && !text.contains('`'), 'bounded literal clang dependency rule required')!
	flat := text.replace('\\\n', '')
	colon := flat.index(':') or { return error('clang dependency target missing') }
	need(colon > 0 && !flat[..colon].contains('\n'), 'one literal clang dependency target required')!
	mut token := ''
	mut escaped := false
	mut paths := []string{}
	for ch in (flat[colon + 1..] + ' ').bytes() {
		if escaped {
			need(ch in [` `, `\t`, `\\`, `#`], 'unsupported clang dependency escape')!
			token += ch.ascii_str()
			escaped = false
		} else if ch == `\\` { escaped = true }
		else if ch in [` `, `\t`, `\n`, `\r`] {
			if token != '' { paths << token; token = '' }
		} else {
			need(ch !in [`:`, `#`], 'unsupported secondary clang dependency rule')!
			token += ch.ascii_str()
		}
	}
	need(!escaped && paths.len > 0, 'complete clang dependency tokens required')!
	return dependency_lines(paths.join('\n'))!
}

fn derived_input_checker() !string {
	original_text := $embed_file('check-current-target-bootstrap-inputs.v').to_string()
	need(sha256.hexhash(original_text) == '957b602391c518a14fa1bb1b8d533138a038fc27548eeda8285827112a003918',
		'qualified fixed comparer source differs')!
	rules := [
		["const setup = state + '/target-freeze-host-01'", "const setup = state + '/target-consumer-host-01'"],
		["const output = setup + '/tool-inputs-02'", "const output = setup + '/tool-inputs'"],
		['--check-after-copier', '--check-before-consumer'],
		['--check-after-freezer', '--check-after-consumer'],
		["'after-copier'", "'before-consumer'"],
		["'after-freezer'", "'after-consumer'"],
		["$" + "embed_file('check-current-target-bootstrap-inputs.v')", "$" + "embed_file('check-current-target-consumer-inputs.v')"],
	]
	expected_counts := [1, 1, 2, 1, 1, 1, 1]
	need(rules.len == expected_counts.len, 'fixed comparer rule/count lengths differ')!
	mut counts := []int{}
	mut result := original_text
	for i, rule in rules {
		count := result.count(rule[0])
		need(count == expected_counts[i], 'fixed comparer derivation exact count')!
		counts << count
		result = result.replace(rule[0], rule[1])
	}
	mut inverse := result
	for i := rules.len - 1; i >= 0; i-- {
		need(inverse.count(rules[i][1]) == counts[i], 'fixed comparer inverse count')!
		inverse = inverse.replace(rules[i][1], rules[i][0])
	}
	need(inverse == original_text, 'fixed comparer complete inverse differs')!
	os.write_file(consumer + '/source-03-comparer-derivation.json', json2.encode({
		'original_sha256': sha256.hexhash(original_text), 'derived_sha256': sha256.hexhash(result),
		'rules': json2.encode(rules), 'counts': json2.encode(counts), 'inverse': 'exact'}) + '\n')!
	return result
}

fn stage() ! {
	need(os.read_file(@FILE)! == $embed_file('qualify-current-target-consumer.v').to_string(),
		'consumer profile source differs from compiled source')!
	need(os.real_path(consumer) == consumer && os.is_dir(consumer)
		&& !present(source) && !present(source_receipt)
		&& !present(consumer + '/source-03-admission.json'), 'fresh canonical source capture required')!
	endpoint(consumer, 'source-03-admission', true)!
	mut before := map[string]string{}
	checker_path := repository + '/tests/socket-peer-login/check-current-target-bootstrap-inputs.v'
	checker_body := $embed_file('check-current-target-bootstrap-inputs.v').to_string()
	need(sha256.hexhash(checker_body) == '957b602391c518a14fa1bb1b8d533138a038fc27548eeda8285827112a003918'
		&& hash(checker_path)! == '957b602391c518a14fa1bb1b8d533138a038fc27548eeda8285827112a003918',
		'qualified original comparer required before capture')!
	before[checker_path] = identity(checker_path)!
	for fields in source_rows()! {
		path := repository + '/' + fields[2]
		link := fields[0] == '120000'
		need(os.is_link(path) == link && blob(path, link)! == fields[1], 'reviewed source bytes differ: ' + path)!
		before[path] = if link { os.readlink(path)! } else { identity(path)! }
	}
	os.mkdir(source)!
	for fields in source_rows()! {
		original_path := repository + '/' + fields[2]
		copy := source + '/' + fields[2]
		os.mkdir_all(os.dir(copy))!
		if fields[0] == '120000' { os.symlink(os.readlink(original_path)!, copy)! }
		else {
			os.cp(original_path, copy, fail_if_exists: true)!
			os.chmod(copy, 0o644)!
			need(os.lstat(copy)!.inode != os.lstat(original_path)!.inode,
				'source capture shares original inode')!
		}
	}
	for path, value in before {
		need((if os.is_link(path) { os.readlink(path)! } else { identity(path)! }) == value,
			'producer input changed during capture: ' + path)!
	}
	for relative, body in {
		'tests/socket-peer-login/qualify-current-target-consumer.v': $embed_file('qualify-current-target-consumer.v').to_string()
		'tests/socket-peer-login/currenttargetrecord/core.v': $embed_file('currenttargetrecord/core.v').to_string()
		'tests/socket-peer-login/currenttargetprobe/main.v': $embed_file('currenttargetprobe/main.v').to_string()
		'tests/socket-peer-login/preserveoutputs/core.v': $embed_file('preserveoutputs/core.v').to_string()
		'tests/socket-peer-login/preserveoutputs/README.md': $embed_file('preserveoutputs/README.md').to_string()
		'tests/socket-peer-login/preserve-outputs-controls.v': $embed_file('preserve-outputs-controls.v').to_string()
		'tests/socket-peer-login/current-target-consumer-sources.txt': $embed_file('current-target-consumer-sources.txt').to_string()
		'tests/socket-peer-login/check-current-target-bootstrap-inputs.v': checker_body
		'tests/socket-peer-login/check-current-target-consumer-inputs.v': derived_input_checker()!
	} {
		path := source + '/' + relative
		if !relative.ends_with('/check-current-target-consumer-inputs.v') {
			need(os.read_file(repository + '/' + relative)! == body, 'embedded helper source drifted before capture')!
		}
		os.mkdir_all(os.dir(path))!
		os.write_file(path, body)!
		os.chmod(path, 0o644)!
		need(hash(path)! == sha256.hexhash(body), 'captured embedded helper bytes differ')!
	}
	need(identity(checker_path)! == before[checker_path], 'original comparer changed during capture')!
	copies := staged_inputs()!
	os.write_file(source_receipt, json2.encode({'inputs': json2.encode(before),
		'copies': json2.encode(copies), 'scope': '65 fixed producer entries including four literal internal aliases plus nine independent helpers (74 total); no compiler or input mutation.'}) + '\n')!
	endpoint(consumer, 'source-03-final', false)!
	println('CURRENT TARGET CONSUMER SOURCE PASS 65')
}

fn recorded_action(label string, argv []string, seconds int) !string {
	return action(label, argv, seconds, 0, target, true)!
}

fn producer_capture(argv []string, _log string, _timeout int, env map[string]string) !hosttest.Result {
	need(env['V'] == target && env['VEXE'] == target && env['CC'] == clang
		&& env['SDKROOT'] == sdk, 'fixed producer callback environment differs')!
	if argv.len > 0 && argv[0] == 'sh' {
		expected := ['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', source]
		need(argv == expected, 'compiler selection argv differs')!
		selected := action(consumer_profile_generation_label + '-selection', ['/bin/sh', ...argv[1..]], 20, 0, target, true)!
		need(selected == target, 'compiler selection left frozen private compiler')!
		return hosttest.Result{selected, '', 0}
	}
	return hosttest.Result{currenttargetrecord.emit(argv, recorded_action)!, '', 0}
}

// The original sampler assertions and compiler flags are retained here, with
// each external command directly owned by this profile's nativeguard API.
fn sampler_case(arch string, sanitizer bool) ! {
	flavor := if sanitizer { 'san' } else { 'plain' }
	label := 'sampler-' + arch + '-' + flavor
	work := consumer + '/' + label
	need(!present(work), 'fresh sampler state required')!
	os.mkdir(work)!
	generated := work + '/sampler.c'
	fixture := work + '/fixture.c'
	consumer_profile_generation_label = label + '-sampler'
	generators.generate_sampler_with_capture(generated, arch, true, producer_capture)!
	consumer_profile_generation_label = label + '-fixture'
	hosttest.generate_module_with_full_capture(source + '/tests/alloc-bench/samplerfixture', fixture,
		arch, []string{}, producer_capture)!
	hosttest.emit_module_header(source + '/kernel/heapbench', generated, work + '/sampler.h')!
	mut flags := [clang, '-arch', if arch == 'amd64' { 'x86_64' } else { arch },
		'-isysroot', sdk, '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
	if sanitizer { flags << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	action(label + '-sampler-object', [...flags, '-MD', '-MF', work + '/sampler.d',
		'-DVINIX_KALLOC_HOST_TEST', '-I', source + '/kernel/c', '-c', generated, '-o', work + '/sampler.o'],
		120, 0, target, true)!
	imports := action(label + '-imports', ['/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm',
		'-u', work + '/sampler.o'], 30, 0, target, true)!
	need(!hosttest.allocation_symbols(imports), 'sampler has allocator imports: ' + imports)!
	action(label + '-fixture-object', [...flags, '-MD', '-MF', work + '/fixture.d',
		'-Wno-unused-function', '-Wno-unused-parameter', '-I', source + '/tests/alloc-bench/samplerfixture',
		'-c', fixture, '-o', work + '/fixture.o'], 120, 0, target, true)!
	action(label + '-varargs-object', [...flags, '-MD', '-MF', work + '/varargs.d',
		'-c', source + '/tests/alloc-bench/samplerfixture/varargs-' + arch + '.S',
		'-o', work + '/varargs.o'], 120, 0, target, true)!
	mut native := map[string]string{}
	for name in ['sampler', 'fixture', 'varargs'] {
		for path, value in native_dependencies(os.read_file(work + '/' + name + '.d')!)! { native[path] = value }
	}
	os.write_file(work + '/compiled-native-inputs.json', json2.encode(native) + '\n')!
	action(label + '-link', [...flags, work + '/sampler.o', work + '/fixture.o', work + '/varargs.o',
		'-o', work + '/sampler-test'], 120, 0, target, true)!
	output := action(label + '-run', [work + '/sampler-test'], 180, 0, target, true)!
	need(output == 'Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed\n',
		'independent sampler fixture verdict differs')!
	for path, expected in native { need(dependency_value(path)! == expected, 'compiled sampler native dependency drifted')! }
	os.write_file(work + '/sampler.stdout', output)!
	os.write_file(work + '/artifacts.json', json2.encode({
		'sampler_c': identity(generated)!, 'fixture_c': identity(fixture)!,
		'sampler_object': identity(work + '/sampler.o')!, 'fixture_object': identity(work + '/fixture.o')!,
		'varargs_object': identity(work + '/varargs.o')!, 'executable': identity(work + '/sampler-test')!,
		'header': identity(work + '/sampler.h')!}) + '\n')!
	println('SAMPLER / OOM / zeroing / clock / callback ABI / allocator imports: PASS ' + arch + ' ' + flavor)
}

fn consumer_actions() ! {
	tools := action('00-tools-before', [input_checker, '--check-before-consumer'], 30, 0, target, false)!
	need(tools.starts_with('CURRENT TARGET BOOTSTRAP INPUTS PASS '), 'complete selected tool precheck differs')!
	text := action('01-private-read', ['/bin/cat', input + '/toolchain/v.mod'], 10, 0, target, true)!
	need(text == os.read_file(input + '/toolchain/v.mod')!, 'private sandbox read differs')!
	denial := action('02-baked-read-refusal', ['/bin/cat', '/Users/alex/code/v-worktrees/vox-parallel-cc/v.mod'], 10, 1, target, true)!
	need(denial.contains('Operation not permitted'), 'baked source denial was not observed')!
	shared_denial := action('02-shared-v-read-refusal', ['/bin/cat', '/Users/alex/code/v/v.mod'], 10, 1, target, true)!
	need(shared_denial.contains('Operation not permitted'), 'shared compiler tree denial was not observed')!
	missing := action('03-missing-boehm-admission', [os.executable(), '--missing-boehm-control'], 10, 1, target, true)!
	need(missing.trim_space() == 'PROFILE ADMISSION REFUSAL: private Boehm libgc.a absent; no compiler launched',
		'missing private library must refuse at profile admission')!
	for label in ['normal', 'prod'] {
		executable := if label == 'normal' { callback_controls_normal } else { callback_controls }
		callbacks := action('03-callback-controls-' + label,
			[executable, '--state-dir', consumer + '/callback-controls-' + label], 30, 0, target, true)!
		need(callbacks == 'Native generator callback controls: PASS (6 controls)\n', 'callback control verdict differs')!
	}
	invalid := action('03-cli-refusal', [os.executable(), '--unknown'], 10, 2, target, true)!
	need(invalid.trim_space() == 'fixed consumer mode required', 'unknown CLI mode did not refuse')!
	stage_sha := hash(source_receipt)!
	stage_before := staged_inputs()!
	repeat := action('03-stage-repeat-refusal', [os.executable(), '--stage'], 10, 1, target, true)!
	need(repeat.trim_space() == 'fresh canonical source capture required'
		&& hash(source_receipt)! == stage_sha && staged_inputs()! == stage_before,
		'source repeat refusal altered captured inputs')!
	private_paths := vlib
	common := [target, '-new-compiler', '-b', 'c', '-nocache', '-no-parallel', '-no-retry-compilation',
		'-gc', 'none', '-cflags', '-isysroot ' + sdk, '-path', private_paths]
	frontend := action('04-host-v-inputs', [...common, '-cc', '/usr/bin/false', '-print-v-files',
		source + '/tests/socket-peer-login/currenttargetprobe/main.v'], 90, 0, target, true)!
	need(frontend.split_into_lines().any(it.starts_with(vlib + '/'))
		&& !frontend.contains('/Users/alex/code/v-worktrees/vox-parallel-cc/'), 'private stdlib selection not proved')!
	os.write_file(consumer + '/host-v-files.txt', frontend)!
	host_v := dependency_lines(frontend)!
	os.write_file(consumer + '/host-v-identities.json', json2.encode(host_v) + '\n')!
	action('05-host-syntax', [...common, '-cc', '/usr/bin/false', '-check-syntax',
		source + '/tests/socket-peer-login/currenttargetprobe/main.v'], 90, 0, target, true)!
	action('06-host-c-emission', [...common, '-cc', clang, '-dump-files', consumer + '/host-build-inputs.txt',
		'-o', consumer + '/private-probe.c', source + '/tests/socket-peer-login/currenttargetprobe/main.v'], 180, 0, target, true)!
	dumped := dependency_lines(os.read_file(consumer + '/host-build-inputs.txt')!)!
	os.write_file(consumer + '/host-build-input-identities.json', json2.encode(dumped) + '\n')!
	action('07-host-c-compile', [clang, '-std=gnu11', '-O2', '-g', '-Werror=incompatible-pointer-types',
		'-Werror=incompatible-function-pointer-types', '-Werror=format', '-isysroot', sdk,
		'-MD', '-MF', consumer + '/host-c-inputs.d', consumer + '/private-probe.c',
		'-o', host_probe, '-lpthread', '-lm'], 120, 0, target, true)!
	native := native_dependencies(os.read_file(consumer + '/host-c-inputs.d')!)!
	os.write_file(consumer + '/host-native-input-identities.json', json2.encode(native) + '\n')!
	need(host_v == dependency_lines(frontend)!, 'host V inputs drifted during compilation')!
	need(dumped == dependency_lines(os.read_file(consumer + '/host-build-inputs.txt')!)!,
		'host dumped inputs drifted during compilation')!
	probe_output := action('08-private-stdlib-run', [host_probe], 30, 0, target, true)!
	need(probe_output == 'CURRENT TARGET PRIVATE STDLIB PASS\n', 'private stdlib runtime probe differs')!
	for arch in ['arm64', 'amd64'] {
		for flavor in ['plain', 'san'] {
			sampler_case(arch, flavor == 'san')!
		}
	}
	need(native == native_dependencies(os.read_file(consumer + '/host-c-inputs.d')!)!,
		'actual host C dependencies changed during consumers')!
}

fn qualify() ! {
	consumer_profile_started_ns = time.sys_mono_now()
	nativeguard.watch_interrupts()!
	need(os.read_file(@FILE)! == $embed_file('qualify-current-target-consumer.v').to_string(),
		'consumer profile source differs from compiled source')!
	need(!present(consumer + '/actions') && !present(consumer + '/status.json')
		&& !present(consumer + '/consumer.sb') && !present(consumer + '/qualify-admission.json'),
		'fresh profile state required; no automatic retry')!
	endpoint(consumer, 'qualify-admission', true)!
	mut success := false
	defer {
		if !success {
			os.write_file(consumer + '/status.json', json2.encode({'status': 'FAIL',
				'scope': 'Consumer profile did not complete all final checks; preserve retained action and audit evidence.'}) + '\n') or { eprintln(err) }
		}
	}
	before := staged_inputs()!
	need(hosttest.root() == source && generators.root() == source
		&& @FILE == source + '/tests/socket-peer-login/qualify-current-target-consumer.v',
		'qualifier must be bootstrapped from the independent captured producer closure')!
	input_bindings()!
	for name in ['actions', 'tmp', 'home', 'bin'] {
		if name == 'bin' && present(consumer + '/bin') { continue }
		os.mkdir(consumer + '/' + name)!
	}
	os.write_file(consumer + '/consumer.sb', policy())!
	check_argv := [original, 'check', input, audit + '/complete-input/inventory.json']
	pre := action('00-original-input-check', check_argv, 180, 0, target, false)!
	need(pre.trim_space() == 'FRAME-PAGE COMPLETE STATE CHECK PASS', 'complete input precheck marker differs')!
	mut failure := ''
	consumer_actions() or {
		failure = err.msg()
		os.write_file(consumer + '/consumer-error.txt', failure + '\n')!
	}
	after_tools := action('98-tools-after', [input_checker, '--check-after-consumer'], 30, 0, target, false) or {
		failure += '\ntool postcheck: ' + err.msg()
		''
	}
	if !after_tools.starts_with('CURRENT TARGET BOOTSTRAP INPUTS PASS ') {
		failure += '\ncomplete selected tool postcheck did not pass'
	}
	// Even a refused consumer needs the unchanged original full postcheck. Its own
	// fresh floor/deadline admission still applies; a refused postcheck stays failed.
	post := action('99-original-input-postcheck', check_argv, 180, 0, target, false) or {
		os.write_file(consumer + '/postcheck-failure.json', json2.encode({'status': 'FAIL', 'consumer_error': failure,
			'postcheck_error': err.msg(), 'scope': 'Postcheck not complete; retain all evidence.'}) + '\n')!
		return err
	}
	need(post.trim_space() == 'FRAME-PAGE COMPLETE STATE CHECK PASS', 'complete input postcheck marker differs')!
	after := staged_inputs()!
	need(before == after, 'complete captured producer sources changed')!
	endpoint(consumer, 'final', false)!
	need(failure == '', failure)!
	deadline()!
	need(consumer_profile_last_sample_ns > 0 && time.sys_mono_now() - consumer_profile_last_sample_ns <= 5 * time.second,
		'final receipt phase exceeded five-second last-observation bound')!
	os.write_file(consumer + '/status.json', json2.encode({'status': 'PASS',
		'elapsed_ns': (time.sys_mono_now() - consumer_profile_started_ns).str(), 'samples': consumer_profile_sample_total.str(),
		'scope': 'Explicit none-GC relocated compiler, private input path controls and independent sampler fixtures only. No Boehm, full kernel, candidate semantic guards, guest or desktop qualification.'}) + '\n')!
	endpoint(consumer, 'receipt-final', false)!
	deadline()!
	need(time.sys_mono_now() - consumer_profile_last_sample_ns <= 5 * time.second, 'final endpoint exceeded last-observation bound')!
	success = true
	println('CURRENT TARGET CONSUMER PASS')
}

fn rename_size() !u64 {
	path := consumer + '/rename-01'
	info := os.lstat(path)!
	need(os.real_path(path) == path && info.mode & 0o170000 == 0o040000
		&& info.uid == u32(os.getuid()) && info.mode & 0o022 == 0,
		'canonical owned rename scope required')!
	used := nativeguard.allocated([path], os.lstat(consumer)!.dev)!
	need(used <= u64(10) << 20 && apparent([path])! <= u64(10) << 20,
		'complete rename source/compiler/control state exceeds 10MiB')!
	return used
}

fn rename_qualify() ! {
	rename_started_ns := time.sys_mono_now()
	consumer_profile_started_ns = rename_started_ns
	nativeguard.watch_interrupts()!
	need(@FILE == source + '/tests/socket-peer-login/qualify-current-target-consumer.v'
		&& os.read_file(@FILE)! == $embed_file('qualify-current-target-consumer.v').to_string(),
		'qualified captured-source driver required')!
	names := consumer + '/rename-01'
	executable := names + '/bin/preserve-outputs-controls'
	need(os.real_path(names) == names && os.is_dir(names) && !present(names + '/native')
		&& !present(names + '/status.json') && !present(names + '/controls')
		&& !present(names + '/policy.sb'), 'fresh fixed rename control state required')!
	mut success := false
	defer {
		if !success {
			os.write_file(names + '/status.json', json2.encode({'status': 'FAIL',
				'scope': 'Rename qualification did not finish all source/status/cleanup/accounting/timing gates.'}) + '\n') or { eprintln(err) }
		}
	}
	for path, expected in {
		source + '/tests/socket-peer-login/preserveoutputs/core.v': 'ffc04263138c29c1c8dbaef7a65113283ad753968546e42cad331f06893bf437'
		source + '/tests/socket-peer-login/preserve-outputs-controls.v': 'd61c643cd05824f0605c0a0127d270017956ed2e9bf500a0aee21280cfcb28e7'
	} { need(hash(path)! == expected, 'reviewed rename source differs')! }
	before := staged_inputs()!
	control_before := identity(executable)!
	input_before := input_bindings()!
	os.mkdir(names + '/native')!
	os.write_file(names + '/policy.sb', policy())!
	env := environment(names + '/native', target)
	for key in os.environ().keys() { os.unsetenv(key) }
	for key, value in env { os.setenv(key, value, true) }
	argv := [sandbox, '-f', names + '/policy.sb', executable, '--controls', names + '/controls']
	os.write_file(names + '/native/argv.json', json2.encode(argv) + '\n')!
	os.write_file(names + '/native/environment.json', json2.encode(env) + '\n')!
	global_cap := endpoint(names + '/native', 'admission', true)!
	local_used := rename_size()!
	global_used := nativeguard.allocated(roots(), os.lstat(consumer)!.dev)!
	local_cap := global_used + (u64(10) << 20) - local_used
	cap := if global_cap < local_cap { global_cap } else { local_cap }
	remaining_ms := (i64(90) * time.second - (time.sys_mono_now() - rename_started_ns)) / time.millisecond
	need(remaining_ms > 0, 'rename entry deadline expired before launch')!
	child_wall := if remaining_ms < 60000 { int(remaining_ms) } else { 60000 }
	result := nativeguard.supervise(argv, names, names, roots(), names + '/native/child.log',
		names + '/native/df', nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap, wall_ms: child_wall, sample_ms: 1000})!
	os.write_file(names + '/native/result.json', json2.encode(result) + '\n')!
	need(result.samples.len > 0 && result.samples.len <= 68
		&& result.samples[0].mono_ns - rename_started_ns <= 5 * time.second,
		'bounded rename observations and entry gap required')!
	for i in 1 .. result.samples.len {
		need(result.samples[i].mono_ns > result.samples[i - 1].mono_ns
			&& result.samples[i].mono_ns - result.samples[i - 1].mono_ns <= 5 * time.second,
			'rename actual observation gap exceeds five seconds')!
	}
	need(result.reason == '' && result.group_observed && !result.held_pipe_after_leader_exit
		&& result.cleanup.exit_code == 0 && result.cleanup.kill_attempts == 0 && result.cleanup.reaped
		&& result.cleanup.group_empty && result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD,
		'rename actual status or owned cleanup differs')!
	need(os.read_file(names + '/native/child.log')! == 'KERNEL OUTPUT RENAME CONTROLS PASS 14\n',
		'exact rename completion marker differs')!
	controls := json2.decode[map[string]string](os.read_file(names + '/controls/controls.json')!)!
	need(controls['cases'] == '14' && controls['repeat_preservation_refusals'] == '3'
		&& controls['real_second_rename_eperm'] == 'passed'
		&& controls['real_cross_device_admission'].starts_with('UNAVAILABLE:'),
		'real rename refusal controls incomplete')!
	need(before == staged_inputs()! && control_before == identity(executable)!
		&& input_before == input_bindings()!, 'rename source/executable/input identities changed')!
	endpoint(names + '/native', 'final', false)!
	rename_size()!
	os.write_file(names + '/status.json', json2.encode({'status': 'PASS', 'cases': '14',
		'scope': 'Fixed new-fixture rename-only controls; no kernel build, VM, production integration or EXDEV execution.'}) + '\n')!
	endpoint(names + '/native', 'receipt-final', false)!
	rename_size()!
	need(time.sys_mono_now() - rename_started_ns < 90 * time.second
		&& time.sys_mono_now() - result.samples[result.samples.len - 1].mono_ns <= 5 * time.second,
		'rename final deadline or last-observation gap exceeded')!
	success = true
	println('CURRENT KERNEL RENAME QUALIFICATION PASS 14')
}

fn main() {
	if os.args.len != 2 || os.args[1] !in ['--stage', '--qualify', '--missing-boehm-control', '--rename-qualify'] {
		eprintln('fixed consumer mode required')
		exit(2)
	}
	match os.args[1] {
		'--stage' { stage() or { eprintln(err); exit(1) } }
		'--missing-boehm-control' { boehm_admission() or { eprintln(err); exit(1) } }
		'--rename-qualify' { rename_qualify() or { eprintln(err); exit(1) } }
		else { qualify() or { eprintln(err); exit(1) } }
	}
}
