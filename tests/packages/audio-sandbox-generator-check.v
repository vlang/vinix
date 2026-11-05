// SPDX-License-Identifier: GPL-2.0-or-later
// Focused host-generator/strict target-link check using an unchanged failed
// preparation's captured inputs. Does not capture another preparation or boot.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time
import tests.packages.audioinputs
import tests.packages.audioprepare

#include <errno.h>
#include <sys/stat.h>

const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const host_cc = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const backend = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/aarch64-linux-musl-gcc'
const reviewed_plan = 'd939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290'
const namespace_cap = u64(2048) << 20
// The whole diagnostic reserves 96MiB: 16MiB bootstrap, this 64MiB run, and
// 16MiB for original full-audit receipts and final records outside this root.
const phase_cap = u64(64) << 20
const generator_changes = ['tests/native-guest-tools/guesthost/pty.v',
	'tests/packages/audio-portal-runtime-check.v', 'tests/packages/audioinputs/generator.v',
	'tests/packages/audio-sandbox-generator-check.v']
const generator_trees = ['.githooks', 'tools/sandbox', 'build-support/native-compat-tools/compathost',
	'tests/qemu-core/fixturehost', 'tests/linuxkpi/hosttest', 'tests/native-guest-tools/guesthost',
	'tests/host-policy/policyhost', 'tests/native-policy-tools/nativepolicy',
	'tests/native-policy-tools/cpufixture', 'tests/packages/audioinputs']
const generator_files = ['AGENTS.md', 'build-support/find-v.sh',
	'build-support/native-compat-tools/main.v']

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

struct Pin {
	kind string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	nlink u64
	size u64
	mtime i64
	ctime i64
	sha256 string
	target string
}

struct Usage {
mut:
	entries int
	allocated u64
	apparent u64
	conservative_apparent u64
}

fn digest(path string) !string { return audioprepare.digest(path) }

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path
		|| path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute path: ' + path)
	}
}

fn tick(started i64, depth int, entries int) ! {
	if depth > 64 || entries > 250000 || recoveryguard.deadline_expired(started, 120000) {
		return error('selected input or namespace traversal exceeds bounded scope')
	}
}

fn metadata(path string) !Pin {
	s := os.lstat(path)!
	kind := s.mode & 0o170000
	if kind !in [u32(0o100000), u32(0o040000), u32(0o120000)] {
		return error('nonordinary selected input: ' + path)
	}
	return Pin{
		kind: if kind == 0o100000 { 'file' } else if kind == 0o040000 { 'directory' } else { 'link' }
		mode: s.mode, uid: s.uid, gid: s.gid, dev: s.dev, inode: s.inode,
		nlink: u64(s.nlink), size: s.size, mtime: s.mtime, ctime: s.ctime
	}
}

fn pin(path string) !Pin {
	before := metadata(path)!
	sum := if before.kind == 'file' { digest(path)! } else { '' }
	target := if before.kind == 'link' { os.readlink(path)! } else { '' }
	if metadata(path)! != before { return error('selected input changed during observation: ' + path) }
	return Pin{...before, sha256: sum, target: target}
}

fn capture(path string, depth int, started i64, mut result map[string]Pin) ! {
	if path in result { return }
	tick(started, depth, result.len)!
	value := pin(path)!
	result[path] = value
	if value.kind == 'directory' {
		mut names := os.ls(path)!
		names.sort()
		for name in names { capture(path + '/' + name, depth + 1, started, mut result)! }
		after := metadata(path)!
		expected := Pin{...value, sha256: '', target: ''}
		if after != expected {
			return error('selected directory changed during observation: ' + path)
		}
	}
}

