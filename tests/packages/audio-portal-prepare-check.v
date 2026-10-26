// SPDX-License-Identifier: GPL-2.0-or-later
// Production-safe controls for the exact sealed-preparation tree inventory.
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.audioinputs
import tests.packages.audioprepare
import tools.packages.pkgcore

#include <sys/stat.h>
fn C.mkfifo(&char, u32) i32

struct Report {
	format   int = 1
	result   string = 'PASS'
	checker  string
	helper   string
	controller string
	preparation string
	limitation string = 'Synthetic tree and receipt validation only; no package admission, target compilation, QEMU or native audio execution.'
	controls []string
}

struct FixtureHost {
	qemu string
	firmware string
	firmware_vars string
}

struct FixturePreparation {
	format int = 1
	architecture string = 'aarch64'
	state_root string
	source_root string
	source_revision string
	sources map[string]string
	generated map[string]string
	inputs map[string]string
	artifact_paths map[string]string
	original_paths map[string]string
	scenarios []string
	extras_root string
	host FixtureHost
	environment map[string]string
	tree []audioprepare.Entry
}

fn put(path string, bytes []u8) ! {
	// Detach first: source, controller and reviewed kernel bytes may be hardlinked.
	if os.exists(path) || os.is_link(path) { os.rm(path)! }
	os.mkdir_all(os.dir(path))!
	os.write_file_array(path, bytes)!
}

fn linked(source string, target string) ! {
	audioprepare.regular(source)!
	os.mkdir_all(os.dir(target))!
	os.link(source, target)!
}

fn source_tree(root string, target string, name string, mut sources map[string]string) ! {
	path := root + '/' + name
	kind := (os.lstat(path)!).mode & 0o170000
	if kind == 0o040000 {
		for child in os.ls(path)! { source_tree(root, target, name + '/' + child, mut sources)! }
	} else if kind == 0o100000 && !name.ends_with('_test.v') {
		linked(path, target + '/' + name)!
		sources[name] = audioprepare.digest(path)!
	} else if kind != 0o100000 { return error('nonordinary fixture source: ' + path) }
}

fn input_sums(paths map[string]string) !map[string]string {
	mut sums := map[string]string{}
	for name, path in paths { sums[name] = audioprepare.digest(path)! }
	return sums
}

fn sealed(p FixturePreparation) !string {
	os.write_file(p.state_root + '/preparation.json', json2.encode(p) + '\n')!
	return audioprepare.digest(p.state_root + '/preparation.json')
}

fn resealed(p FixturePreparation) !FixturePreparation {
	inputs := input_sums(p.artifact_paths)!
	put(p.state_root + '/input-before.json', (json2.encode(inputs) + '\n').bytes())!
	updated := FixturePreparation{ ...p, inputs: inputs, tree: audioprepare.capture(p.state_root, ['preparation.json'])! }
	sealed(updated)!
	return updated
}

fn verify_cli(controller string, p FixturePreparation, expected string, log string, reason string) ! {
	mut refused := false
	hwhost.run_tool([controller, '--verify-prepared', p.state_root, '--prepared-sha256', expected],
		{'VINIX_ROOT': os.real_path(os.dir(os.dir(os.dir(@FILE))))}, log, 30) or { refused = true }
	output := os.read_file(log)!
	marker := 'AUDIO PREPARATION VERIFIED ' + expected + ' (read-only; no guest executed)'
	if reason == '' {
		if refused || !output.contains(marker) { return error('valid preparation refused: ' + output) }
	} else if !refused || !output.contains('audio-portal-runtime-check:')
		|| !output.contains(reason) || output.contains('AUDIO PREPARATION VERIFIED') {
		return error('preparation mutation did not receive expected refusal (' + reason + '): ' + output)
	}
}

fn receipt_refusal(controller string, p FixturePreparation, logs string, name string, reason string,
	mut controls []string) ! {
	verify_cli(controller, p, sealed(p)!, logs + '/' + name + '.log', reason)!
	controls << name
}

