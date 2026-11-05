// SPDX-License-Identifier: GPL-2.0-or-later
// Preparation only. Borrowed format-1 inputs never become mutable state.
module audiocontinue

import crypto.sha256
import json2
import os
import time
import tests.packages.audioinputs
import tests.packages.audiokernel
import nativeguard
import tools.packages.pkgcore

#include <errno.h>
#include <unistd.h>

fn C.getpid() int
fn C.getpgid(i32) i32

const engine2_trees = ['tools/packages', 'tools/accounts', 'tools/security-events',
	'tools/keyring', 'tools/sandbox', 'build-support/native-compat-tools/compathost',
	'tests/qemu-core/fixturehost', 'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest',
	'tests/native-policy-tools/nativepolicy', 'tests/native-policy-tools/cpufixture',
	'tests/host-policy/policyhost', 'tests/hardware-platform/hwhost',
	'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone',
	'tests/packages/audiotest', 'tests/packages/audioinputs', 'tests/packages/audioprepare',
	'tests/packages/audiokernel', 'tests/packages/audiocontinue', 'compat/ios/plist',
	'tests/software-hosted-x11/nativeguard',
	'tests/software-hosted-x11/diagnostics/recoveryguard']

const engine2_files = ['tests/packages/audio-portal-runtime-check.v',
	'tests/packages/audio-portal-retain.v', 'tests/packages/audio-portal-evidence-check.v',
	'tests/packages/audio-portal-wave-check.v', 'build-support/native-compat-tools/main.v',
	'build-support/security-tools/compile-v-core', 'build-support/run-v-tool.sh',
	'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v',
	'tests/packages/audio-input-check.v', 'tests/packages/audio-cross-probe.v',
	'tests/packages/audio-portal-prepare-check.v', 'build-support/limine.conf',
	'tests/hardware-platform/run.v', 'tests/packages/audio-portal-continuation.v']

pub fn source_selected2(path string) bool {
	return path in engine2_files || engine2_trees.any(path == it || path.starts_with(it + '/'))
}

struct Engine2 {
	plan Plan2
	plan_path string
	plan_sha256 string
	legacy LegacyPlan2
	donor Donor2
	source Source2
	started i64
mut:
	fresh map[string]Fresh2
	command_count int
}

struct Refusal2 {
	format int = 2
	profile string = format2_profile
	native_qualification bool
	failures []string
}

struct AuditBarrier2 {
	pid int
	observed_pgid int
	parent_uid int
	parent_euid int
}