fn generator_pins(p Plan, maintained string, root string, revision string) !map[string]Pin {
	if revision.len != 40 || !revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('generator revision must be an exact lowercase Git object identity')
	}
	marker := pin(root + '/.git')!
	if marker.kind != 'file' || marker.nlink != 1 { return error('generator source requires its independent worktree marker') }
	text := os.read_file(root + '/.git')!
	if !text.starts_with('gitdir: ') { return error('generator source is not a Git worktree') }
	git_dir := text.all_after('gitdir: ').trim_space()
	canonical(git_dir)!
	if text != 'gitdir: ' + git_dir + '\n' { return error('unexpected worktree marker encoding') }
	head_path := git_dir + '/HEAD'
	head := pin(head_path)!
	if head.kind != 'file' || head.size != 41 || head.sha256 != sha256.hexhash(revision + '\n')
		|| os.read_file(head_path)! != revision + '\n' {
		return error('generator worktree is not at its reviewed detached revision')
	}
	mut result := map[string]Pin{}
	capture(root, 0, time.sys_mono_now(), mut result)!
	if result[root + '/.git'] != marker { return error('generator worktree marker changed during observation') }
	for path, value in result {
		if path == root { continue }
		relative := path.all_after(root + '/')
		if relative == '.git' { continue }
		if value.kind == 'file' {
			if value.nlink != 1 { return error('generator regular files must be independent: ' + path) }
			if relative in generator_changes {
				current := pin(maintained + '/' + relative)!
				if current.kind != 'file' || value.sha256 != current.sha256
					|| value.mode & 0o7777 != current.mode & 0o7777 {
					return error('explicit generator change differs from maintained source: ' + relative)
				}
				continue
			}
		}
		expected := p.inputs['tree:source'][p.roots['source'] + '/' + relative] or {
			return error('unexpected generator source path: ' + relative)
		}
		actual := if value.kind == 'file' {
			'file|' + (value.mode & 0o7777).str() + '|' + value.sha256
		} else if value.kind == 'directory' {
			'directory|' + (value.mode & 0o7777).str()
		} else { 'link|' + value.target }
		if actual != expected { return error('unreviewed generator source difference: ' + relative) }
	}
	for relative in generator_changes {
		if root + '/' + relative !in result { return error('generator source omits explicit changed source: ' + relative) }
	}
	// Sparse checkout may omit unrelated source. Every entry in each selected
	// generator module is required so lookup cannot silently use another root.
	for original, _ in p.inputs['tree:source'] {
		if !original.starts_with(p.roots['source'] + '/') { continue }
		relative := original.all_after(p.roots['source'] + '/')
		if relative in generator_files || generator_trees.any(relative == it || relative.starts_with(it + '/')) {
			if root + '/' + relative !in result { return error('generator source omits selected module entry: ' + relative) }
		}
	}
	result[head_path] = pin(head_path)!
	if result[head_path] != head {
		return error('generator revision changed during source observation')
	}
	return result
}

fn input_pins(p Plan, maintained string) !map[string]Pin {
	mut result := map[string]Pin{}
	started := time.sys_mono_now()
	// This is source identity, not another copied capture. The broad frozen W
	// source map was already admitted by the complete preparation plan.
	for path, expected in p.inputs['tree:source'] {
		tick(started, 0, result.len)!
		value := pin(path)!
		actual := if value.kind == 'file' {
			'file|' + (value.mode & 0o7777).str() + '|' + value.sha256
		} else if value.kind == 'directory' {
			'directory|' + (value.mode & 0o7777).str()
		} else { 'link|' + value.target }
		if actual != expected { return error('frozen source differs from reviewed map: ' + path) }
		result[path] = value
	}
	failed := p.state_root
	for tree in [failed + '/inputs/cross-sysroot/include', failed + '/inputs/cross-gcc/include',
		failed + '/inputs/cross-gcc/include-fixed', failed + '/inputs/source/tools/sandbox'] {
		capture(tree, 0, started, mut result)!
	}
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libm.a', 'libpthread.a'] {
		capture(failed + '/inputs/cross-sysroot/lib/' + name, 0, started, mut result)!
	}
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] {
		capture(failed + '/inputs/cross-gcc/' + name, 0, started, mut result)!
	}
	for path in [compiler, host_cc, backend, failed + '/cross-cc', failed + '/inputs/adapter-host-cc',
		failed + '/inputs/source/tests/packages/audio-cross-cc.v', failed + '/sandbox-build/generate.log',
		maintained + '/tests/packages/audio-portal-runtime-check.v',
		maintained + '/tests/native-guest-tools/guesthost/pty.v',
		maintained + '/tests/packages/audioinputs/generator.v', @FILE, os.executable()] {
		capture(path, 0, started, mut result)!
	}
	for role in ['cc1', 'collect2', 'as', 'ld', 'lto-wrapper', 'lto-plugin'] {
		path := p.files[role]
		capture(path, 0, started, mut result)!
		value := result[path]
		if p.inputs['file:' + role][path] != 'file|' + (value.mode & 0o7777).str() + '|' + value.sha256 {
			return error('original target compiler tool differs from reviewed Plan: ' + role)
		}
	}
	if result[compiler].sha256 != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| result[host_cc].sha256 != '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		|| result[host_cc].sha256 != result[failed + '/inputs/adapter-host-cc'].sha256
		|| p.inputs['file:backend'][backend] != 'file|' + (result[backend].mode & 0o7777).str() + '|' + result[backend].sha256
		|| result[maintained + '/tests/packages/audioinputs/generator.v'].sha256
			!= sha256.hexhash($embed_file('audioinputs/generator.v').to_string()) {
		return error('pinned compiler or compiled generator factory source differs')
	}
	return result
}