fn resume_refusal(controller string, p FixturePreparation, expected string, extra []string,
	log string, reason string) ! {
	before := audioprepare.capture(p.state_root, [])!
	mut argv := [controller, '--resume', p.state_root, '--prepared-sha256', expected]
	argv << extra
	mut refused := false
	hwhost.run_tool(argv, {'VINIX_ROOT': os.real_path(os.dir(os.dir(os.dir(@FILE))))}, log, 30) or { refused = true }
	output := os.read_file(log)!
	if !refused || !output.contains('audio-portal-runtime-check:') || !output.contains(reason)
		|| output.contains('AUDIO PREPARATION PASS') || output.contains('AUDIO PREPARATION VERIFIED')
		|| output.contains('Captured complete native evidence') {
		return error('resume did not receive expected pre-execution refusal (' + reason + '): ' + output)
	}
	for name in ['run', 'source-after.json', 'generated-after.json', 'input-after.json', 'qualification.json'] {
		if os.exists(p.state_root + '/' + name) || os.is_link(p.state_root + '/' + name) {
			return error('refused resume created runtime result: ' + name)
		}
	}
	if audioprepare.capture(p.state_root, [])! != before { return error('refused resume changed preparation') }
}

fn synthetic_preparation(out string, controller string, kernel string) !FixturePreparation {
	root := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	prep := out + '/preparation'
	os.mkdir(prep)!
	mut sources := map[string]string{}
	for name in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'tools/sandbox',
		'build-support/native-compat-tools/compathost', 'tests/qemu-core/fixturehost', 'tests/native-guest-tools/guesthost',
		'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy', 'tests/host-policy/policyhost',
		'tests/hardware-platform/hwhost', 'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone',
		'tests/packages/audiotest', 'tests/packages/audioinputs', 'tests/packages/audioprepare'] {
		source_tree(root, prep + '/inputs/source', name, mut sources)!
	}
	for name in ['tests/packages/audio-portal-runtime-check.v', 'tests/packages/audio-portal-retain.v',
		'tests/packages/audio-portal-evidence-check.v', 'tests/packages/audio-portal-wave-check.v',
		'build-support/native-compat-tools/main.v', 'build-support/security-tools/compile-v-core',
		'build-support/run-v-tool.sh', 'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v',
		'tests/packages/audio-input-check.v', 'tests/packages/audio-cross-probe.v',
		'tests/packages/audio-portal-prepare-check.v', 'build-support/limine.conf'] {
		linked(root + '/' + name, prep + '/inputs/source/' + name)!
		sources[name] = audioprepare.digest(root + '/' + name)!
	}
	mut paths := map[string]string{}
	mut elf := []u8{len: 64}
	for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { elf[i] = byte }
	elf[16] = 2
	elf[18] = 183
	for name, relative in {
		'guest': 'guest-build/init', 'tone': 'tone-build/tone', 'sandbox': 'sandbox-build/vinix-sandbox',
		'package-cli': 'tools/program-0/vinix-package', 'account-cli': 'tools/program-1/vinix-account',
		'session-cli': 'tools/program-2/vinix-session', 'authd': 'tools/program-3/vinix-authd',
		'cross-probe': 'cross-probe', 'qemu': 'inputs/qemu', 'firmware': 'inputs/firmware',
		'firmware-vars': 'inputs/firmware-vars', 'v': 'inputs/v', 'clang': 'inputs/clang',
		'cross-backend': 'inputs/cross-backend', 'cross-cc1': 'inputs/cross-cc1',
		'cross-collect2': 'inputs/cross-collect2', 'cross-as': 'inputs/cross-as',
		'cross-ld': 'inputs/cross-ld', 'cross-lto-wrapper': 'inputs/cross-lto-wrapper',
		'cross-lto-plugin': 'inputs/cross-lto-plugin', 'adapter-host-cc': 'inputs/adapter-host-cc'
	} {
		paths[name] = prep + '/' + relative
		put(paths[name], elf)!
	}
	paths['controller'] = prep + '/inputs/controller'
	linked(controller, paths['controller'])!
	paths['kernel-seal'] = prep + '/inputs/kernel-evidence/kernel-seal.json'
	linked(kernel + '/kernel-seal.json', paths['kernel-seal'])!
	paths['kernel'] = prep + '/inputs/kernel'
	linked(kernel + '/kernel-aarch64/bin/vinix', paths['kernel'])!
	linked(kernel + '/kernel-aarch64/bin/vinix', prep + '/inputs/kernel-evidence/kernel-aarch64/bin/vinix')!
	if audioprepare.digest(paths['kernel-seal'])! != '839ad75dd1ec376a8cae4e75dc1cfbddc913406dc3e136e8d4f4a412657f9b73' {
		return error('fixture requires the actual reviewed kernel seal')
	}
	for name in ['cp', 'tar', 'mformat', 'mmd', 'mcopy'] {
		paths['runtime/' + name] = prep + '/runtime-bin/' + name
		put(paths['runtime/' + name], 'SYNTHETIC NONEXECUTED RUNTIME INPUT\n'.bytes())!
		os.chmod(paths['runtime/' + name], 0o755)!
	}
	paths['runtime/BOOTAA64.EFI'] = prep + '/inputs/runtime/BOOTAA64.EFI'
	put(paths['runtime/BOOTAA64.EFI'], 'SYNTHETIC NONEXECUTED LOADER\n'.bytes())!
	mut generated := map[string]string{}
	for name in ['guest-build/init.c', 'tone-build/tone.c', 'tools/program-0/vinix-package.c',
		'tools/program-1/vinix-account.c', 'tools/program-2/vinix-session.c', 'tools/program-3/vinix-authd.c'] {
		put(prep + '/' + name, 'SYNTHETIC NONEXECUTED GENERATED C\n'.bytes())!
		generated[name] = audioprepare.digest(prep + '/' + name)!
	}
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { put(prep + '/inputs/cross-sysroot/lib/' + name, 'SYNTHETIC\n'.bytes())! }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { put(prep + '/inputs/cross-gcc/' + name, 'SYNTHETIC\n'.bytes())! }
	put(prep + '/inputs/cross-sysroot/include/stdint.h', 'SYNTHETIC\n'.bytes())!
	mut trace := '#include <...> search starts here:\n'
	for name in ['cross-gcc/include', 'cross-gcc/include-fixed', 'cross-sysroot/include'] { trace += ' ' + prep + '/inputs/' + name + '\n' }
	trace += 'End of search list.\n. ' + prep + '/inputs/cross-sysroot/include/stdint.h\n'
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { trace += prep + '/inputs/cross-sysroot/lib/' + name + '\n' }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { trace += prep + '/inputs/cross-gcc/' + name + '\n' }
	for name in audioinputs.trace_files() {
		object := audioinputs.trace_object(prep, name)!
		put(object, 'SYNTHETIC GENERATED OBJECT\n'.bytes())!
		put(prep + '/' + name, (trace + object + '\n').bytes())!
		paths['trace/' + name] = prep + '/' + name
		paths['trace-object/' + name] = object
	}
	key := '0'.repeat(64)
	config := json2.encode(pkgcore.Config{architecture: 'aarch64', launch_user: 'sam',
		repositories: [pkgcore.Repository{id: 'audio-fixture', url: 'file:///usr/share/audio-publisher', public_key: key}],
		policy: pkgcore.Policy{offline: true, reserve_bytes: 0}})
	put(prep + '/inputs/config.json', config.bytes())!
	put(prep + '/inputs/public-key', (key + '\n').bytes())!
	put(prep + '/inputs/publisher/SYNTHETIC', 'NO SIGNED PACKAGE OR NATIVE EXECUTION CLAIMED\n'.bytes())!
	extras := prep + '/tools/root'
	mut root_files := {
		'etc/passwd': 'root:x:0:0:root:/root:/bin/sh\n', 'etc/group': 'root:x:0:\ntty:x:5:\n',
		'etc/vinix/auth.conf': 'scrypt_ln = 10\n', 'etc/vinix-packages/config.json': config,
		'usr/share/audio-publisher/SYNTHETIC': 'NO SIGNED PACKAGE OR NATIVE EXECUTION CLAIMED\n'
	}
	for entry in audioprepare.capture(root + '/tools/accounts/actions', [])! {
		if entry.kind == 'file' { root_files['usr/share/vinix/actions/' + entry.path] = os.read_file(root + '/tools/accounts/actions/' + entry.path)! }
	}
	for name, text in root_files { put(extras + '/' + name, text.bytes())!; os.chmod(extras + '/' + name, 0o644)! }
	for key_name, name in {'package-cli': 'usr/bin/vinix-package', 'account-cli': 'usr/sbin/vinix-account',
		'session-cli': 'usr/sbin/vinix-session', 'authd': 'usr/sbin/vinix-authd', 'sandbox': 'usr/bin/vinix-sandbox'} {
		put(extras + '/' + name, os.read_bytes(paths[key_name])!)!
		os.chmod(extras + '/' + name, 0o755)!
	}
	for name in ['run', 'home', 'var/log', 'tmp'] { os.mkdir_all(extras + '/' + name)! }
	for entry in audioprepare.capture(extras, [])! {
		if entry.kind == 'directory' { os.chmod(if entry.path == '' { extras } else { extras + '/' + entry.path }, if entry.path == 'tmp' { 0o1777 } else { 0o755 })! }
	}
	hwhost.run_tool(['git', '-C', root, 'rev-parse', 'HEAD'], {}, out + '/revision.log', 30)!
	revision := os.read_file(out + '/revision.log')!.trim_space()
	put(prep + '/repository-head.log', (revision + '\n').bytes())!
	put(prep + '/production.diff', 'SYNTHETIC CHECKPOINT, NOT NATIVE QUALIFICATION\n'.bytes())!
	paths['source-revision'] = prep + '/repository-head.log'
	paths['source-patch'] = prep + '/production.diff'
	put(prep + '/source-before.json', (json2.encode(sources) + '\n').bytes())!
	put(prep + '/generated-before.json', (json2.encode(generated) + '\n').bytes())!
	paths['input-origins'] = prep + '/original-input-paths.json'
	mut origins := map[string]string{}
	for name in ['kernel', 'v', 'qemu', 'firmware', 'firmware-vars', 'controller', 'clang',
		'cross-backend', 'cross-cc1', 'cross-collect2', 'cross-as', 'cross-ld', 'cross-lto-wrapper',
		'cross-lto-plugin', 'adapter-host-cc', 'runtime/BOOTAA64.EFI',
		'runtime/cp', 'runtime/tar', 'runtime/mformat', 'runtime/mmd', 'runtime/mcopy'] {
		origins[name] = if name == 'controller' { controller } else { paths[name] }
	}
	put(prep + '/original-input-paths.json', (json2.encode(origins) + '\n').bytes())!
	return resealed(FixturePreparation{
		state_root: prep, source_root: root, source_revision: revision, sources: sources, generated: generated,
		artifact_paths: paths, original_paths: origins, scenarios: ['packages-audio-basic'], extras_root: extras,
		host: FixtureHost{qemu: paths['qemu'], firmware: paths['firmware'], firmware_vars: paths['firmware-vars']},
		environment: {'PATH': prep + '/runtime-bin', 'VINIX_LIMINE_BOOTAA64': paths['runtime/BOOTAA64.EFI'], 'VINIX_HWTEST_TCG': '1'}
	})
}

