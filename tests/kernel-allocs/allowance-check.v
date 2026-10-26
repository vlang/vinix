// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import copycore
import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <signal.h>
fn C.getpgid(i32) i32

__global stopped = i32(0)
__global inventory_deadline = i64(0)
__global inventory_entries = int(0)
__global inventory_active = false
fn interrupt(_ os.Signal) { stopped = 1 }

const repository = '/Users/alex/code/vinix'
const compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const archiver = '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar'

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		if inventory_active && time.sys_mono_now() > inventory_deadline { return error('input inventory deadline') }
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn checked(argv []string) !string {
	result := os.exec(argv)
	if result.exit_code != 0 { return error('command refused: ' + argv.str() + '\n' + result.output) }
	return result.output
}

fn tree(path string, ancestors []string, mut result map[string]string) ! {
	inventory_entries++
	if inventory_entries > 250000 || inventory_active && time.sys_mono_now() > inventory_deadline {
		return error('input inventory entry/deadline limit')
	}
	if ancestors.len > 128 { return error('input nesting limit: ' + path) }
	info := os.lstat(path)!
	kind := info.mode & 0o170000
	result['mode:' + path] = (info.mode & 0o177777).str()
	if kind == 0o120000 {
		result['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if resolved == '' || resolved == path || resolved in ancestors { return error('dangling/cyclic input: ' + path) }
		result['resolved:' + path] = resolved
		tree(resolved, ancestors, mut result)!
	} else if kind == 0o040000 {
		resolved := os.real_path(path)
		if resolved in ancestors { return error('cyclic directory: ' + path) }
		mut next := ancestors.clone(); next << resolved
		mut names := os.ls(path)!; names.sort()
		for name in names { tree(path + '/' + name, next, mut result)! }
	} else if kind == 0o100000 { result[path] = digest(path)! }
	else { return error('unsupported input type: ' + path) }
}

// Sampled allocated-size/free-space admission, not a filesystem quota.
fn budget(root string, parent string, admission bool) !string {
	output := checked(['/bin/df', '-k', parent])!
	lines := output.trim_space().split_into_lines()
	if lines.len != 2 || lines[1].fields().len < 4 { return error('unexpected df output') }
	minimum := if admission { i64(2097152) } else { i64(1048576) }
	if lines[1].fields()[3].i64() < minimum { return error('actual df below required floor:\n' + output) }
	usage := checked(['/usr/bin/du', '-sk', root, parent])!
	mut total := i64(0)
	for line in usage.trim_space().split_into_lines() {
		fields := line.fields()
		if fields.len < 2 { return error('unexpected du output') }
		total += fields[0].i64()
	}
	if total > 524288 { return error('observed 512MiB worktree+state budget exceeded:\n' + usage) }
	return output + '\n' + usage
}

fn snapshot(root string) !map[string]string {
	inventory_entries = 0
	inventory_deadline = time.sys_mono_now() + 120_000_000_000
	inventory_active = true
	defer { inventory_active = false }
	mut result := map[string]string{}
	result['revision'] = checked(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'])!.trim_space()
	result['tracked-patch'] = checked(['/usr/bin/git', '-C', root, 'diff', 'HEAD', '--', 'kernel', 'tests/kernel-allocs/allowed.txt'])!
	for name in os.ls(root + '/kernel')! {
		if name in ['obj', 'bin', 'cc-runtime-x86_64', 'cc-runtime-aarch64'] { continue }
		tree(root + '/kernel/' + name, [], mut result)!
	}
	tools := os.dir(os.dir(os.dir(@FILE)))
	for relative in ['tests/kernel-allocs/allowance-check.v', 'tests/kernel-allocs/copycore',
		'tests/kernel-allocs/hosttest', 'tests/kernel-allocs/run.sh'] {
		tree(tools + '/' + relative, [], mut result)!
	}
	tree(root + '/tests/kernel-allocs/allowed.txt', [], mut result)!
	tree(os.dir(compiler), [], mut result)!
	for path in [clang, archiver, '/usr/bin/make', '/bin/sh', '/usr/bin/uname', '/usr/bin/find',
		'/usr/bin/sort', '/usr/bin/sed', '/usr/bin/grep', '/usr/bin/git', '/bin/df', '/usr/bin/du',
		os.executable()] { tree(path, [], mut result)! }
	for path, expected in {
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		archiver: '20bf95222345e846483af09868180d0005a83f70e7df3503e25df9280333e33e'
	} { if result[path] != expected { return error('tool digest mismatch: ' + path) } }
	for key, value in os.environ() { result['env:' + key] = value }
	return result
}

fn group_present(pid int) !bool {
	if pid <= 1 || pid == C.getpgid(0) { return error('invalid child group') }
	if C.kill(-pid, 0) == 0 { return true }
	if C.errno == C.ESRCH { return false }
	if C.errno == C.EPERM { return true }
	return error('group probe failed')
}

// Trusted host processes; numeric PGIDs are not hostile identity handles.
fn cleanup(mut child os.Process) ! {
	if child.pid <= 1 || child.pid == C.getpgid(0) { return error('invalid cleanup scope') }
	start := time.sys_mono_now()
	for {
		if group_present(child.pid)! { if C.kill(-child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return error('kill group failed') } }
		if child.status !in [.exited, .aborted] || child.code < 0 {
			if C.kill(child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return error('kill child failed') }
		}
		alive := child.is_alive()
		if !alive && child.status in [.exited, .aborted] && child.code >= 0 && !group_present(child.pid)! {
			mut status := i32(0)
			if C.waitpid(child.pid, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD { child.wait(); return }
		}
		if time.sys_mono_now() - start > 5_000_000_000 { return error('cleanup deadline') }
		time.sleep(20 * time.millisecond)
	}
}

fn invoke(argv []string, root string, out string, parent string, prefix string) !int {
	os.write_file(out + '/' + prefix + '.budget-before.log', budget(root, parent, false)!)!
	os.write_file(out + '/' + prefix + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	mut complete := false
	defer { if !complete && child.pid > 1 { cleanup(mut child) or { eprintln(err) } }; child.close() }
	mut log := os.create(out + '/' + prefix + '.log')!
	defer { log.close() }
	child.set_args(argv[1..]); child.set_work_folder(root)
	child.set_redirect_stdio_merged(); child.use_pgroup = true; child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.sys_mono_now()
	mut confirmed := false
	for _ in 0 .. 100 {
		if C.getpgid(i32(child.pid)) == i32(child.pid) { confirmed = true; break }
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	mut reason := if confirmed { '' } else { 'group not observed' }
	mut total := 0
	mut last_budget := start
	for reason == '' {
		for _ in 0 .. 32 {
			chunk := child.stdout_read(); if chunk.len == 0 { break }
			total += chunk.len
			if total > 32 * 1024 * 1024 { reason = 'log limit'; break }
			log.write_string(chunk)!
		}
		if stopped != 0 { reason = 'interrupted' }
		if time.sys_mono_now() - start > 900_000_000_000 { reason = '15 minute deadline' }
		if time.sys_mono_now() - last_budget > 5_000_000_000 {
			observation := budget(root, parent, false) or { reason = err.msg(); '' }
			os.write_file(out + '/' + prefix + '.budget-' + time.sys_mono_now().str() + '.log', observation)!
			last_budget = time.sys_mono_now()
		}
		if reason != '' { break }
		if !child.is_alive() { if group_present(child.pid)! { reason = 'leader exited with descendants' }; break }
		time.sleep(20 * time.millisecond)
	}
	cleanup(mut child)!; complete = true
	for _ in 0 .. 32 {
		chunk := child.stdout_read(); if chunk.len == 0 { break }
		total += chunk.len
		if total > 32 * 1024 * 1024 { reason = 'log limit'; break }
		log.write_string(chunk)!
	}
	os.write_file(out + '/' + prefix + '.status.json', json2.encode({'exit_code': child.code.str(),
		'reason': reason, 'cleanup': 'leader reaped; group absent; ECHILD',
		'elapsed_ms': ((time.sys_mono_now() - start) / 1_000_000).str()}) + '\n')!
	if reason != '' { return error(prefix + ' refused; incomplete report preserved: ' + out) }
	return child.code
}

fn positive_number(text string) bool {
	if text == '' { return false }
	for ch in text { if ch < `0` || ch > `9` { return false } }
	return text.len <= 9 && text.u64() > 0
}

fn source_list(recipe string) ![]string {
	mut result := []string{}
	for line in recipe.split_into_lines() {
		if !line.starts_with('for f in ') { continue }
		if result.len != 0 || !line.contains(';') { return error('ambiguous source recipe') }
		for relative in line['for f in '.len..].all_before(';').fields() {
			if relative.starts_with('/') || relative.split('/').any(it in ['', '.', '..'])
				|| !relative.ends_with('.v') || relative.contains('\\') || relative.contains('"')
				|| relative.contains("'") || relative.contains('$') { return error('unsafe source recipe entry') }
			result << relative
		}
	}
	if result.len == 0 { return error('empty source recipe') }
	return result
}

// Match run.sh's unique file:line:column + kind sites; reject incomplete
// diagnostics instead of silently reducing a report to zero warnings.
fn warning_sites(log string, source string) ![]string {
	mut unique := map[string]bool{}
	marker := ': warning: allocation ('
	for line in log.split_into_lines() {
		if !line.contains('allocation (') { continue }
		if !line.starts_with(source + '/') || line.count(marker) != 1 || !line.ends_with(')') {
			return error('malformed/outside allocation diagnostic: ' + line)
		}
		position := line.all_before(marker)[source.len + 1..]
		fields := position.split(':')
		if fields.len != 3 || fields[0].starts_with('/') || fields[0].split('/').any(it in ['', '.', '..'])
			|| !fields[0].ends_with('.v') || !positive_number(fields[1]) || !positive_number(fields[2]) {
			return error('invalid allocation location: ' + position)
		}
		raw_kind := line.all_after(marker)
		kind := raw_kind[..raw_kind.len - 1]
		if kind == '' || kind.contains(')') || kind.contains('\t') { return error('invalid allocation kind') }
		unique[position + ' ' + kind] = true
	}
	mut result := unique.keys(); result.sort()
	if result.len == 0 { return error('compiler produced no allocation report') }
	return result
}

fn complete_report(code int, log string, source string) ![]string {
	if code != 0 { return error('compiler failed (exit ' + code.str() + '); allocation report is incomplete') }
	return warning_sites(log, source)!
}

fn counts(sites []string) !map[string]int {
	mut result := map[string]int{}
	mut unique := map[string]bool{}
	for site in sites {
		if site in unique { continue }
		unique[site] = true
		position := site.all_before(' ')
		fields := position.split(':')
		if fields.len != 3 || !positive_number(fields[1]) || !positive_number(fields[2]) { return error('invalid normalized site') }
		key := fields[0] + ' ' + site.all_after(' ')
		result[key]++
	}
	return result
}

fn allowances(text string) !map[string]int {
	mut result := map[string]int{}
	for line in text.split_into_lines() {
		if line == '' { continue }
		fields := line.split('\t')
		if fields.len != 2 || !positive_number(fields[1]) || fields[0] in result || !fields[0].contains('.v ') {
			return error('invalid/duplicate allowance: ' + line)
		}
		result[fields[0]] = fields[1].int()
	}
	if result.len == 0 { return error('empty allowance baseline') }
	return result
}

fn enforce(actual map[string]int, allowed map[string]int) ! {
	mut failures := []string{}
	for key, count in actual {
		if key !in allowed || count > allowed[key] { failures << key + ': ' + count.str() + ', allowed ' + allowed[key].str() }
	}
	failures.sort()
	if failures.len > 0 { return error('NEW: ' + failures.join('\nNEW: ')) }
}

fn controls() ! {
	if source_list('other\nfor f in main.v foo/bar.v; do :; done\n')! != ['main.v', 'foo/bar.v'] { return error('seed control') }
	for text in ['', 'for f in ; do :; done', 'for f in ../escape.v; do :; done',
		'for f in /escape.v; do :; done', 'for f in main.v; do :; done\nfor f in other.v; do :; done'] {
		mut refused := false; source_list(text) or { refused = true }
		if !refused { return error('bad seed control accepted') }
	}
	valid := '/src/main.v:1:2: warning: allocation (array initialization)\n'
	first := complete_report(0, valid + valid, '/src')!
	second := complete_report(0, valid + '/src/main.v:3:2: warning: allocation (array initialization)\n', '/src')!
	mut combined := first.clone(); combined << second
	actual := counts(combined)!
	if actual != {'main.v array initialization': 2} { return error('cross-architecture dedup control') }
	enforce(actual, allowances('main.v array initialization\t2\nunused.v struct on the heap\t1\n')!)!
	for text in ['', '/other/main.v:1:2: warning: allocation (array initialization)\n',
		'/src/main.v:x:2: warning: allocation (array initialization)\n',
		'/src/main.v:0:2: warning: allocation (array initialization)\n',
		'/src/../escape.v:1:2: warning: allocation (array initialization)\n',
		'/src/main.v:1:2: warning: allocation (array initialization\n',
		'/src/main.v:1:2: warning: allocation (array initialization))\n'] {
		mut refused := false; warning_sites(text, '/src') or { refused = true }
		if !refused { return error('bad warning control accepted') }
	}
	for code in [-1, 7] {
		mut refused := false; complete_report(code, valid, '/src') or { refused = true }
		if !refused { return error('incomplete compiler report accepted') }
	}
	for text in ['', 'main.v array initialization\t0\n', 'main.v array initialization\t2\nmain.v array initialization\t2\n'] {
		mut refused := false; allowances(text) or { refused = true }
		if !refused { return error('bad allowance control accepted') }
	}
	for allowed in [map[string]int{}, {'main.v array initialization': 1}, {'main.v struct on the heap': 2}] {
		mut refused := false; enforce(actual, allowed) or { refused = true }
		if !refused { return error('exceeded/new kind control accepted') }
	}
}

fn qualify_arch(root string, out string, parent string, arch string, before map[string]string) ![]string {
	os.write_file(out + '/budget-before.log', budget(root, parent, true)!)!
	// These defaults match run.sh's ordinary (non-ALLOC_TRACK) report scan.
	make_argv := ['/usr/bin/make', '-C', root + '/kernel', '-Bn', 'obj/blob.c.o', 'ARCH=' + arch, 'V=' + compiler,
		'PROD=false', 'CC=' + clang, 'AR=' + archiver]
	if invoke(make_argv, root, out, parent, 'make')! != 0 { return error('cannot obtain complete source recipe') }
	seed := source_list(os.read_file(out + '/make.log')!)!
	os.write_file(out + '/seed.files', seed.join('\n') + '\n')!
	source := out + '/source'; os.mkdir(source)!
	copied := copycore.copy_sources(root + '/kernel', out + '/seed.files', source)!
	os.write_file(out + '/copied.files', copied.join('\n') + '\n')!
	mut copied_inputs := map[string]string{}; tree(source, [], mut copied_inputs)!
	os.write_file(out + '/copied-before.json', json2.encode(copied_inputs) + '\n')!
	for relative in copied {
		if digest(source + '/' + relative)! != digest(root + '/kernel/' + relative)! { return error('copied source differs: ' + relative) }
	}
	mut argv := [compiler, '-nocache', '-os', 'vinix', '-enable-globals', '-nofloat', '-manualfree', '-message-limit',
		'100000', '-gc', 'none', '-target-libc-headers', '-no-closures', '-d', 'no_backtrace']
	if arch == 'aarch64' { argv << ['-arch', 'arm64', '-d', 'aarch64', '-d', 'limine_mp'] }
	else { argv << ['-arch', 'amd64'] }
	argv << ['-warn-about-allocs', '-o', out + '/kernel.c', source]
	compiler_code := invoke(argv, root, out, parent, 'compiler')!
	sites := complete_report(compiler_code, os.read_file(out + '/compiler.log')!, source)!
	os.write_file(out + '/sites.txt', sites.join('\n') + '\n')!
	after := snapshot(root)!; os.write_file(out + '/inputs-after.json', json2.encode(after) + '\n')!
	if before != after { return error('input changed during allocation scan') }
	mut copied_after := map[string]string{}; tree(source, [], mut copied_after)!
	os.write_file(out + '/copied-after.json', json2.encode(copied_after) + '\n')!
	if copied_inputs != copied_after { return error('copied source changed during scan') }
	os.write_file(out + '/budget-after.log', budget(root, parent, false)!)!
	println(arch + ': ' + copied.len.str() + ' source files, ' + sites.len.str() + ' distinct sites')
	return sites
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' { controls()!; println('ALLOWANCE CONTROLS PASS'); return }
	if os.args.len != 4 || os.args[1] != 'check' { return error('usage: allowance-check selfcheck | check REPOSITORY NEW-ABSOLUTE-OUT') }
	root := os.real_path(os.args[2]); out := os.args[3]; parent := os.dir(out)
	if root == '' || !out.starts_with('/') || os.exists(out) || os.is_link(out)
		|| os.real_path(parent) != parent || parent == root || parent.starts_with(root + '/')
		|| root.starts_with(parent + '/') { return error('fresh output outside selected repository, with canonical existing parent, required') }
	admission := budget(root, parent, true)!
	os.mkdir(out)!; os.mkdir(out + '/tmp')!; os.mkdir(out + '/modules')!; os.mkdir(out + '/cache')!
	os.write_file(out + '/budget-admission.log', admission)!
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	// Keep only the host identity needed by the captured V wrapper. Clear all
	// ambient compiler/search/test selectors (including V3CACHE/VTEST_ONLY_FN),
	// then place any defensive cache path inside the charged namespace.
	for key in os.environ().keys() {
		if key !in ['HOME', 'USER', 'LOGNAME'] { os.unsetenv(key) }
	}
	for key, value in {'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VMODULES': out + '/modules',
		'V3CACHE': out + '/cache', 'XDG_CACHE_HOME': out + '/cache',
		'VTMP': out + '/tmp', 'TMPDIR': out + '/tmp', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'} { os.setenv(key, value, true) }
	controls()!; os.write_file(out + '/controls.log', 'ALLOWANCE CONTROLS PASS\n')!
	before := snapshot(root)!; os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	os.cp(root + '/tests/kernel-allocs/allowed.txt', out + '/allowed.txt')!
	os.cp(@FILE, out + '/allowance-check.v')!
	allowed := allowances(os.read_file(out + '/allowed.txt')!)!
	mut sites := []string{}
	for arch in ['aarch64', 'x86_64'] {
		step := out + '/' + arch; os.mkdir(step)!
		found := qualify_arch(root, step, parent, arch, before) or {
			os.write_file(step + '/failure.txt', err.msg() + '\n')!
			if after := snapshot(root) { os.write_file(step + '/inputs-after-failure.json', json2.encode(after) + '\n')! }
			else { os.write_file(step + '/input-failure.txt', err.msg() + '\n')! }
			return err
		}
		sites << found
	}
	actual := counts(sites)!
	os.write_file(out + '/counts.json', json2.encode(actual) + '\n')!
	enforce(actual, allowed) or { os.write_file(out + '/failure.txt', err.msg() + '\n')!; return err }
	mut artifacts := map[string]string{}; tree(out, [], mut artifacts)!
	os.write_file(out + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(out + '/qualification.json', json2.encode({'result': 'PASS', 'counts': digest(out + '/counts.json')!,
		'allowed': digest(out + '/allowed.txt')!, 'inputs': digest(out + '/inputs-before.json')!,
		'artifacts': digest(out + '/artifacts.json')!, 'scope': 'ordinary non-ALLOC_TRACK warning scan; both compilers exit zero; allowances unchanged'}) + '\n')!
	println('ALLOWANCE BOTH ARCHITECTURES PASS ' + digest(out + '/qualification.json')!)
}

fn main() { run() or { eprintln(err); exit(1) } }