fn namespace(path string, device u64, depth int, started i64, mut u Usage) ! {
	u.entries++
	tick(started, depth, u.entries)!
	mut st := C.stat{}
	if unsafe { C.lstat(&char(path.str), &st) } != 0 || u64(st.st_dev) != device
		|| st.st_blocks < 0 || st.st_size < 0 { return error('namespace lstat, device or size refused') }
	allocated := u64(st.st_blocks) * 512
	apparent := u64(st.st_size)
	if apparent > ~u64(0) - 4095 { return error('namespace rounding overflow') }
	conservative := ((apparent + 4095) / 4096) * 4096
	if allocated > ~u64(0) - u.allocated || apparent > ~u64(0) - u.apparent
		|| conservative > ~u64(0) - u.conservative_apparent { return error('namespace integer overflow') }
	u.allocated += allocated
	u.apparent += apparent
	u.conservative_apparent += conservative
	if st.st_mode & C.S_IFMT == C.S_IFDIR {
		for name in os.ls(path)! { namespace(path + '/' + name, device, depth + 1, started, mut u)! }
	} else if st.st_mode & C.S_IFMT != C.S_IFREG && st.st_mode & C.S_IFMT != C.S_IFLNK {
		return error('nonordinary namespace entry')
	}
}

fn usage(paths []string, device u64) !Usage {
	mut result := Usage{}
	for path in paths { namespace(path, device, 0, time.sys_mono_now(), mut result)! }
	return result
}

fn endpoint(p Plan, out string, name string) ! {
	device := os.lstat(out)!.dev
	phase := usage([out], device)!
	all := usage(p.charged_roots, device)!
	observation := nativeguard.actual_df(out, out + '/' + name + '-df.log')!
	os.write_file(out + '/' + name + '-usage.json', json2.encode({
		'phase_allocated_bytes': phase.allocated.str(), 'phase_apparent_bytes': phase.apparent.str(),
		'namespace_allocated_bytes': all.allocated.str(), 'namespace_apparent_bytes': all.apparent.str(),
		'phase_conservative_apparent_bytes': phase.conservative_apparent.str(),
		'namespace_conservative_apparent_bytes': all.conservative_apparent.str(),
		'available_bytes': observation.available.str(), 'phase_cap_bytes': phase_cap.str(),
		'namespace_cap_bytes': namespace_cap.str(),
		'scope': 'Completed endpoint observations. Cap checks use 4KiB-rounded apparent entries above observed 1KiB du units; raw apparent size is informational. Symlinks are not traversed; hardlinks count repeatedly. No exclusive physical-growth or continuous dual-cap claim.'
	}) + '\n')!
	if phase.allocated > phase_cap || phase.conservative_apparent > phase_cap || all.allocated > namespace_cap
		|| all.conservative_apparent > namespace_cap || observation.available < u64(1) << 30 {
		return error('phase, namespace or final free-space endpoint refused: ' + name)
	}
}

fn environment(root string, out string, failed string) map[string]string {
	mut env := {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'V': compiler, 'VEXE': compiler, 'VINIX_V_COMPILER': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VTMP': out + '/tmp', 'TMPDIR': out + '/tmp', 'VMODULES': out + '/modules',
		'VFLAGS': '-nocache', 'VINIX_ROOT': root,
		'VINIX_AUDIO_BACKEND_CC': backend,
		'VINIX_AUDIO_FROZEN_SYSROOT': failed + '/inputs/cross-sysroot',
		'VINIX_AUDIO_FROZEN_GCC': failed + '/inputs/cross-gcc'}
	for name, value in audioinputs.sandbox_generator_environment() { env[name] = value }
	return env
}