fn controller_controls(out string, controller string, kernel string, mut controls []string) !string {
	audioprepare.regular(controller)!
	if !os.is_abs_path(controller) || os.real_path(controller) != controller
		|| !os.is_abs_path(kernel) || os.real_path(kernel) != kernel { return error('controller/kernel fixture paths must be canonical absolute') }
	base := synthetic_preparation(out, controller, kernel)!
	logs := out + '/controller-logs'
	os.mkdir(logs)!
	sha := sealed(base)!
	before := audioprepare.capture(base.state_root, [])!
	verify_cli(controller, base, sha, logs + '/valid.log', '')!
	if audioprepare.capture(base.state_root, [])! != before { return error('read-only controller verification changed preparation') }
	for name in ['run', 'source-after.json', 'generated-after.json', 'input-after.json', 'qualification.json'] {
		if os.exists(base.state_root + '/' + name) || os.is_link(base.state_root + '/' + name) { return error('verification created runtime result: ' + name) }
	}
	controls << 'controller-real-readonly-verification-no-runtime-results'
	verify_cli(controller, base, '0'.repeat(64), logs + '/wrong-checkpoint.log', 'receipt digest differs')!
	controls << 'controller-wrong-reviewed-digest-refused'
	resume_refusal(controller, base, '0'.repeat(64), [], logs + '/resume-wrong-checkpoint.log', 'receipt digest differs')!
	controls << 'resume-wrong-reviewed-digest-refused-before-claim'
	resume_refusal(controller, base, sha, ['--arch', 'x86_64'], logs + '/resume-override.log', 'no overrides')!
	controls << 'resume-argument-override-refused-before-claim'
	receipt_refusal(controller, FixturePreparation{ ...base, format: 2 }, logs, 'controller-resealed-format-refused', 'identity', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, architecture: 'x86_64' }, logs, 'controller-resealed-architecture-refused', 'identity', mut controls)!
	os.write_file(base.state_root + '/preparation.json', json2.encode(FixturePreparation{ ...base, state_root: out }) + '\n')!
	verify_cli(controller, base, audioprepare.digest(base.state_root + '/preparation.json')!,
		logs + '/controller-resealed-state-root-refused.log', 'identity')!
	controls << 'controller-resealed-state-root-refused'
	receipt_refusal(controller, FixturePreparation{ ...base, source_root: out }, logs, 'controller-resealed-source-root-refused', 'identity', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, scenarios: [] }, logs, 'controller-resealed-empty-scenarios-refused', 'identity', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, scenarios: ['unknown'] }, logs, 'controller-resealed-scenario-refused', 'unknown or duplicate', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, scenarios: ['packages-audio-basic', 'packages-audio-basic'] }, logs, 'controller-resealed-duplicate-scenario-refused', 'unknown or duplicate', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, scenarios: ['packages-audio-seat', 'packages-audio-basic'] }, logs, 'controller-resealed-reordered-scenarios-refused', 'identity', mut controls)!
	mut sources := base.sources.clone()
	sources['tests/packages/audio-portal-runtime-check.v'] = '0'.repeat(64)
	receipt_refusal(controller, FixturePreparation{ ...base, sources: sources }, logs, 'controller-resealed-source-digest-refused', 'source closure differs', mut controls)!
	mut inputs := base.inputs.clone()
	inputs['controller'] = '0'.repeat(64)
	receipt_refusal(controller, FixturePreparation{ ...base, inputs: inputs }, logs, 'controller-resealed-input-digest-refused', 'maps differ', mut controls)!
	mut paths := base.artifact_paths.clone()
	paths.delete('guest')
	receipt_refusal(controller, FixturePreparation{ ...base, artifact_paths: paths }, logs, 'controller-resealed-missing-artifact-refused', 'maps differ', mut controls)!
	paths = base.artifact_paths.clone()
	paths['guest'] = paths['tone']
	receipt_refusal(controller, FixturePreparation{ ...base, artifact_paths: paths }, logs, 'controller-resealed-artifact-alias-refused', 'artifact location differs', mut controls)!
	paths = base.artifact_paths.clone()
	paths['trace-object/cross-search.log'] = audioinputs.trace_object(base.state_root, 'tone-build/build.log')!
	receipt_refusal(controller, FixturePreparation{ ...base, artifact_paths: paths }, logs, 'controller-resealed-object-alias-refused', 'trace/object binding differs', mut controls)!
	mut generated := base.generated.clone()
	generated['guest-build/init.c'] = '0'.repeat(64)
	receipt_refusal(controller, FixturePreparation{ ...base, generated: generated }, logs, 'controller-resealed-generated-map-refused', 'maps differ', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, extras_root: base.state_root + '/inputs' }, logs, 'controller-resealed-extras-root-refused', 'extras root', mut controls)!
	receipt_refusal(controller, FixturePreparation{ ...base, host: FixtureHost{ ...base.host, qemu: controller } }, logs, 'controller-resealed-runtime-host-refused', 'runtime binding', mut controls)!
	mut environment := base.environment.clone()
	environment['PATH'] = '/usr/bin'
	receipt_refusal(controller, FixturePreparation{ ...base, environment: environment }, logs, 'controller-resealed-runtime-path-refused', 'runtime binding', mut controls)!
	paths = base.artifact_paths.clone()
	paths['kernel'] = paths['guest']
	receipt_refusal(controller, resealed(FixturePreparation{ ...base, artifact_paths: paths })!, logs,
		'controller-resealed-kernel-alias-refused', 'kernel differs', mut controls)!
	mut origins := base.original_paths.clone()
	origins.delete('cross-backend')
	put(base.state_root + '/original-input-paths.json', (json2.encode(origins) + '\n').bytes())!
	receipt_refusal(controller, resealed(FixturePreparation{ ...base, original_paths: origins })!, logs,
		'controller-resealed-required-original-omitted-refused', 'missing prepared original', mut controls)!
	put(base.state_root + '/original-input-paths.json', (json2.encode(base.original_paths) + '\n').bytes())!
	resealed(base)!
	external_v := out + '/external-v'
	put(external_v, os.read_bytes(base.artifact_paths['v'])!)!
	origins = base.original_paths.clone()
	origins['v'] = external_v
	put(base.state_root + '/original-input-paths.json', (json2.encode(origins) + '\n').bytes())!
	external_base := resealed(FixturePreparation{ ...base, original_paths: origins })!
	external_sha := sealed(external_base)!
	verify_cli(controller, external_base, external_sha, logs + '/external-original-valid.log', '')!
	put(external_v, 'SYNTHETIC ORIGINAL CHANGED AFTER PREPARATION\n'.bytes())!
	resume_refusal(controller, external_base, external_sha, [], logs + '/resume-changed-original.log',
		'external original changed before resume: v')!
	controls << 'resume-changed-external-original-refused-before-claim'
	put(base.state_root + '/original-input-paths.json', (json2.encode(base.original_paths) + '\n').bytes())!
	resealed(base)!
	for name in ['run', 'source-after.json', 'generated-after.json', 'input-after.json', 'qualification.json'] {
		path := base.state_root + '/' + name
		if name == 'run' { os.mkdir(path)! } else { put(path, 'SYNTHETIC PREEXISTING EXECUTION RESULT\n'.bytes())! }
		receipt_refusal(controller, resealed(base)!, logs, 'controller-resealed-runtime-result-' + name + '-refused',
			'already contains execution result', mut controls)!
		if name == 'run' { os.rmdir(path)! } else { os.rm(path)! }
		resealed(base)!
	}
	put(base.state_root + '/unexpected', 'UNLISTED\n'.bytes())!
	receipt_refusal(controller, base, logs, 'controller-unsealed-extra-file-refused', 'tree differs', mut controls)!
	os.rm(base.state_root + '/unexpected')!
	os.mkdir(base.state_root + '/unexpected-empty')!
	receipt_refusal(controller, base, logs, 'controller-unsealed-extra-empty-directory-refused', 'tree differs', mut controls)!
	os.rmdir(base.state_root + '/unexpected-empty')!
	os.mv(base.artifact_paths['guest'], out + '/detached-guest')!
	receipt_refusal(controller, base, logs, 'controller-unsealed-missing-file-refused', 'tree differs', mut controls)!
	os.mv(out + '/detached-guest', base.artifact_paths['guest'])!
	// Restore the baseline receipt before mutating files; detach all replacements.
	sealed(base)!
	for name, reason in {
		'tools/root/etc/passwd': 'prepared root file differs'
		'runtime-bin/cp': 'runtime executable differs'
		'inputs/controller': 'controller or reviewed kernel seal differs'
		'inputs/kernel-evidence/kernel-seal.json': 'controller or reviewed kernel seal differs'
		'cross-search.log': 'uncaptured selected target link input'
		'cross-probe.o': 'maps differ'
	} {
		path := base.state_root + '/' + name
		bytes := os.read_bytes(path)!
		mode := (os.lstat(path)!).mode & 0o7777
		if name == 'runtime-bin/cp' { os.chmod(path, 0o644)! }
		else if name == 'cross-search.log' { put(path, (bytes.bytestr() + '/original/foreign.a\n').bytes())! }
		else { put(path, 'SYNTHETIC MUTATED INPUT\n'.bytes())! }
		// Reseal the tree and input map so semantic checks, not stale hashes, refuse.
		mut mutated := resealed(base)!
		if name == 'cross-probe.o' {
			// A detached object mutation is byte-integrity protected; no compiler
			// provenance can be inferred from arbitrary resealed synthetic bytes.
			mutated = FixturePreparation{ ...mutated, inputs: base.inputs }
		}
		receipt_refusal(controller, mutated, logs, 'controller-file-' + name.replace('/', '-') + '-refused', reason, mut controls)!
		put(path, bytes)!
		os.chmod(path, int(mode))!
		resealed(base)!
	}
	sealed(base)!
	verify_cli(controller, base, sha, logs + '/restored.log', '')!
	if audioprepare.capture(base.state_root, [])! != before { return error('controller controls failed to restore exact baseline') }
	controls << 'controller-exact-baseline-restored-and-reverified'
	return sha
}

