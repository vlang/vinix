@[has_globals]
module main

import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <signal.h>
fn C.getpgid(i32) i32

__global stopped = i32(0)
fn interrupt(_ os.Signal) { stopped = 1 }

const baseline = '9acefa77bee69247c837e97987a2377536aa41cc'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'

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

fn tree(path string, mut found map[string]string) ! {
	kind := os.lstat(path)!.mode & 0o170000
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names { tree(path + '/' + name, mut found)! }
	} else if kind == 0o100000 { found[path] = digest(path)! }
	else if kind == 0o120000 {
		found['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if os.lstat(resolved)!.mode & 0o170000 != 0o100000 { return error('nonregular tool link referent: ' + path) }
		found['resolved:' + path] = resolved
		found[path] = digest(resolved)!
	} else { return error('unsupported input: ' + path) }
}

fn snapshot(root string) !map[string]string {
	mut found := map[string]string{}
	for name in os.ls(root + '/kernel/alloctrack')! {
		if name.ends_with('.v') { found[root + '/kernel/alloctrack/' + name] = digest(root + '/kernel/alloctrack/' + name)! }
	}
	for name in ['frame-page-check.v', 'frame-page-host-check.v'] {
		found[root + '/tests/kernel-allocs/' + name] = digest(root + '/tests/kernel-allocs/' + name)!
	}
	for name in ['vlib', 'thirdparty'] { tree(os.dir(compiler) + '/' + name, mut found)! }
	for path in [compiler, clang, os.dir(compiler) + '/v.mod', os.dir(compiler) + '/snapshot.json', os.executable()] {
		found[path] = digest(path)!
	}
	if found[compiler] != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| found[clang] != '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8' {
		return error('compiler digest mismatch')
	}
	for directory in os.vmodules_paths() {
		path := directory + '/alloctrack'
		if os.exists(path) || os.is_link(path) { return error('global alloctrack shadows selected module') }
		found['absent:' + path] = 'absent'
	}
	for name in ['PATH', 'HOME', 'TMPDIR', 'VTMP', 'VHOME', 'VMODULES', 'SDKROOT', 'DEVELOPER_DIR',
		'MACOSX_DEPLOYMENT_TARGET', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH',
		'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR', 'V', 'VEXE',
		'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
		'V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'VINIX_ROOT', 'CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'VFLAGS'] {
		if value := os.getenv_opt(name) { found['env:' + name] = value }
		else { found['absent-env:' + name] = 'absent' }
	}
	return found
}

fn retain_c(out string, profile string) ! {
	target := out + '/' + profile + '.c'
	if !os.is_file(target) {
		mut candidates := []string{}
		for name in os.ls(out + '/compiler-tmp')! {
			if name.starts_with(profile + '.') && name.ends_with('.tmp.c') {
				path := out + '/compiler-tmp/' + name
				if os.lstat(path)!.mode & 0o170000 != 0o100000 { return error('nonregular generated C') }
				candidates << path
			}
		}
		if candidates.len != 1 { return error('expected exactly one kept generated C') }
		os.cp(candidates[0], target)!
		os.write_file(out + '/' + profile + '.c-origin.json', json2.encode({'path': candidates[0], 'sha256': digest(candidates[0])!}) + '\n')!
	}
	text := os.read_file(target)!
	header := '_v_ret_Array_fixed_u64_10 alloctrack__frame_page_chain(u64* frame, u64 minimum) {'
	if text.count(header) != 1 { return error('shared production walker C body absent or duplicated') }
	start := text.index(header) or { return error('walker header absent') }
	end := text[start..].index('\n}') or { return error('walker body unterminated') }
	os.write_file(out + '/' + profile + '.walker.c.txt', text[start..start + end + 2] + '\n')!
}

fn group_present(pid int) !bool {
	if pid <= 1 || pid == C.getpgid(0) { return error('invalid subprocess group') }
	if C.kill(-pid, 0) == 0 { return true }
	if C.errno == C.ESRCH { return false }
	if C.errno == C.EPERM { return true }
	return error('process group probe failed')
}

fn kill_one(pid int) ! {
	if C.kill(pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return error('kill failed') }
}