fn command(p Plan, cwd string, out string, name string, argv []string, env map[string]string) ! {
	for key, _ in os.environ() { os.unsetenv(key) }
	for key, value in env { os.setenv(key, value, true) }
	os.write_file(out + '/' + name + '.argv.json', json2.encode(argv) + '\n')!
	os.write_file(out + '/' + name + '.environment.json', json2.encode(env) + '\n')!
	mut failure := ''
	result := nativeguard.supervise(argv, cwd, out, p.charged_roots,
		out + '/' + name + '.log', out + '/' + name + '-df', nativeguard.Limits{
			start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: namespace_cap - (u64(2) << 20), wall_ms: 300000, sample_ms: 1000
		}) or { failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	os.write_file(out + '/' + name + '.result.json', json2.encode(result) + '\n')!
	os.write_file(out + '/' + name + '.error.json', json2.encode({'error': failure}) + '\n')!
	if failure != '' || result.reason != '' || !result.group_observed || !result.cleanup.reaped
		|| !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0
		|| result.held_pipe_after_leader_exit {
		return error('command or owned-group cleanup refused: ' + name)
	}
	if os.lstat(out + '/' + name + '.log')!.size > u64(16) << 20
		|| os.ls(out + '/modules')!.len != 0 { return error('command log or private modules refused') }
	endpoint(p, out, name + '-after')!
}

fn check() ! {
	$if prod {} $else { return error('compile this checker with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-sandbox-generator-check.v').to_string()) {
		return error('checker source differs from compiled source')
	}
	if os.args.len != 6 { return error('use PLAN PLAN_SHA256 NEW_OUTPUT GENERATOR_SOURCE GENERATOR_REVISION') }
	plan_path := os.args[1]
	canonical(plan_path)!
	if os.lstat(plan_path)!.size > u64(32) << 20 { return error('Plan exceeds32MiB') }
	if os.args[2] != reviewed_plan || digest(plan_path)! != reviewed_plan {
		return error('requires reviewed original failed-preparation Plan')
	}
	text := os.read_file(plan_path)!
	p := json2.decode[Plan](text)!
	if text != json2.encode(p) + '\n' || p.format != 1 || p.profile != 'matched-peer-frame-atomic-fresh-20261026'
		|| p.cap_bytes != namespace_cap || p.charged_roots.len != 6
		|| p.source_revision != '56941c3e3d059911b736f4ac21d169f122013b5d' {
		return error('original preparation profile differs')
	}
	root := p.roots['source']
	failed := p.state_root
	out := os.args[3]
	generator_source := os.args[4]
	generator_revision := os.args[5]
	maintained := os.dir(os.dir(os.dir(@FILE)))
	for path in [root, failed, out, os.dir(out), generator_source, compiler, host_cc, backend, os.executable()] { canonical(path)! }
	if os.exists(out) || os.is_link(out) || os.dir(out) != os.dir(failed)
		|| os.lstat(failed)!.mode & 0o170000 != 0o040000
		|| os.exists(failed + '/preparation.json') || os.exists(failed + '/run')
		|| !p.charged_roots.any(out.starts_with(it + '/')) {
		return error('requires fresh sibling diagnostic for the unchanged failed preparation')
	}
	if generator_source == root || !generator_source.starts_with(os.dir(failed) + '/')
		|| generator_source == failed || generator_source.starts_with(failed + '/')
		|| generator_source == out || generator_source.starts_with(out + '/')
		|| out.starts_with(generator_source + '/')
		|| os.lstat(generator_source)!.mode & 0o170000 != 0o040000 {
		return error('requires a distinct committed generator source below the charged preparation parent')
	}
	for charged in p.charged_roots {
		canonical(charged)!
		if p.charged_roots.filter(it == charged).len != 1
			|| p.charged_roots.any(it != charged && charged.starts_with(it + '/')) { return error('charged roots overlap') }
	}
	expected_environment := {'CFLAGS': '', 'CPPFLAGS': '', 'LDFLAGS': ''}
	if audioinputs.sandbox_generator_environment() != expected_environment {
		return error('generator environment must clear exactly the three target flag variables')
	}
	os.mkdir(out, mode: 0o700)!
	for name in ['tmp', 'modules'] { os.mkdir(out + '/' + name, mode: 0o700)! }
	nativeguard.watch_interrupts()!
	env := environment(generator_source, out, failed)
	for key, _ in os.environ() { os.unsetenv(key) }
	for key, value in env { os.setenv(key, value, true) }
	os.write_file(out + '/plan.sha256', reviewed_plan + '\n')!
	os.write_file(out + '/charged-roots.json', json2.encode(p.charged_roots) + '\n')!
	before := input_pins(p, maintained)!
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	generator_before := generator_pins(p, maintained, generator_source, generator_revision)!
	os.write_file(out + '/generator-source-before.json', json2.encode(generator_before) + '\n')!
	endpoint(p, out, 'before')!
	current := usage(p.charged_roots, os.lstat(out)!.dev)!
	if current.allocated > namespace_cap - phase_cap || current.conservative_apparent > namespace_cap - phase_cap {
		return error('six-root namespace lacks full 64MiB runtime-output reserve')
	}
	binary := out + '/security-compile'
	build := audioinputs.sandbox_generator_arguments(generator_source, compiler, host_cc, binary)!
	mut failure := ''
	command(p, generator_source, out, 'build-host-generator', build, env) or { failure = err.msg() }
	if failure == '' {
		command(p, generator_source, out, 'generate-sandbox', [binary, 'security-compile', 'sandbox', out + '/sandbox.c', '--arch', 'arm64'], env) or { failure = err.msg() }
	}
	if failure == '' {
		frozen := failed + '/inputs/cross-sysroot'
		argv := [failed + '/cross-cc', '--target=aarch64-linux-musl', '--sysroot=' + frozen,
			'-L' + frozen + '/lib', '-fuse-ld=lld', '-static', '-std=c11', '-O2', '-Wall', '-Wextra',
			'-Werror', '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', failed + '/inputs/source/tools/sandbox',
			out + '/sandbox.c', '-o', out + '/vinix-sandbox']
		command(p, generator_source, out, 'link-aarch64-sandbox', argv, env) or { failure = err.msg() }
	}
	after := input_pins(p, maintained)!
	os.write_file(out + '/inputs-after.json', json2.encode(after) + '\n')!
	generator_after := generator_pins(p, maintained, generator_source, generator_revision)!
	os.write_file(out + '/generator-source-after.json', json2.encode(generator_after) + '\n')!
	if before != after { return error('original source, helper, compiler or frozen capture changed') }
	if generator_before != generator_after { return error('committed generator source bytes or metadata changed') }
	if failure != '' { return error(failure) }
	elf := os.read_bytes(out + '/vinix-sandbox')!
	if elf.len < 64 || elf[..4] != [u8(0x7f), `E`, `L`, `F`] || elf[4] != 2 || elf[5] != 1
		|| elf[6] != 1 || elf[16] != 2 || elf[17] != 0 || elf[18] != 183 || elf[19] != 0 {
		return error('linked sandbox is not ELF64 little-endian AArch64 ET_EXEC')
	}
	endpoint(p, out, 'final')!
	mut artifacts := map[string]Pin{}
	capture(out, 0, time.sys_mono_now(), mut artifacts)!
	os.write_file(out + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(out + '/qualification.pending.json', json2.encode({
		'result': 'PASS', 'plan_sha256': reviewed_plan,
		'source_revision': p.source_revision, 'checker_sha256': digest(@FILE)!,
		'generator_source_root': generator_source, 'generator_source_revision': generator_revision,
		'generator_source_before_sha256': digest(out + '/generator-source-before.json')!,
		'generator_source_after_sha256': digest(out + '/generator-source-after.json')!,
		'factory_source_sha256': before[maintained + '/tests/packages/audioinputs/generator.v'].sha256,
		'controller_source_sha256': before[maintained + '/tests/packages/audio-portal-runtime-check.v'].sha256,
		'generator_sha256': digest(binary)!, 'sandbox_c_sha256': digest(out + '/sandbox.c')!,
		'aarch64_elf_sha256': digest(out + '/vinix-sandbox')!,
		'inputs_before_sha256': digest(out + '/inputs-before.json')!,
		'inputs_after_sha256': digest(out + '/inputs-after.json')!,
		'artifacts_sha256': digest(out + '/artifacts.json')!,
		'scope': 'Standalone host generator, sandbox C generation and strict AArch64 target link from unchanged failed captures; no new preparation, execution or guest qualification.'
	}) + '\n')!
	endpoint(p, out, 'receipt-final')!
	os.mv(out + '/qualification.pending.json', out + '/qualification.json')!
	println('AUDIO SANDBOX GENERATOR CHECK PASS')
}

fn main() { check() or { eprintln('audio-sandbox-generator-check: ' + recoveryguard.bounded_message(err.msg())); exit(1) } }