fn refuse(root string, entries []audioprepare.Entry, ignored []string) ! {
	audioprepare.verify(root, entries, ignored) or { return }
	return error('accepted invalid preparation inventory')
}

fn refuse_capture(root string, ignored []string) ! {
	audioprepare.capture(root, ignored) or { return }
	return error('accepted invalid preparation tree: ' + root)
}

fn changed(entries []audioprepare.Entry, path string, replacement audioprepare.Entry) ![]audioprepare.Entry {
	mut result := entries.clone()
	for i, entry in result {
		if entry.path == path { result[i] = replacement; return result }
	}
	return error('checker fixture entry is absent: ' + path)
}

fn run(out string, controller string, kernel string) ! {
	if !os.is_abs_path(out) || os.exists(out) || os.is_link(out) {
		return error('requires a NEW absolute output directory')
	}
	parent := os.dir(out)
	if parent != os.real_path(parent) || (os.lstat(parent)!).mode & 0o170000 != 0o040000
		|| out != os.join_path(parent, os.base(out)) || os.base(out) in ['', '.', '..'] {
		return error('output requires an existing canonical ordinary parent directory')
	}
	os.mkdir_all(out)!
	if os.real_path(out) != out { return error('output directory must be canonical') }
	root := out + '/tree'
	os.mkdir_all(root + '/nested/empty')!
	os.mkdir_all(root + '/tmp')!
	os.chmod(root, 0o750)!
	os.chmod(root + '/tmp', 0o1777)!
	os.write_file(root + '/artifact', 'fixture\n')!
	os.chmod(root + '/artifact', 0o640)!
	os.write_file(root + '/nested/data', 'retained\n')!
	// Exercise several streaming reads, including a final partial buffer.
	large := []u8{len: 2 * 64 * 1024 + 3, init: u8(index % 251)}
	os.write_file_array(root + '/stream', large)!
	if audioprepare.digest(root + '/stream')! != sha256.sum(large).hex() {
		return error('streaming digest differs from whole-byte oracle')
	}
	mut controls := ['streaming-digest-multiple-buffers']
	baseline := audioprepare.capture(root, [])!
	if baseline.len != 7 || baseline[0].path != '' || baseline[0].mode != 0o750 {
		return error('fixture inventory misses root, files or empty directories')
	}
	before := audioprepare.capture(out, [])!
	audioprepare.verify(root, baseline, [])!
	if audioprepare.capture(out, [])! != before { return error('valid verification wrote to its tree') }
	controls << 'valid-exact-tree-verification-without-writes'
	os.rm(root + '/artifact')!
	refuse(root, baseline, [])!
	controls << 'missing-file-refused'
	os.mkdir(root + '/artifact')!
	refuse(root, baseline, [])!
	controls << 'file-replaced-by-directory-refused'
	os.rmdir(root + '/artifact')!
	os.write_file(root + '/artifact', 'fixture\n')!
	os.chmod(root + '/artifact', 0o640)!
	os.write_file(root + '/extra', 'extra\n')!
	refuse(root, baseline, [])!
	controls << 'extra-file-refused'
	os.rm(root + '/extra')!
	os.mkdir(root + '/extra-empty')!
	refuse(root, baseline, [])!
	controls << 'extra-empty-directory-refused'
	os.rmdir(root + '/extra-empty')!
	os.rmdir(root + '/nested/empty')!
	refuse(root, baseline, [])!
	controls << 'missing-empty-directory-refused'
	os.mkdir(root + '/nested/empty')!
	os.chmod(root + '/artifact', 0o600)!
	refuse(root, baseline, [])!
	controls << 'file-mode-change-refused'
	os.chmod(root + '/artifact', 0o640)!
	os.chmod(root + '/tmp', 0o755)!
	refuse(root, baseline, [])!
	controls << 'sticky-directory-mode-change-refused'
	os.chmod(root + '/tmp', 0o1777)!
	os.chmod(root, 0o700)!
	refuse(root, baseline, [])!
	controls << 'root-mode-change-refused'
	os.chmod(root, 0o750)!
	os.write_file(root + '/artifact', 'changed\n')!
	refuse(root, baseline, [])!
	controls << 'same-length-content-change-refused'
	os.write_file(root + '/artifact', 'fixture\n')!
	os.symlink('artifact', root + '/link')!
	refuse_capture(root, [])!
	controls << 'file-symlink-refused'
	os.rm(root + '/link')!
	os.symlink('nested', root + '/link')!
	refuse_capture(root, [])!
	controls << 'directory-symlink-refused'
	os.rm(root + '/link')!
	os.symlink('tree', out + '/root-link')!
	refuse_capture(out + '/root-link', [])!
	controls << 'symlink-root-refused'
	refuse_capture(root + '/.', [])!
	controls << 'noncanonical-root-refused'
	refuse_capture('relative-root', [])!
	controls << 'relative-root-refused'
	refuse_capture(out + '/missing-root', [])!
	controls << 'missing-root-refused'
	refuse_capture(root + '/artifact', [])!
	controls << 'regular-file-root-refused'
	if C.mkfifo((root + '/fifo').str, 0o600) != 0 { return error('cannot create FIFO control') }
	refuse_capture(root, [])!
	controls << 'special-file-refused-without-opening'
	os.rm(root + '/fifo')!
	os.write_file(root + '/bad\nname', 'bad name\n')!
	refuse_capture(root, [])!
	controls << 'control-character-filename-refused'
	os.rm(root + '/bad\nname')!
	audioprepare.verify(root, baseline, [])!
	controls << 'restored-fixture-verifies-after-tree-mutations'
	for path in ['../escape', '/absolute', 'nested//data', 'nested/./data', 'nested/../data',
		'nested/data/', 'nested\\data', 'nul\x00name'] {
		entries := changed(baseline, 'artifact', audioprepare.Entry{
			path: path, kind: 'file', mode: 0o640, sha256: sha256.sum('fixture\n'.bytes()).hex()
		})!
		refuse(root, entries, [])!
		controls << 'malformed-expected-path-' + controls.len.str() + '-refused'
	}
	mut duplicate := baseline.clone()
	duplicate << baseline[baseline.len - 1]
	refuse(root, duplicate, [])!
	controls << 'duplicate-expected-path-refused'
	mut unsorted := baseline.clone()
	unsorted[1] = baseline[2]
	unsorted[2] = baseline[1]
	refuse(root, unsorted, [])!
	controls << 'unsorted-expected-paths-refused'
	refuse(root, [], [])!
	controls << 'missing-root-entry-refused'
	refuse(root, baseline.filter(it.path != 'nested'), [])!
	controls << 'missing-expected-parent-refused'
	for hash in ['0'.repeat(64), 'A'.repeat(64), 'bad'] {
		refuse(root, changed(baseline, 'artifact', audioprepare.Entry{
			path: 'artifact', kind: 'file', mode: 0o640, sha256: hash
		})!, [])!
		controls << 'wrong-or-malformed-expected-hash-' + controls.len.str() + '-refused'
	}
	refuse(root, changed(baseline, 'artifact', audioprepare.Entry{
		path: 'artifact', kind: 'symlink', mode: 0o640
	})!, [])!
	controls << 'invalid-expected-kind-refused'
	refuse(root, changed(baseline, 'artifact', audioprepare.Entry{
		path: 'artifact', kind: 'file', mode: 0o100640, sha256: sha256.sum('fixture\n'.bytes()).hex()
	})!, [])!
	controls << 'invalid-expected-mode-bits-refused'
	refuse(root, changed(baseline, 'nested', audioprepare.Entry{
		path: 'nested', kind: 'directory', mode: 0o755, sha256: '0'.repeat(64)
	})!, [])!
	controls << 'unexpected-directory-hash-refused'
	for ignored in [['../escape'], ['/absolute'], [''], ['nested', 'nested']] {
		refuse_capture(root, ignored)!
		controls << 'malformed-ignore-' + controls.len.str() + '-refused'
	}
	os.mkdir(root + '/skip')!
	os.write_file(root + '/skip/private', 'ignored\n')!
	os.write_file(root + '/skip-more', 'included\n')!
	os.write_file(root + '/skipfile', 'included too\n')!
	ignored := ['skip', 'receipt.json']
	filtered := audioprepare.capture(root, ignored)!
	os.write_file(root + '/skip/private', 'ignored mutation\n')!
	os.write_file(root + '/receipt.json', 'ignored exact receipt\n')!
	audioprepare.verify(root, filtered, ignored)!
	controls << 'exact-ignore-subtree-and-missing-receipt-name'
	os.write_file(root + '/skip-more', 'changed included\n')!
	refuse(root, filtered, ignored)!
	controls << 'ignored-name-hyphen-boundary-retained'
	os.write_file(root + '/skip-more', 'included\n')!
	os.write_file(root + '/skipfile', 'changed included too\n')!
	refuse(root, filtered, ignored)!
	controls << 'ignored-name-prefix-boundary-retained'
	os.write_file(root + '/skipfile', 'included too\n')!
	audioprepare.verify(root, filtered, ignored)!
	controls << 'restored-ignore-boundary-fixture-verifies'
	refuse(root, filtered, ['skip', 'receipt.json', 'artifact'])!
	controls << 'expected-entry-within-ignored-subtree-refused'
	mut regular_refused := false
	audioprepare.regular(out + '/root-link') or { regular_refused = true }
	if !regular_refused { return error('regular helper accepted a symbolic link') }
	controls << 'regular-file-helper-refuses-symlink'
	preparation := if controller == '' { '' } else { controller_controls(out, controller, kernel, mut controls)! }
	os.write_file(out + '/result.json', json2.encode(Report{
		checker: audioprepare.digest(@FILE)!
		helper: sha256.sum($embed_file('audioprepare/prepare.v').to_string().bytes()).hex()
		controller: if controller == '' { '' } else { audioprepare.digest(controller)! }
		preparation: preparation
		controls: controls
	}) + '\n')!
	println('AUDIO PREPARATION TREE PASS controls=' + controls.len.str())
}

fn main() {
	mut values := map[string]string{}
	for argument in os.args[1..] {
		key := argument.all_before('=')
		if !argument.contains('=') || key !in ['--out', '--controller', '--kernel-evidence'] || key in values {
			eprintln('use --out=NEW_ABSOLUTE_DIRECTORY [--controller=ABS --kernel-evidence=ABS]')
			exit(1)
		}
		values[key] = argument.all_after('=')
	}
	if values['--out'] == '' || (values['--controller'] == '') != (values['--kernel-evidence'] == '') {
		eprintln('requires --out and optional paired --controller/--kernel-evidence')
		exit(1)
	}
	run(values['--out'], values['--controller'], values['--kernel-evidence']) or { eprintln(err); exit(1) }
}