// Trusted host process scope: numeric process-group observations are not a
// hostile concurrent PID/PGID identity guarantee.
fn cleanup(mut child os.Process) ! {
	if child.pid <= 1 || child.pid == C.getpgid(0) { return error('invalid cleanup scope') }
	start := time.sys_mono_now()
	for {
		if group_present(child.pid)! { kill_one(-child.pid)! }
		known_finished := child.status in [.exited, .aborted] && child.code >= 0
		if !known_finished { kill_one(child.pid)! }
		alive := child.is_alive()
		present := group_present(child.pid)!
		if !alive && child.status in [.exited, .aborted] && child.code >= 0 {
			mut status := i32(0)
			waited := C.waitpid(child.pid, &status, C.WNOHANG)
			if waited == -1 && C.errno == C.ECHILD && !present { child.wait(); return }
		}
		if time.sys_mono_now() - start >= 5_000_000_000 { return error('subprocess cleanup deadline') }
		time.sleep(20 * time.millisecond)
	}
}

fn invoke(argv []string, log_path string, cwd string) ! {
	os.write_file(log_path + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	mut complete := false
	defer {
		if !complete && child.pid > 1 { cleanup(mut child) or { eprintln(err) } }
		child.close()
	}
	mut log := os.create(log_path)!
	defer { log.close() }
	child.set_args(argv[1..]); child.set_work_folder(cwd)
	child.set_redirect_stdio_merged(); child.use_pgroup = true; child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.sys_mono_now()
	mut confirmed := false
	for _ in 0 .. 100 {
		if C.getpgid(i32(child.pid)) == i32(child.pid) { confirmed = true; break }
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	mut reason := if confirmed { '' } else { 'process group not observed' }
	mut total := 0
	for reason == '' {
		for _ in 0 .. 16 {
			chunk := child.stdout_read()
			if chunk.len == 0 { break }
			total += chunk.len
			if total > 4 * 1024 * 1024 { reason = 'output cap exceeded'; break }
			log.write_string(chunk)!
		}
		if stopped != 0 { reason = 'interrupted' }
		if time.sys_mono_now() - start > 300_000_000_000 { reason = 'wall deadline' }
		if reason != '' { break }
		if !child.is_alive() {
			if group_present(child.pid)! { reason = 'leader exited with descendants' }
			break
		}
		time.sleep(10 * time.millisecond)
	}
	cleanup(mut child)!
	complete = true
	for _ in 0 .. 16 {
		chunk := child.stdout_read()
		if chunk.len == 0 { break }
		total += chunk.len
		if total > 4 * 1024 * 1024 { reason = 'output cap exceeded'; break }
		log.write_string(chunk)!
	}
	log.close()
	os.write_file(log_path + '.status.json', json2.encode({
		'exit_code': child.code.str(), 'reason': reason,
		'cleanup': 'leader reaped and process group absent',
		'elapsed_ms': ((time.sys_mono_now() - start) / 1_000_000).str(),
	}) + '\n')!
	if reason != '' || child.code != 0 { return error('step failed; raw output retained: ' + log_path) }
}

fn budget(root string, out string) ! {
	// df is intentional: os.disk_usage misreports free space on this host.
	result := os.exec(['df', '-k', root])
	if result.exit_code != 0 { return error('df failed') }
	os.write_file(out + '/df-' + time.sys_mono_now().str() + '.log', result.output)!
	lines := result.output.trim_space().split_into_lines()
	if lines.len != 2 { return error('unexpected df output') }
	fields := lines[1].fields()
	if fields.len < 4 || fields[3].i64() < 1024 * 1024 { return error('free space below 1GiB floor') }
	// Include preserved bootstrap/failed attempts in OUT's dedicated parent.
	usage := os.exec(['du', '-sk', root, os.dir(out)])
	if usage.exit_code != 0 { return error('du failed') }
	os.write_file(out + '/du-' + time.sys_mono_now().str() + '.log', usage.output)!
	mut used := i64(0)
	for line in usage.output.trim_space().split_into_lines() { used += line.fields()[0].i64() * 1024 }
	if used > 40 * 1024 * 1024 { return error('40MiB worktree+external-state budget exceeded') }
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'seal' {
		base := os.real_path(os.args[2])
		manifest := base + '/bundle.sha256'
		if os.exists(manifest) { return error('bundle already sealed') }
		mut all := map[string]string{}
		tree(base, mut all)!
		mut paths := all.keys()
		paths.sort()
		mut lines := []string{}
		for path in paths {
			if !path.starts_with(base + '/') { return error('seal requires regular retained files') }
			lines << all[path] + '\t' + path[base.len + 1..]
		}
		os.write_file(manifest, lines.join('\n') + '\n')!
		println('FRAME-PAGE BUNDLE ' + digest(manifest)!)
		return
	}
	if os.args.len != 3 { return error('use ROOT NEW-OUT (macOS host checks only)') }
	root := os.real_path(os.args[1]); out := os.args[2]
	if !out.starts_with('/') || os.exists(out) { return error('output must be new and absolute') }
	head := os.exec(['git', '-C', root, 'rev-parse', 'HEAD'])
	if head.exit_code != 0 || head.output.trim_space() != baseline { return error('wrong isolated baseline') }
	initial_df := os.exec(['df', '-k', root])
	if initial_df.exit_code != 0 || initial_df.output.trim_space().split_into_lines().len != 2
		|| initial_df.output.trim_space().split_into_lines()[1].fields()[3].i64() < 2 * 1024 * 1024 {
		return error('fresh df below 2GiB admission')
	}
	os.mkdir_all(out)!
	os.mkdir_all(out + '/compiler-tmp')!
	os.write_file(out + '/df-admission.log', initial_df.output)!
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	for key, value in {'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VINIX_ROOT': root,
		'CFLAGS': '', 'CPPFLAGS': '', 'LDFLAGS': '', 'VFLAGS': ''} { os.setenv(key, value, true) }
	os.setenv('VTMP', out + '/compiler-tmp', true)
	before := snapshot(root)!
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	os.write_file(out + '/baseline.log', head.output)!
	diff := os.exec(['git', '-C', root, 'diff', '--', 'kernel/alloctrack/track_d_alloc_track.v'])
	if diff.exit_code != 0 { return error('cannot retain callsite diff') }
	os.write_file(out + '/callsite.patch', diff.output)!
	for path, _ in before {
		if path.starts_with(root + '/') {
			captured := out + '/source/' + path[root.len + 1..]
			os.mkdir_all(os.dir(captured))!
			os.cp(path, captured)!
		}
	}
	os.cp(os.executable(), out + '/host-runner')!
	for profile in ['normal', 'prod', 'sanitized'] {
		budget(root, out)!
		mut argv := [compiler, '-gc', 'none', '-manualfree', '-nocache', '-keepc', '-cc', clang,
			'-path', '@vlib|@vmodules|' + root + '/kernel', '-o', out + '/' + profile]
		if profile == 'prod' { argv << '-prod' }
		if profile == 'sanitized' { argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined'] }
		argv << root + '/tests/kernel-allocs/frame-page-check.v'
		invoke(argv, out + '/' + profile + '.build.log', root)!
		retain_c(out, profile)!
		budget(root, out)!
		invoke([out + '/' + profile], out + '/' + profile + '.run.log', root)!
		text := os.read_file(out + '/' + profile + '.run.log')!
		if text.count('FRAME-PAGE complete PASS') != 1 || !text.contains('FRAME-PAGE 10000-flat PASS') {
			return error('checker completion absent')
		}
		if snapshot(root)! != before { return error('selected inputs changed') }
	}
	os.write_file(out + '/inputs-after.json', json2.encode(snapshot(root)!) + '\n')!
	mut outputs := map[string]string{}
	tree(out, mut outputs)!
	os.write_file(out + '/outputs.json', json2.encode(outputs) + '\n')!
	os.write_file(out + '/result.json', json2.encode({
		'scope': 'shared walker macOS host checks only; kernel build/allocation/perf/desktop validation pending',
		'baseline': baseline, 'profiles': 'normal,prod,sanitized', 'qualification': 'false',
		'inputs_sha256': digest(out + '/inputs-before.json')!, 'outputs_sha256': digest(out + '/outputs.json')!,
		'toolchain_scope': 'V libraries and original tools hashed before/after; host SDK and original clang execute in place; not hermetic',
	}) + '\n')!
	budget(root, out)!
	println('FRAME-PAGE HOST profiles=3 PASS (kernel qualification pending)')
}

fn main() { run() or { eprintln(err); exit(1) } }