fn engine2_digest(path string) !string {
	stat := os.lstat(path)!
	if stat.mode & 0o170000 != 0o100000 { return error('expected ordinary fresh file: ' + path) }
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn engine2_text(path string, value string) ! {
	os.mkdir_all(os.dir(path))!
	write_new2(path, value)!
}

fn (mut e Engine2) record(key string, relative string, kind string) ! {
	if key in e.fresh { return error('duplicate fresh artifact role: ' + key) }
	e.fresh[key] = Fresh2{path: relative, kind: kind,
		sha256: engine2_digest(e.plan.state_root + '/' + relative)!}
}

fn (e &Engine2) command_context() CommandContext2 {
	return CommandContext2{plan: e.plan, legacy: e.legacy, donor: e.donor,
		plan_path: e.plan_path, plan_sha256: e.plan_sha256}
}

fn (e &Engine2) remaining_ms() !int {
	elapsed := (time.sys_mono_now() - e.started) / 1_000_000
	if elapsed < 0 || elapsed >= e.plan.wall_ms { return error('complete preparation wall deadline exceeded') }
	remaining := i64(e.plan.wall_ms) - elapsed
	return int(if remaining < 300000 { remaining } else { i64(300000) })
}

// nativeguard owns each inherited process group. Temporarily replacing the
// environment is synchronous; no worker thread or independent child is used.
fn (mut e Engine2) command(role string) ! {
	spec := command_spec2(e.command_context(), role)!
	argv := spec.argv
	log_relative := spec.log_relative
	wall_ms := e.remaining_ms()!
	out := e.plan.state_root
	usage := usage2(e.legacy.charged_roots)!
	if usage.allocated > aggregate_cap2 - e.plan.receipt_reserve_bytes
		|| usage.apparent > aggregate_cap2 - e.plan.receipt_reserve_bytes {
		return error('pre-command dual namespace endpoint reserve refused')
	}
	log := out + '/' + log_relative
	os.mkdir_all(os.dir(log))!
	for suffix in ['', '.argv.json', '.environment.json', '.result.json', '.error.json'] {
		if os.exists(log + suffix) || os.is_link(log + suffix) { return error('command output already exists') }
	}
	environment := spec.environment
	write_new2(log + '.argv.json', json2.encode(argv) + '\n')!
	write_new2(log + '.environment.json', json2.encode(environment) + '\n')!
	saved := os.environ()
	for name, _ in saved { os.unsetenv(name) }
	for name, value in environment { os.setenv(name, value, true) }
	defer {
		for name, _ in os.environ() { os.unsetenv(name) }
		for name, value in saved { os.setenv(name, value, true) }
	}
	mut failure := ''
	result := nativeguard.supervise(argv, out + '/inputs/source', out,
		e.legacy.charged_roots, log, log + '.df', nativeguard.Limits{
		start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
		cap_bytes: aggregate_cap2 - e.plan.receipt_reserve_bytes,
		wall_ms: wall_ms, sample_ms: 1000
	}) or { failure = err.msg(); nativeguard.Result{} }
	write_new2(log + '.result.json', json2.encode(result) + '\n')!
	write_new2(log + '.error.json', json2.encode({'error': failure}) + '\n')!
	e.command_count++
	if failure != '' || result.reason != '' || !result.group_observed
		|| result.held_pipe_after_leader_exit || !result.cleanup.reaped
		|| !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0 {
		return error('command or inherited-group cleanup refused: ' + log_relative)
	}
	e.remaining_ms()!
	final_usage := usage2(e.legacy.charged_roots)!
	if final_usage.allocated > aggregate_cap2 - e.plan.receipt_reserve_bytes
		|| final_usage.apparent > aggregate_cap2 - e.plan.receipt_reserve_bytes {
		return error('post-command dual namespace endpoint reserve refused')
	}
}

fn (mut e Engine2) copy_source() ! {
	root := e.plan.state_root + '/inputs/source'
	os.mkdir(root)!
	mut copied := map[string]bool{}
	for entry in e.source.entries {
		if entry.kind != 'file' || !source_selected2(entry.path) { continue }
		destination := root + '/' + entry.path
		os.mkdir_all(os.dir(destination))!
		copy_new2(e.source.root + '/' + entry.path, destination, e.donor)!
		os.chmod(destination, int(entry.mode & 0o7777))!
		copied[entry.path] = true
	}
	for path in engine2_files {
		if !copied[path] { return error('fresh source manifest lacks required file: ' + path) }
	}
	for tree in engine2_trees {
		if !copied.keys().any(it.starts_with(tree + '/')) {
			return error('fresh source manifest lacks required tree: ' + tree)
		}
	}
	copy_new2(os.executable(), e.plan.state_root + '/inputs/controller', e.donor)!
	os.chmod(e.plan.state_root + '/inputs/controller', 0o755)!
	if engine2_digest(e.plan.state_root + '/inputs/controller')! != e.plan.controller_sha256 {
		return error('fresh controller copy differs')
	}
	e.record('controller', 'inputs/controller', 'host')!
	engine2_text(e.plan.state_root + '/source-before.json',
		json2.encode(capture_owned2(root, [], e.donor)!) + '\n')!
	e.record('source-before', 'source-before.json', 'metadata')!
}

fn (mut e Engine2) v_program(relative string, name string, key string) ! {
	out := e.plan.state_root
	os.mkdir_all(out + '/' + relative)!
	base := relative + '/' + name
	e.command(relative + '/generate.log')!
	e.command(relative + '/build.log')!
	e.record(key, base, 'target')!
	e.record('generated/' + base + '.c', base + '.c', 'generated')!
}

struct EngineCompletion2 {
	engine Engine2
	path string
	sha string
}

fn (g EngineCompletion2) verify_candidate() ! {
	validate_preparation_candidate2(g.path, g.sha)!
}

fn (g EngineCompletion2) verify_resources() ! {
	usage := usage2(g.engine.legacy.charged_roots)!
	if usage.allocated > aggregate_cap2 || usage.apparent > aggregate_cap2 {
		return error('sealed preparation exceeds final dual namespace cap')
	}
}

fn (g EngineCompletion2) verify_cancellation() ! {
	root := g.engine.plan.state_root
	// Reuse the existing owner's sticky cancellation check during synchronous
	// proof reads; this introduces no new process owner or signal handler.
	nativeguard.allocated([root], os.lstat(root)!.dev)!
}

fn (g EngineCompletion2) verify_deadline() ! {
	g.engine.remaining_ms()!
}

fn (mut e Engine2) build_targets() ! {
	out := e.plan.state_root
	root := out + '/inputs/source'
	v := e.legacy.roots['compiler'] + '/v'
	host_cc := e.legacy.files['clang']
	if host_cc == '' { return error('reviewed original host compiler role is absent') }
	if engine2_digest(v)! != engine2_digest(borrow_path2(e.donor, 'v')!)!
		|| engine2_digest(host_cc)! != engine2_digest(borrow_path2(e.donor, 'host-cc')!)! {
		return error('original V or host compiler differs from immutable donor identity')
	}
	e.command('cross-adapter-build.log')!
	e.record('adapter', 'cross-cc', 'host')!
	e.record('adapter-c', 'cross-cc.c', 'generated')!
	e.command('cross-probe-generate.log')!
	e.command('cross-search.log')!
	e.record('cross-probe', 'cross-probe', 'target')!
	e.record('generated/cross-probe.c', 'cross-probe.c', 'generated')!
	os.mkdir(out + '/sandbox-build')!
	generator := out + '/sandbox-build/security-compiler'
	args := audioinputs.sandbox_generator_arguments(root, v, host_cc, generator)!
	engine2_text(out + '/sandbox-build/generator-arguments.json', json2.encode(args) + '\n')!
	engine2_text(out + '/sandbox-build/generator-environment.json',
		json2.encode(audioinputs.sandbox_generator_environment()) + '\n')!
	e.command('sandbox-build/generator-build.log')!
	e.record('sandbox-generator', 'sandbox-build/security-compiler', 'host')!
	e.record('sandbox-generator-c', 'sandbox-build/security-compiler.c', 'generated')!
	e.command('sandbox-build/generate.log')!
	e.command('sandbox-build/build.log')!
	e.record('sandbox', 'sandbox-build/vinix-sandbox', 'target')!
	e.record('generated/sandbox-build/sandbox.c', 'sandbox-build/sandbox.c', 'generated')!
	e.v_program('tone-build', 'tone', 'tone')!
	e.v_program('guest-build', 'init', 'guest')!
	for index in 0 .. 4 {
		name := ['vinix-package', 'vinix-account', 'vinix-session', 'vinix-authd'][index]
		key := ['package-cli', 'account-cli', 'session-cli', 'authd'][index]
		e.v_program('tools/program-' + index.str(), name, key)!
	}
}

fn engine2_elf(path string) ! {
	target_elf2(path)!
}

fn (e &Engine2) headers() !map[string]bool {
	mut allowed := map[string]bool{}
	mut donor_headers := map[string]string{}
	for entry in e.donor.entries {
		if entry.root == 'capture' && entry.kind == 'file' && entry.path.ends_with('.h') {
			donor_headers[entry.path] = entry.sha256
		}
	}
	root := e.plan.state_root + '/inputs/source'
	for entry in e.source.entries {
		if entry.kind == 'file' && source_selected2(entry.path) {
			allowed[root + '/' + entry.path] = true
		}
	}
	// V emits its original absolute stdatomic/vlib header paths. Original tool
	// maps are verified independently; matching them to the donor forbids an
	// unretained header from being admitted merely because its path looks right.
	for role, entries in e.legacy.inputs {
		if role != 'tree:compiler' { continue }
		for path, value in entries {
			if !path.ends_with('.h') || !value.starts_with('file|') { continue }
			prefix := e.legacy.roots['compiler'] + '/'
			if !path.starts_with(prefix) { continue }
			relative := path[prefix.len..]
			mut donor_relative := ''
			if relative.starts_with('vlib/') { donor_relative = 'inputs/' + relative }
			if relative.starts_with('thirdparty/stdatomic/') {
				donor_relative = 'inputs/v-thirdparty/stdatomic/' + relative.all_after('thirdparty/stdatomic/')
			}
			if donor_relative == '' { continue }
			if donor_headers[donor_relative] == value.all_after_last('|') { allowed[path] = true }
		}
	}
	return allowed
}

fn (mut e Engine2) admit_targets() ! {
	out := e.plan.state_root
	for key in ['cross-probe', 'sandbox', 'tone', 'guest', 'package-cli', 'account-cli',
		'session-cli', 'authd'] {
		engine2_elf(out + '/' + e.fresh[key].path)!
	}
	allowed := e.headers()!
	for name in audioinputs.trace_files() {
		verify_trace2(os.read_file(out + '/' + name)!, out, borrow_path2(e.donor, 'sysroot')!,
			borrow_path2(e.donor, 'gcc')!, name, allowed)!
		e.record('trace/' + name, name, 'trace')!
		object := trace_object2(out, name)!
		e.record('object/' + name, object[out.len + 1..], 'object')!
	}
}

fn (mut e Engine2) root_file(relative string, text string) ! {
	path := e.plan.state_root + '/tools/root/' + relative
	engine2_text(path, text)!
	os.chmod(path, 0o644)!
}

fn (mut e Engine2) extras() ! {
	out := e.plan.state_root
	payload := out + '/inputs/payload'
	os.mkdir_all(payload + '/bin')!
	copy_new2(out + '/' + e.fresh['tone'].path, payload + '/bin/tone', e.donor)!
	os.chmod(payload + '/bin/tone', 0o755)!
	key := pkgcore.keygen(out + '/inputs/signing-seed')!
	for id in ['tone', 'noaudio'] {
		manifest := pkgcore.Package{id: id, version: '1.0.0', architecture: 'aarch64',
			name: 'Audio portal fixture', license: 'GPL-2.0-or-later', kind: 'native',
			entrypoint: 'bin/tone', permissions: if id == 'tone' { ['audio'] } else { []string{} }}
		path := out + '/inputs/' + id + '.json'
		write_new2(path, json2.encode(manifest))!
		mut packed := pkgcore.pack(path, payload, out + '/inputs/publisher')!
		packed.close()
	}
	pkgcore.publish(out + '/inputs/publisher', 'audio-fixture', out + '/inputs/signing-seed',
		1, time.now().unix() + 86400)!
	write_new2(out + '/inputs/public-key', key + '\n')!
	config := pkgcore.Config{architecture: 'aarch64', launch_user: 'sam',
		repositories: [pkgcore.Repository{id: 'audio-fixture',
			url: 'file:///usr/share/audio-publisher', public_key: key}],
		policy: pkgcore.Policy{offline: true, reserve_bytes: 0}}
	write_new2(out + '/inputs/config.json', json2.encode(config))!
	e.root_file('etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	e.root_file('etc/group', 'root:x:0:\ntty:x:5:\n')!
	e.root_file('etc/vinix/auth.conf', 'scrypt_ln = 10\n')!
	e.root_file('etc/vinix-packages/config.json', json2.encode(config))!
	for pair in [['inputs/publisher', 'usr/share/audio-publisher'],
		['inputs/source/tools/accounts/actions', 'usr/share/vinix/actions']] {
		entries := capture_owned2(out + '/' + pair[0], [], e.donor)!
		for entry in entries {
			if entry.kind != 'file' { continue }
			destination := out + '/tools/root/' + pair[1] + '/' + entry.path
			os.mkdir_all(os.dir(destination))!
			copy_new2(out + '/' + pair[0] + '/' + entry.path, destination, e.donor)!
		}
	}
	for program_role, relative in {'package-cli': 'usr/bin/vinix-package',
		'account-cli': 'usr/sbin/vinix-account', 'session-cli': 'usr/sbin/vinix-session',
		'authd': 'usr/sbin/vinix-authd', 'sandbox': 'usr/bin/vinix-sandbox'} {
		destination := out + '/tools/root/' + relative
		os.mkdir_all(os.dir(destination))!
		copy_new2(out + '/' + e.fresh[program_role].path, destination, e.donor)!
		os.chmod(destination, 0o755)!
	}
	for directory in ['run', 'home', 'var/log', 'tmp'] { os.mkdir_all(out + '/tools/root/' + directory)! }
	os.chmod(out + '/tools/root/tmp', 0o1777)!
	os.mkdir(out + '/runtime')!
	for name in ['cp', 'tar', 'mformat', 'mmd', 'mcopy', 'limine'] {
		original := e.legacy.files[name]
		if original == '' { return error('missing original runtime tool: ' + name) }
		copy_new2(original, out + '/runtime/' + name, e.donor)!
		os.chmod(out + '/runtime/' + name, 0o755)!
		e.record('runtime/' + name, 'runtime/' + name, 'host')!
	}
	e.record('public-key', 'inputs/public-key', 'metadata')!
	e.record('config', 'inputs/config.json', 'metadata')!
	engine2_text(out + '/publisher-files.json',
		json2.encode(capture_owned2(out + '/inputs/publisher', [], e.donor)!) + '\n')!
	engine2_text(out + '/extras-files.json',
		json2.encode(capture_owned2(out + '/tools/root', [], e.donor)!) + '\n')!
	e.record('publisher', 'publisher-files.json', 'metadata')!
	e.record('extras', 'extras-files.json', 'metadata')!
	// No rootfs, archive, boot image, firmware state, WAV, or run claim is
	// produced here. Their complete retained cost belongs to run admission.
}

fn (mut e Engine2) audit(label string) ! {
	out := e.plan.state_root
	root := borrow_path2(e.donor, 'kernel-evidence')!
	sha := engine2_digest(borrow_path2(e.donor, 'kernel')!)!
	audiokernel.validate(root, 'aarch64', sha)!
	os.mkdir_all(out + '/audits')!
	e.command('audits/' + label + '-owner.log')!
	e.record('kernel-audit-' + label, 'audits/' + label + '.log.checked.json', 'metadata')!
}

// An internal audit leaf admits only the just-released nativeguard child.
// Direct invocation has no matching barrier/argv and starts no checker. The
// ordinary controller copy, all paths and the complete donor are still bound
// to the reviewed Plan rather than supplied as an executable command payload.
pub fn kernel_audit_leaf2(plan_path string, plan_sha string, label string) ! {
	if label !in ['before', 'after'] { return error('invalid internal audit phase') }
	p := load_plan2(plan_path, plan_sha)!
	self := os.executable()
	if self != leaf2(p.state_root, 'inputs/controller', 'file')!
		|| os.lstat(self)!.nlink != 1 || engine2_digest(self)! != p.controller_sha256 {
		return error('internal audit requires the independent reviewed controller copy')
	}
	owner := p.state_root + '/audits/' + label + '-owner.log'
	barrier_path := owner + '.barrier.json'
	ordinary2(barrier_path, 'file')!
	if os.lstat(barrier_path)!.nlink != 1 || os.lstat(barrier_path)!.size > 4096 {
		return error('invalid internal audit owner barrier')
	}
	barrier_text := os.read_file(barrier_path)!
	barrier := json2.decode[AuditBarrier2](barrier_text, strict: true)!
	if barrier_text != json2.encode({'pid': barrier.pid, 'observed_pgid': barrier.observed_pgid,
		'parent_uid': barrier.parent_uid, 'parent_euid': barrier.parent_euid})
		|| barrier.pid != C.getpid()
		|| barrier.observed_pgid != C.getpid() || C.getpgid(0) != C.getpid()
		|| barrier.parent_uid != int(C.getuid()) || barrier.parent_euid != int(C.geteuid()) {
		return error('internal audit lacks its current nativeguard child-group barrier')
	}
	argv_path := owner + '.argv.json'
	ordinary2(argv_path, 'file')!
	if os.lstat(argv_path)!.nlink != 1 || os.lstat(argv_path)!.size > 16384
		|| os.read_file(argv_path)! != json2.encode([self, '--kernel-audit', plan_path,
			plan_sha, label]) + '\n' {
		return error('internal audit owner invocation differs')
	}
	for path in [owner + '.result.json', owner + '.cleanup.json',
		p.state_root + '/refusal2.json', p.state_root + '/preparation2.json'] {
		if os.exists(path) || os.is_link(path) { return error('internal audit phase is no longer active') }
	}
	donor := load_donor2(p, load_legacy2(p)!)!
	root := borrow_path2(donor, 'kernel-evidence')!
	sha := engine2_digest(borrow_path2(donor, 'kernel')!)!
	audiokernel.check_audit(root, 'aarch64', sha, p.state_root + '/audits/' + label + '.log')!
}

fn (mut e Engine2) build() ! {
	e.copy_source()!
	e.audit('before')!
	e.build_targets()!
	e.admit_targets()!
	e.extras()!
	e.audit('after')!
	e.remaining_ms()!
}

// Retain every original role that can be observed, even when another role is
// unavailable. A partial map is always accompanied by explicit errors.
fn engine2_legacy_actual(l LegacyPlan2) (map[string]map[string]string, []string) {
	mut actual := map[string]map[string]string{}
	mut failures := []string{}
	for role, root in l.roots {
		mut entries := map[string]string{}
		legacy2_inventory(root, role == 'source', 0, time.sys_mono_now(), mut entries) or {
			failures << 'tree:' + role + ': ' + err.msg()
		}
		actual['tree:' + role] = entries
	}
	for role, path in l.files {
		mut entries := map[string]string{}
		legacy2_inventory(path, false, 0, time.sys_mono_now(), mut entries) or {
			failures << 'file:' + role + ': ' + err.msg()
		}
		actual['file:' + role] = entries
	}
	return actual, failures
}

// Actual inventories are written before equality is decided. Expected bytes
// are never presented as an observation after an inventory or equality error.
fn (mut e Engine2) observations(label string) ! {
	out := e.plan.state_root
	mut failures := []string{}
	donor_observed := observe_roots2(e.donor.roots)
	donor_actual := donor_observed.entries
	for role, message in donor_observed.errors { failures << 'donor:' + role + ': ' + message }
	write_new2(out + '/donor-' + label + '.json',
		json2.encode(Donor2{...e.donor, entries: donor_actual}) + '\n') or { failures << err.msg() }
	if donor_observed.errors.len == 0 {
		closed_aliases2(donor_actual, false) or { failures << err.msg() }
		if donor_actual != e.donor.entries { failures << 'complete donor inventory changed' }
	}
	source_observed := observe_roots2({'source': e.source.root})
	source_actual := source_observed.entries
	for role, message in source_observed.errors { failures << 'source:' + role + ': ' + message }
	write_new2(out + '/external-source-' + label + '.json',
		json2.encode(Source2{...e.source, entries: source_actual}) + '\n') or { failures << err.msg() }
	if source_observed.errors.len == 0 {
		closed_aliases2(source_actual, true) or { failures << err.msg() }
		if source_actual != e.source.entries { failures << 'complete external source inventory changed' }
	}
	legacy_actual, legacy_errors := engine2_legacy_actual(e.legacy)
	failures << legacy_errors
	write_new2(out + '/legacy-' + label + '.json', json2.encode(legacy_actual) + '\n') or { failures << err.msg() }
	if legacy_actual != e.legacy.inputs { failures << 'complete original-tool maps changed' }
	// Preserve detached revision, qualified compiler and the original overlay
	// checks in addition to the actual full inventory observations above.
	verify_source2(e.source) or { failures << 'source identity: ' + err.msg() }
	verify_legacy_inputs2(e.legacy) or { failures << 'legacy identity: ' + err.msg() }
	write_new2(out + '/observations-' + label + '.json',
		json2.encode({'failures': failures}) + '\n') or { failures << err.msg() }
	if failures.len > 0 { return error(failures.join('\n')) }
	for prefix in ['donor-', 'external-source-', 'legacy-'] {
		e.record(prefix + label, prefix + label + '.json', 'metadata')!
	}
}

// Every independent after-observation is attempted, including on a build
// failure. Copied-source observations are separate from external source pins.
fn (mut e Engine2) postchecks() ! {
	out := e.plan.state_root
	mut failures := []string{}
	e.observations('after') or { failures << err.msg() }
	if os.is_dir(out + '/inputs/source') {
		after := capture_owned2(out + '/inputs/source', [], e.donor) or {
			failures << 'source-copy: ' + err.msg()
			[]OwnedEntry2{}
		}
		text := json2.encode(after) + '\n'
		write_new2(out + '/source-after.json', text) or { failures << err.msg() }
		before := os.read_file(out + '/source-before.json') or { failures << err.msg(); '' }
		if before != text { failures << 'fresh copied source changed' }
	}
	write_new2(out + '/postchecks.json', json2.encode({'failures': failures}) + '\n') or { failures << err.msg() }
	if failures.len > 0 { return error(failures.join('\n')) }
	e.record('source-after', 'source-after.json', 'metadata')!
}

fn (mut e Engine2) seal(plan_path string, expected_sha string) !string {
	p := e.plan
	e.record('source-manifest', 'source-manifest.json', 'metadata')!
	preparation := Preparation2{state_root: p.state_root, completed_at: time.now().unix(),
		plan_path: plan_path,
		plan_sha256: expected_sha, donor_manifest_path: p.donor_manifest_path,
		donor_manifest_sha256: p.donor_manifest_sha256, legacy_plan_path: p.legacy_plan_path,
		legacy_plan_sha256: p.legacy_plan_sha256, source_manifest_path: p.source_manifest_path,
		source_manifest_sha256: p.source_manifest_sha256, source_root: p.source_root,
		source_base_revision: p.source_base_revision, controller_sha256: p.controller_sha256,
		borrowed: e.donor.roles, fresh: e.fresh,
		scenarios: ['packages-audio-basic', 'packages-audio-lifecycle', 'packages-audio-seat'],
		extras_path: 'tools/root', tree: capture_owned2(p.state_root, ['preparation2.pending.json'], e.donor)!}
	path := p.state_root + '/preparation2.pending.json'
	e.remaining_ms()!
	write_new2(path, json2.encode(preparation) + '\n')!
	sha := engine2_digest(path)!
	return complete_candidate2(p.state_root, sha, EngineCompletion2{engine: e, path: path, sha: sha})
}

pub fn prepare2(plan_path string, expected_sha string) !string {
	started := time.sys_mono_now()
	p := load_plan2(plan_path, expected_sha)!
	legacy := load_legacy2(p)!
	donor := load_donor2(p, legacy)!
	source := load_source2(p)!
	verify_legacy_inputs2(legacy)!
	verify_source2(source)!
	verify_donor2(donor)!
	controller := os.executable()
	ordinary2(controller, 'file')!
	if !under2(os.dir(legacy.state_root), controller)
		|| engine2_digest(controller)! != p.controller_sha256 {
		return error('controller differs from reviewed format-2 Plan')
	}
	reserve := proof_reserve2(legacy, donor, source)!
	if p.receipt_reserve_bytes < reserve || p.receipt_reserve_bytes >= aggregate_cap2 {
		return error('Plan does not reserve complete after inventories and final/refusal receipts')
	}
	check_budget2(p, legacy, false)!
	nativeguard.watch_interrupts()!
	// Admission above is read only. An existing state, including a refused
	// attempt, is never reopened or overwritten.
	if os.exists(p.state_root) || os.is_link(p.state_root) { return error('state must be new') }
	os.mkdir(p.state_root)!
	mut e := Engine2{plan: p, plan_path: plan_path, plan_sha256: expected_sha,
		legacy: legacy, donor: donor, source: source, started: started}
	mut failures := []string{}
	for directory in ['inputs', 'tmp', 'modules'] {
		os.mkdir(p.state_root + '/' + directory) or { failures << err.msg() }
	}
	if failures.len == 0 {
		df := nativeguard.actual_df(p.state_root, p.state_root + '/admission-df.log') or {
			failures << err.msg()
			nativeguard.DfObservation{}
		}
		if df.available < u64(2) << 30 { failures << 'actual df below2GiB start admission' }
	}
	write_new2(p.state_root + '/source-manifest.json', json2.encode(source) + '\n') or { failures << err.msg() }
	e.observations('before') or { failures << err.msg() }
	if failures.len == 0 { e.build() or { failures << err.msg() } }
	e.postchecks() or { failures << err.msg() }
	if failures.len == 0 {
		e.remaining_ms() or { failures << err.msg() }
		usage := usage2(legacy.charged_roots) or { failures << err.msg(); Usage2{} }
		if usage.allocated > aggregate_cap2 - p.receipt_reserve_bytes
			|| usage.apparent > aggregate_cap2 - p.receipt_reserve_bytes {
			failures << 'final dual namespace endpoint reserve refused'
		}
	}
	mut sha := ''
	if failures.len == 0 {
		sha = e.seal(plan_path, expected_sha) or { failures << err.msg(); '' }
	}
	if failures.len != 0 {
		// A failure before publication leaves only pending evidence. Even if this
		// refusal write also fails, no completed preparation receipt exists.
		write_new2(p.state_root + '/refusal2.json', json2.encode(Refusal2{failures: failures}) + '\n') or {
			return error(failures.join('\n') + '\nreceipt: ' + err.msg())
		}
		return error(failures.join('\n'))
	}
	return sha
}
