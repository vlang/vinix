// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import json2
import os
import time
import tools.development.devcore
import tools.development.sourcecore
import tools.packages.pkgcore
import crypto.ed25519
import encoding.hex
import tests.development.referencecore
import tests.development.cicore

struct Pin {
	path   string
	sha256 string
}

struct Job {
	id               string = 'fixture'
	executable       Pin
	arguments        []string
	expand_attempt bool
	directory        string            = '/home/developer'
	interval_seconds int               = 3600
	timeout_seconds  int               = 10
	environment      map[string]string = {
		'VINIX_DEVELOPMENT_PAYLOAD': '1'
	}
	credential_files map[string]string
}

struct Plan {
	schema int = 1
	uid    int = 1000
	jobs   []Job
}

struct Stage {
	schema       int
	architecture string
	complete     bool
	binaries     map[string]string
}

struct BuildStep {
	name      string   = 'payload'
	argv      []string = ['{payload}']
	directory string   = '.'
	artifacts []string = ['artifact.txt']
}

struct BuildPlan {
	schema          int = 1
	source          Pin
	inputs          []Pin
	tools           map[string]Pin
	epoch           i64               = 1700000000
	timeout_seconds int               = 10
	environment     map[string]string = {
		'VINIX_DEVELOPMENT_PAYLOAD': 'build'
	}
	steps           []BuildStep = [BuildStep{}]
}

struct NativeStep {
	name      string
	argv      []string
	exit_code int
	artifacts map[string]string
	detail    string
}

struct NativeBuild {
	schema int
	plan_sha256 string
	source   Pin
	inputs   []Pin
	tools    map[string]Pin
	complete bool
	uid      int
	kernel   string
	epoch    i64
	steps    []NativeStep
}

struct NativeCommand {
	argv              []string
	executable_sha256 string
	exit_code         int
}

struct Profile {
	profile  string
	status   string
	commands []NativeCommand
}

struct NativeQualification {
	schema              int
	kernel              string
	architecture        string
	runner_sha256       string
	complete            bool
	all_selected_passed bool
	uid                 int
	context             string
	requested           []string
	results             []Profile
	command_timeout_seconds int
}

struct NativeJobState {
	in_flight bool
	next_due i64
	started i64
	finished i64
	exit_code int
	detail string
	runs u64
	attempts u64
}

struct NativeSchedule {
	schema int
	uid int
	plan_sha256 string
	jobs map[string]NativeJobState
}

struct Receipt {
	schema          int = 1
	arch            string
	uid             int = 1000
	kernel_sha256   string
	fixture_sha256  string
	sdk_sha256      string
	v_root_sha256   string
	v_smoke_root_sha256 string
	selfhost_v bool
	reference_sdk_sha256 string
	reference_runtime_sha256 string
	reference_profiles []string
	reference_jit bool
	reference_ci bool
	reference_tools map[string]Pin
	native_source_sha256 string
	native_source_revision string
	tools           map[string]string
	command         []string
	native_receipts map[string]string
	passed          bool
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn build_source(path string) bool {
	return (path.ends_with('.v') && !path.ends_with('_test.v')) || path.ends_with('.h') || path.ends_with('/v.mod')
}

struct PackageProof {
	signature string
	object_sha256 string
	object_bytes u64
}

// Materialize a prepared native SDK while preserving relative links and
// recording precisely the copied closure. GDB's unused Python helpers are
// excluded before copying; no Python source is written or executed.
fn copy_sdk(source string, target string, base string, relative string, mut hash sha256.Digest) ! {
	if source.ends_with('.py') || source.ends_with('.pyc') || source.ends_with('.pyo') { return }
	st := os.lstat(source)!
	mode := if st.get_filetype() == .symbolic_link { u32(0o777) } else { st.mode & 0o777 }
	hash.write('${relative.len}:${relative}:${mode}:'.bytes())!
	match st.get_filetype() {
		.directory {
			os.mkdir(target, mode: 0o700)!
			hash.write('directory\n'.bytes())!
			mut children := os.ls(source)!
			children.sort()
			for name in children {
				copy_sdk(source + '/' + name, target + '/' + name, base, relative + '/' + name, mut hash)!
			}
			os.chmod(target, int(mode))!
		}
		.regular {
			os.cp(source, target)!
			os.chmod(target, int(mode))!
			copied := digest(target)!
			if digest(source)! != copied { return error('SDK input changed during copy') }
			hash.write(('file:' + copied + '\n').bytes())!
		}
		.symbolic_link {
			mut link := os.readlink(source)!
			if link.starts_with('/') {
				if link != '/lib/libc.so' {
					return error('unsupported absolute SDK link: ' + source)
				}
				// Make the musl loader portable and pin-able as part of the
				// copied SDK closure, rather than resolving a host /lib path.
				if os.lstat(os.dir(source) + '/libc.so')!.get_filetype() != .regular {
					return error('absolute musl loader needs an adjacent regular libc.so')
				}
				link = 'libc.so'
			} else {
				if !os.exists(source) { return error('dangling SDK link: ' + source) }
				resolved := os.real_path(source)
				if resolved != base && !resolved.starts_with(base + '/') {
					return error('SDK link escapes input closure: ' + source)
				}
			}
			os.symlink(link, target)!
			hash.write(('link:' + link + '\n').bytes())!
		}
		else { return error('unsupported SDK file type') }
	}
}

fn run() !int {
	if os.args.len !in [5, 6, 8] {
		return error('usage: run-guest aarch64|x86_64 KERNEL-DIR STAGED-TOOLS NEW-STATE [PREPARED-NATIVE-GCC-SDK [NATIVE-V-ROOT NATIVE-BUSYBOX]]')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	reference := referencecore.options(os.getenv('VINIX_DEVELOPMENT_REFERENCE_SDK'),
		os.getenv('VINIX_DEVELOPMENT_REFERENCE_PROFILES'), arch)!
	jit_value := os.getenv('VINIX_DEVELOPMENT_REFERENCE_JIT')
	if jit_value !in ['', '0', '1'] { return error('VINIX_DEVELOPMENT_REFERENCE_JIT must be 0 or 1') }
	reference_jit := jit_value == '1'
	reference_ci := cicore.options(os.getenv('VINIX_DEVELOPMENT_REFERENCE_CI'), reference.profiles)!
	if reference_jit && reference.profiles != ['java'] { return error('reference JIT mode requires only the prepared Java profile') }
	if reference.root != '' && os.args.len != 5 {
		return error('reference SDK mode uses only the base arguments; prepare one complete reference SDK instead of mixing runtimes')
	}
	selfhost_option := os.getenv('VINIX_DEVELOPMENT_SELFHOST_V')
	if selfhost_option !in ['', '0', '1'] { return error('VINIX_DEVELOPMENT_SELFHOST_V must be 0 or 1') }
	selfhost_v := selfhost_option == '1'
	if selfhost_v && os.args.len != 8 { return error('native V self-hosting requires the complete SDK, V root and shell arguments') }
	if os.args.len == 8 && os.getenv('VINIX_DEVELOPMENT_V_SMOKE_ROOT') != '' {
		return error('use either the native V build gate or the prepared V smoke root')
	}
	kernel := os.real_path(os.args[2])
	stage := os.real_path(os.args[3])
	state := os.abs_path(os.args[4])
	if os.exists(state) { return error('state directory must be new') }
	manifest := json2.decode[Stage](os.read_file(stage + '/development-tools.json')!, strict: true)!
	if manifest.schema != 1 || !manifest.complete || manifest.architecture != arch {
		return error('incomplete or wrong-architecture tools')
	}
	os.mkdir_all(state)!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	init := guesthost.compile_init(guesthost.root() + '/tests/development/guestfixture/core.v', state, arch, false)!
	root := state + '/rootfs'
	os.mkdir_all(root + '/usr/bin')!
	os.mkdir_all(root + '/home/developer')!
	mut hashes := map[string]string{}
	mut v_smoke_hash := ''
	for tool in ['vinix-build', 'vinix-qualify', 'vinix-vm', 'vinix-jobs'] {
		binary := stage + '/usr/bin/' + tool
		hash := digest(binary)!
		if manifest.binaries[tool] != hash { return error('staged tool changed: ' + tool) }
		header := os.read_bytes(binary)!
		machine := if header.len >= 20 { u16(header[18]) | (u16(header[19]) << 8) } else { u16(0) }
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		} {
			return error('wrong ELF tool: ' + tool)
		}
		os.cp(binary, root + '/usr/bin/' + tool)!
		os.chmod(root + '/usr/bin/' + tool, 0o755)!
		hashes[tool] = hash
	}
	if source := os.getenv_opt('VINIX_DEVELOPMENT_V_SMOKE_ROOT') {
		v_root := os.real_path(source)
		os.mkdir_all(root + '/usr/lib')!
		mut hash := sha256.new()
		copy_sdk(v_root, root + '/usr/lib/vlang', v_root, '.', mut hash)!
		v_smoke_hash = hash.sum([]u8{}).hex()
		binary := root + '/usr/lib/vlang/v'
		header := os.read_bytes(binary)!
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| (u16(header[18]) | u16(header[19]) << 8) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
			return error('prepared V compiler has the wrong ELF architecture')
		}
		hashes['v-smoke'] = digest(binary)!
		os.symlink('/usr/lib/vlang/v', root + '/usr/bin/v-smoke')!
	}
	// Optional prepared ELF smoke coverage is kept distinct from native builds.
	if cpu_binary := os.getenv_opt('VINIX_DEVELOPMENT_CPU_BINARY') {
		binary := os.real_path(cpu_binary)
		header := os.read_bytes(binary)!
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| (u16(header[18]) | (u16(header[19]) << 8)) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
			return error('prepared lscpu has the wrong ELF architecture')
		}
		hashes['lscpu-smoke'] = digest(binary)!
		os.cp(binary, root + '/usr/bin/lscpu-smoke')!
		os.chmod(root + '/usr/bin/lscpu-smoke', 0o755)!
		if digest(root + '/usr/bin/lscpu-smoke')! != hashes['lscpu-smoke'] || digest(binary)! != hashes['lscpu-smoke'] {
			return error('prepared lscpu changed during copy')
		}
	}
	os.cp(init, root + '/usr/bin/development-payload')!
	os.chmod(root + '/usr/bin/development-payload', 0o755)!
	mut fifo_plan_sha := ''
	for name in ['jobs', 'link-jobs', 'fifo-jobs'] {
		plan := Plan{
			jobs: [Job{
				executable:       Pin{'/usr/bin/development-payload', digest(init)!}
				interval_seconds: if name == 'fifo-jobs' { 1 } else { 3600 }
				credential_files: {
					'TEST_TOKEN': '/home/developer/' + if name == 'link-jobs' {
						'token-link'
					} else {
						'token'
					}
				}
			}]
		}
		text := json2.encode(plan)
		if name == 'fifo-jobs' { fifo_plan_sha = sha256.sum(text.bytes()).hex() }
		os.write_file(root + '/home/developer/' + name + '.json', text)!
	}
	os.write_file(root + '/home/developer/token', 'vinix-native-fixture-secret')!
	mut lifecycle_plans := map[string]string{}
	for name in ['deadline', 'term', 'int', 'watch', 'interrupted'] {
		plan := Plan{jobs: [Job{
			executable: Pin{'/usr/bin/development-payload', digest(init)!}
			interval_seconds: if name == 'watch' { 2 } else { 3600 }
			timeout_seconds: if name == 'deadline' { 1 } else { 30 }
			environment: {
				'VINIX_DEVELOPMENT_PAYLOAD': if name == 'watch' { 'tick' } else if name == 'interrupted' { 'recover' } else { 'linger' }
				'VINIX_JOB_PROOF_PREFIX': '/home/developer/' + name
			}
			credential_files: { 'TEST_TOKEN': '/home/developer/token' }
		}]}
		text := json2.encode(plan)
		lifecycle_plans[name] = sha256.sum(text.bytes()).hex()
		os.write_file(root + '/home/developer/' + name + '-jobs.json', text)!
	}
	os.mkdir_all(root + '/home/developer/source')!
	os.write_file(root + '/home/developer/source/input.txt', 'build-fixture-input\n')!
	os.write_file(root + '/home/developer/build-template.json', json2.encode(BuildPlan{
		source: Pin{'/home/developer/source', '%s'}
		tools:  {
			'payload': Pin{'/usr/bin/development-payload', digest(init)!}
		}
	}))!
	mut sdk_hash := ''
	mut v_root_hash := ''
	mut source_revision := ''
	mut native_plan := BuildPlan{}
	mut profiles := []string{}
	mut compiler_hashes := map[string]string{}
	mut reference_plan := BuildPlan{}
	mut reference_plan_sha := ''
	mut reference_hash := ''
	mut reference_runtime_hash := ''
	mut reference_tools := map[string]Pin{}
	if reference.root != '' {
		os.mkdir_all(root + '/opt')!
		mut hash := sha256.new()
		copy_sdk(reference.root, root + '/opt/reference', reference.root, '.', mut hash)!
		// The imported prefix and default musl loader path are independently
		// pinned. No runtime from a second compiler SDK is overwritten.
		copy_sdk(root + '/opt/reference/lib', root + '/lib', root + '/opt/reference', './runtime-lib', mut hash)!
		loader := 'ld-musl-' + arch + '.so.1'
		if !os.exists(root + '/lib/' + loader) && !os.is_link(root + '/lib/' + loader) {
			os.symlink('libc.so', root + '/lib/' + loader)!
		}
		for directory in ['/opt/reference/lib', '/lib'] {
			for name in os.ls(root + directory)! {
				path := root + directory + '/' + name
				if os.is_link(path) && os.readlink(path)! == '/lib/libc.so' {
					os.rm(path)!
					os.symlink('libc.so', path)!
				}
			}
		}
		reference_hash = devcore.tree_hash(root + '/opt/reference')!
		reference_runtime_hash = devcore.tree_hash(root + '/lib')!
		mut steps := []BuildStep{}
		for name in referencecore.required_tools(reference.profiles) {
			pin := reference.tools[name]
			copied := root + '/opt/reference/bin/' + name
			if digest(copied)! != pin.sha256 { return error('reference tool changed during copy: ' + name) }
			reference_tools[name] = Pin{'/opt/reference/bin/' + name, pin.sha256}
			if name == 'sh' {
				os.mkdir_all(root + '/bin')!
				os.symlink('/opt/reference/bin/sh', root + '/bin/sh')!
			} else if name !in ['java', 'javac', 'jar'] {
				steps << BuildStep{ name: 'version-' + name, argv: ['{' + name + '}', ...referencecore.version_arguments(name)], artifacts: []string{} }
			}
		}
		source := root + '/home/developer/reference-source'
		os.mkdir(source, mode: 0o755)!
		os.write_file(source + '/profiles.txt', reference.profiles.join(',') + '\n')!
		os.chmod(source + '/profiles.txt', 0o644)!
		steps << BuildStep{ name: 'qualify', argv: ['{qualifier}', '--require-vinix', '{work}/qualification', reference.profiles.join(',')],
			artifacts: referencecore.artifacts(reference.profiles) }
		mut tools := reference_tools.clone()
		tools['qualifier'] = Pin{'/usr/bin/vinix-qualify', hashes['vinix-qualify']}
		mut environment := { 'PATH': '/opt/reference/bin:/usr/bin:/bin', 'VINIX_QUALIFY_TIMEOUT_SECONDS': '600' }
		if reference_ci {
			tools['ci_proof'] = Pin{'/usr/bin/development-payload', digest(init)!}
			environment['VINIX_DEVELOPMENT_PAYLOAD'] = 'ci-check'
			steps.prepend(BuildStep{name: 'ci-isolation', argv: ['{ci_proof}'], artifacts: ['ci-account.json']})
			ci_plan := Plan{jobs: [Job{id: 'ci', executable: Pin{'/usr/bin/vinix-build', hashes['vinix-build']},
				arguments: ['build', '/home/developer/reference-build.json', '/home/developer/ci-{attempt}'], expand_attempt: true,
				interval_seconds: 1, timeout_seconds: 1800, environment: {}, credential_files: {'CI_TOKEN': '/home/developer/token'}}]}
			os.write_file(root + '/home/developer/ci-jobs.json', json2.encode(ci_plan))!
		}
		if reference_jit {
			environment['VINIX_QUALIFY_JIT'] = '1'
			os.write_file(root + '/home/developer/reference-jit', 'java\n')!
		}
		reference_plan = BuildPlan{
			source: Pin{'/home/developer/reference-source', devcore.tree_hash(source)!}
			inputs: [Pin{'/opt/reference', reference_hash}, Pin{'/lib', reference_runtime_hash}]
			tools: tools
			environment: environment
			timeout_seconds: 1800
			steps: steps
		}
		plan_text := json2.encode(reference_plan)
		reference_plan_sha = sha256.sum(plan_text.bytes()).hex()
		os.write_file(root + '/home/developer/reference-build.json', plan_text)!
	}
	if os.args.len >= 6 {
		sdk := os.real_path(os.args[5])
		os.mkdir_all(root + '/opt')!
		mut hash := sha256.new()
		copy_sdk(sdk, root + '/opt/native', sdk, '.', mut hash)!
		// Dynamic project executables need the SDK's musl/C++ runtime in the
		// guest loader's default search path, with the same recorded bytes.
		copy_sdk(root + '/opt/native/lib', root + '/lib', os.real_path(root + '/opt/native'), './runtime-lib', mut hash)!
		sdk_hash = hash.sum([]u8{}).hex()
		for name in ['cc', 'c++'] {
			driver := if os.exists(root + '/opt/native/bin/' + name) {
				name
			} else if name == 'cc' {
				'gcc'
			} else {
				'g++'
			}
			binary := root + '/opt/native/bin/' + driver
			header := os.read_bytes(binary)!
			if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
				|| (u16(header[18]) | (u16(header[19]) << 8)) != if arch == 'aarch64' {
					u16(183)
				} else {
					u16(62)
				} {
				return error('native SDK compiler has the wrong ELF architecture')
			}
			compiler_hashes[if name == 'cc' { 'c' } else { 'cpp' }] = digest(binary)!
			os.symlink('/opt/native/bin/' + driver, root + '/usr/bin/' + name)!
		}
		profiles = ['c', 'cpp']
		if os.args.len == 8 {
			v_root := os.real_path(os.args[6])
			os.mkdir_all(root + '/usr/lib')!
			mut v_hash := sha256.new()
			copy_sdk(v_root, root + '/usr/lib/vlang', v_root, '.', mut v_hash)!
			v_root_hash = v_hash.sum([]u8{}).hex()
			v_binary := root + '/usr/lib/vlang/v'
			shell := os.real_path(os.args[7])
			for binary in [v_binary, shell] {
				header := os.read_bytes(binary)!
				if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
					|| (u16(header[18]) | (u16(header[19]) << 8)) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
					return error('native V or shell has the wrong ELF architecture')
				}
			}
			os.symlink('/usr/lib/vlang/v', root + '/usr/bin/v')!
			compiler_hashes['v'] = digest(v_binary)!
			hashes['v'] = compiler_hashes['v']
			os.mkdir_all(root + '/bin')!
			os.cp(shell, root + '/bin/busybox')!
			os.chmod(root + '/bin/busybox', 0o755)!
			if digest(shell)! != digest(root + '/bin/busybox')! { return error('shell changed during copy') }
			hashes['sh'] = digest(root + '/bin/busybox')!
			os.symlink('busybox', root + '/bin/sh')!
			profiles << 'v'
			userland := root + '/home/developer/native-source'
			os.mkdir(userland)!
			source_revision = sourcecore.revision(guesthost.root())!
			sourcecore.export(guesthost.root(), source_revision, ['util-vinix', 'init',
				'tools/packages/main.v', 'tools/packages/pkgcore', 'tools/packages/pkgprotocol', 'tools/packages/signing'], userland, build_source)!
			os.write_file(userland + '/SOURCE_REVISION', source_revision + '\n')!
			os.write_file(userland + '/assert-failure.v', 'fn main() {\n    assert 1 == 2\n}\n')!
			mut steps := []BuildStep{}
			if selfhost_v {
				os.write_file(root + '/home/developer/selfhost-v', '1\n')!
				v_revision := os.read_file(v_root + '/VERSION')!.trim_space()
				if v_revision.len !in [40, 64] || !v_revision.bytes().all(it.is_hex_digit()) {
					return error('self-host compiler needs a full pinned VERSION')
				}
				// The bootstrap is GC-free. Let it exit before native GCC starts,
				// so the compiler AST and GCC/assembler do not compete for RAM.
				steps << BuildStep{
					name: 'copy-selfhost-root'
					argv: ['{toolbox}', 'cp', '-a', '/usr/lib/vlang', '{work}/compiler']
					artifacts: []string{}
				}
				steps << BuildStep{
					name: 'translate-selfhost-v'
					argv: ['{v}', '-nocache', '-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
						'-d', 'skip_fastc', '-d', 'skip_wasm', '-d', 'skip_arm64', '-d', 'skip_eval', '-d', 'skip_ssa',
						'-path', '@vlib|/usr/lib/vlang', '-os', 'linux',
						'-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
						'-o', '{work}/selfhost-v.c', '/usr/lib/vlang/cmd/v']
					artifacts: ['selfhost-v.c']
				}
				steps << BuildStep{
					name: 'compile-selfhost-v'
					argv: ['{cc}', '-static', '-O0', '-w', '-std=gnu11', '-D_GNU_SOURCE', '-DV_COMMIT_HASH="' + v_revision + '"',
						'-include', '/usr/lib/vlang/vlib/v/pthread_helper.h', '{work}/selfhost-v.c',
						'/usr/lib/vlang/vlib/os/execute_capture_nix.o', '/usr/lib/vlang/vlib/v/pthread_helper.o',
						'/usr/lib/vlang/vlib/v/bench/peak_rss.o', '/usr/lib/vlang/vlib/v/modulecache/file_metadata.o',
						'/usr/lib/vlang/vlib/builtin/segfault_handler_nix.o', '-o', '{work}/compiler/v', '-lm', '-lpthread']
					artifacts: ['compiler/v']
				}
				steps << BuildStep{ name: 'version-selfhost-v', argv: ['{work}/compiler/v', '--version'], artifacts: []string{} }
			}
			project_v := if selfhost_v { '{work}/compiler/v' } else { '{v}' }
			steps << BuildStep{ name: 'help-v', argv: [project_v, '--help'], artifacts: []string{} }
			steps << BuildStep{
				name: 'compile-package'
				argv: [project_v, '-new-compiler', '-nocache', '-showcc', '-no-retry-compilation', '-no-parallel', '-no-memory-limit',
					'-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-musl', '-gc', 'none',
					'-cc', '{cc}', '-path', '@vlib|{work}', '-o', '{work}/package-bin', '{work}/tools/packages/main.v']
				artifacts: ['package-bin']
			}
			steps << BuildStep{ name: 'help-package', argv: ['{work}/package-bin', '--help'], artifacts: []string{} }
			steps << BuildStep{
				name: 'compile-assertion'
				argv: [project_v, '-new-compiler', '-nocache', '-no-retry-compilation', '-no-parallel', '-no-memory-limit',
					'-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-musl', '-gc', 'none',
					'-cc', '{cc}', '-o', '{work}/assert-bin', '{work}/assert-failure.v']
				artifacts: ['assert-bin']
			}
			for name in ['fetch', 'mount', 'chsh', 'lscpu', 'init'] {
				input := if name == 'init' { '/init' } else { '/util-vinix/' + name }
				steps << BuildStep{
					name: 'compile-' + name
					argv: [project_v, '-new-compiler', '-nocache', '-no-retry-compilation', '-no-parallel',
						'-no-memory-limit', '-os', 'vinix', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
						'-musl', '-gc', 'none', '-cc', '{cc}', '-o', '{work}/' + name + '-bin', '{work}' + input]
					artifacts: [name + '-bin']
				}
				steps << BuildStep{ name: 'run-' + name, argv: ['{work}/' + name + '-bin', '--version'], artifacts: []string{} }
			}
			steps << BuildStep{ name: 'inspect-lscpu', argv: ['{work}/lscpu-bin'], artifacts: []string{} }
			steps << BuildStep{ name: 'prepare-payload', argv: ['{toolbox}', 'mkdir', '-p', '{work}/payload/bin'], artifacts: []string{} }
			steps << BuildStep{ name: 'copy-payload', argv: ['{toolbox}', 'cp', '{work}/lscpu-bin', '{work}/payload/bin/lscpu'], artifacts: ['payload/bin/lscpu'] }
			os.write_file(userland + '/package.json', json2.encode(pkgcore.Package{
				id: 'org.vinix.native-lscpu', version: '1.0.0', architecture: arch, name: 'Native lscpu fixture',
				license: 'GPL-2.0-or-later', kind: 'native', entrypoint: 'bin/lscpu', permissions: ['files'],
			}))!
			// Public deterministic fixture data, never a production signing key.
			os.write_file(root + '/home/developer/publisher.seed', '00'.repeat(32) + '\n')!
			steps << BuildStep{ name: 'pack-package', argv: ['{work}/package-bin', 'pack', '{work}/package.json', '{work}/payload', '{work}/repository'],
				artifacts: ['repository/manifests/org.vinix.native-lscpu-' + arch + '-1.0.0.json'] }
			steps << BuildStep{ name: 'publish-package', argv: ['{work}/package-bin', 'publish-release', '{work}/repository',
				'development-fixture', '/home/developer/publisher.seed', '1', '2000000000', '{work}/release'],
				artifacts: ['release/index.json', 'release/index.sig'] }
			native_plan = BuildPlan{
				source: Pin{'/home/developer/native-source', devcore.tree_hash(userland)!}
				inputs: [Pin{'/opt/native', devcore.tree_hash(root + '/opt/native')!},
					Pin{'/usr/lib/vlang', devcore.tree_hash(root + '/usr/lib/vlang')!},
					Pin{'/lib', devcore.tree_hash(root + '/lib')!},
					Pin{'/home/developer/publisher.seed', digest(root + '/home/developer/publisher.seed')!}]
				tools: {
					'v': Pin{'/usr/lib/vlang/v', compiler_hashes['v']}
					'cc': Pin{'/usr/bin/cc', compiler_hashes['c']}
					'sh': Pin{'/bin/sh', hashes['sh']}
					'toolbox': Pin{'/bin/busybox', hashes['sh']}
				}
				timeout_seconds: if selfhost_v { 1800 } else { 600 }
				environment: { 'VJOBS': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'VINIX_V_ROOT': '/usr/lib/vlang' }
				steps: steps
			}
			os.write_file(root + '/home/developer/native-build.json', json2.encode(native_plan))!
		}
		os.write_file(root + '/home/developer/qualify-sdk', profiles.join(','))!
	}
	archive := guesthost.image(init, state)!
	// The archive already holds the complete guest closure. ISO assembly
	// needs it and the kernel, so retire the duplicate SDK tree first.
	os.rmdir_all(root)!
	launch := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	// Both architectures boot solely from the completed ISO.
	os.rm(archive)!
	mut command := launch.command.clone()
	if arch == 'x86_64' {
		if cpu := os.getenv_opt('VINIX_QEMU_CPU') { command[command.index('-cpu') + 1] = cpu }
	}
	if sdk_hash != '' || reference_hash != '' {
		for i, argument in command { if argument == '-m' {
			command[i + 1] = if selfhost_v { '8192' } else if v_root_hash == '' { '2048' } else { '3072' }
		} }
	}
	mut expected := [
		'DEVELOPMENT LOG HEAD SENTINEL',
		'DEVELOPMENT LOG TAIL SENTINEL',
		'DEVELOPMENT SIGNAL IDENTITY PASS:',
		'DEVELOPMENT ACCOUNT PASS:',
		'DEVELOPMENT PRIVATE FILE PASS:',
		'DEVELOPMENT SERVICE EXPORT PASS:',
		'DEVELOPMENT JOB CONTROL PASS:',
		'DEVELOPMENT BUILD PASS:',
		'DEVELOPMENT GUEST PASS',
	]
	if sdk_hash != '' { expected << 'DEVELOPMENT TOOLCHAINS PASS:' }
	if v_root_hash != '' { expected << 'DEVELOPMENT USERLAND PASS:' }
	if v_root_hash != '' { expected << 'DEVELOPMENT PACKAGES PASS:' }
	if selfhost_v { expected << 'DEVELOPMENT SELFHOST PASS:' }
	if reference_hash != '' { expected << 'DEVELOPMENT REFERENCE PASS:' }
	if reference_jit { expected << ['DEVELOPMENT JIT APPROVAL PASS:', 'DEVELOPMENT JIT REVOCATION PASS:'] }
	if reference_ci { expected << 'DEVELOPMENT CI PASS:' }
	if 'http' in reference.profiles { expected << 'DEVELOPMENT HTTP PASS:' }
	if 'lscpu-smoke' in hashes { expected << 'DEVELOPMENT CPU PASS:' }
	if 'v-smoke' in hashes { expected << 'DEVELOPMENT V SMOKE PASS:' }
	result := guesthost.boot(command, launch.env, state, expected,
		['DEVELOPMENT GUEST FAIL', 'KERNEL PANIC', 'vinix-native-fixture-secret'], if selfhost_v { 7200 } else if v_root_hash != '' { 2400 } else { 900 }, true)!
	mut receipts := map[string]string{}
	for line in os.read_lines(state + '/serial.log')! {
		if !line.starts_with('DEVELOPMENT RECEIPT ') { continue }
		entry := line.all_after('DEVELOPMENT RECEIPT ').trim_space()
		path := entry.all_before(' ')
		body := entry.all_after(' ')
		if path !in ['/home/developer/good/state.json', '/home/developer/good/plan.json',
			'/home/developer/public-token/state.json', '/home/developer/link-token/state.json',
			'/home/developer/fifo-failed.json', '/home/developer/fifo-token/state.json',
			'/home/developer/build-a/receipt.json', '/home/developer/build-b/receipt.json',
			'/home/developer/qualification/report.json', '/home/developer/native-build.json',
			'/home/developer/native-a/receipt.json', '/home/developer/native-b/receipt.json',
			'/home/developer/native-a/work/release/index.json', '/home/developer/native-b/work/release/index.json',
			'/home/developer/native-a/work/release/index.sig', '/home/developer/native-b/work/release/index.sig',
			'/home/developer/deadline-state/state.json', '/home/developer/term-state/state.json',
			'/home/developer/int-state/state.json', '/home/developer/watch-state/state.json',
			'/home/developer/interrupted-before.json', '/home/developer/interrupted-state/state.json',
			'/home/developer/reference-build.json', '/home/developer/reference-a/receipt.json', '/home/developer/reference-b/receipt.json',
			'/home/developer/reference-a/work/qualification/report.json', '/home/developer/reference-b/work/qualification/report.json',
			'/home/developer/reference-a/work/qualification/http/server.json', '/home/developer/reference-b/work/qualification/http/server.json',
			'/home/developer/ci-1/receipt.json', '/home/developer/ci-2/receipt.json',
			'/home/developer/ci-1/work/qualification/report.json', '/home/developer/ci-2/work/qualification/report.json',
			'/home/developer/ci-1/work/ci-account.json', '/home/developer/ci-2/work/ci-account.json',
			'/home/developer/ci-state/plan.json', '/home/developer/ci-state/state.json', '/home/developer/ci-completed.json'] {
			return error('unexpected guest receipt path')
		}
		json2.decode[json2.Any](body)!
		receipts[path] = body
	}
	if result == 0 && receipts.len != 2 + if reference_ci { 22 } else if 'http' in reference.profiles { 19 } else if reference_hash != '' { 17 } else if sdk_hash == '' { 12 } else if v_root_hash == '' { 13 } else { 20 } {
		return error('missing native workflow receipts')
	}
	if result == 0 {
		for failed in [true, false] {
			path := '/home/developer/' + if failed { 'fifo-failed.json' } else { 'fifo-token/state.json' }
			schedule := json2.decode[NativeSchedule](receipts[path], strict: true)!
			job := schedule.jobs['fixture'] or { return error('missing native private-file job') }
			if schedule.schema != 1 || schedule.uid != 1000 || schedule.plan_sha256 != fifo_plan_sha
				|| schedule.jobs.len != 1 || job.in_flight
				|| job.attempts != if failed { u64(1) } else { u64(2) }
				|| job.runs != job.attempts || job.exit_code != if failed { -1 } else { 0 }
				|| (failed && !job.detail.starts_with('private file must be regular'))
				|| (!failed && job.detail != 'finished') || job.started <= 0
				|| job.finished < job.started || job.next_due != job.finished + 1 {
				return error('native private-file failure/recovery receipt changed')
			}
		}
		if reference_ci {
			cicore.verify(receipts['/home/developer/ci-state/plan.json'], receipts['/home/developer/ci-completed.json'],
				receipts['/home/developer/ci-state/state.json'], hashes['vinix-build'])!
		}
		if reference_hash != '' {
			mut common := map[string]string{}
			mut tool_pins := map[string]devcore.Pin{}
			for name, pin in reference_tools { tool_pins[name] = devcore.Pin{pin.path, pin.sha256} }
			for position, output in cicore.outputs(reference_ci) {
				work := '/home/developer/' + output + '/work'
				receipt := json2.decode[NativeBuild](receipts['/home/developer/' + output + '/receipt.json'], strict: true)!
				if receipt.schema != 1 || receipt.plan_sha256 != reference_plan_sha
					|| !receipt.complete || receipt.uid != 1000 || receipt.kernel != 'Vinix' || receipt.epoch != 1700000000
					|| receipt.source != reference_plan.source || receipt.inputs != reference_plan.inputs || receipt.tools != reference_plan.tools
					|| receipt.steps.len != reference_plan.steps.len || receipt.steps.any(it.exit_code != 0 || it.detail != '') {
					return error('reference SDK build inputs, account or completion failed validation')
				}
				for i, step in receipt.steps {
					planned := reference_plan.steps[i]
					mut argv := planned.argv.map(it.replace('{work}', work))
					for name, pin in reference_plan.tools { argv = argv.map(it.replace('{' + name + '}', pin.path)) }
					if step.name != planned.name || step.argv != argv || step.artifacts.len != planned.artifacts.len {
						return error('reference SDK command order, argv or artifacts changed')
					}
					for name in planned.artifacts {
						hash := step.artifacts[name]
						if hash.len != 64 { return error('missing reference output hash') }
						if name == 'qualification/report.json' { continue }
						if position == 0 { common[name] = hash }
						else if common[name] != hash { return error('reference artifact differs between workspaces: ' + name) }
						if name.ends_with('/project.data') && hash != sha256.sum('42'.bytes()).hex() {
							return error('reference project readback artifact changed')
						}
					}
				}
				referencecore.verify_report_jit(receipts[work + '/qualification/report.json'], arch, reference.profiles,
					hashes['vinix-qualify'], tool_pins, work, receipt.steps.last().artifacts, reference_jit)!
				if reference_ci {
					if receipts[work + '/ci-account.json'] + '\n' != cicore.account_proof
						|| receipt.steps[0].artifacts['ci-account.json'] != sha256.sum(cicore.account_proof.bytes()).hex() {
						return error('CI account or credential-isolation proof changed')
					}
				}
				if 'http' in reference.profiles {
					proof := receipts[work + '/qualification/http/server.json']
					referencecore.verify_http_proof(proof)!
					if sha256.sum((proof + '\n').bytes()).hex() != receipt.steps.last().artifacts['qualification/http/server.json'] {
						return error('HTTP native evidence does not match its artifact pin')
					}
				}
			}
		}
		for name in ['deadline', 'term', 'int', 'watch', 'interrupted', 'interrupted-before'] {
			path := '/home/developer/' + if name == 'interrupted-before' { name + '.json' } else { name + '-state/state.json' }
			state_receipt := json2.decode[NativeSchedule](receipts[path], strict: true)!
			plan_name := if name == 'interrupted-before' { 'interrupted' } else { name }
			if state_receipt.schema != 1 || state_receipt.uid != 1000
				|| state_receipt.plan_sha256 != lifecycle_plans[plan_name]
				|| state_receipt.jobs.len != 1 || 'fixture' !in state_receipt.jobs {
				return error('native schedule identity or plan pin changed')
			}
			job := state_receipt.jobs['fixture']
			interrupted_before := name == 'interrupted-before'
			failed := name in ['deadline', 'term', 'int']
			expected_detail := if name == 'deadline' { 'job deadline expired' }
				else if name in ['term', 'int'] { 'job interrupted' }
				else if interrupted_before { 'running' } else { 'finished' }
			if job.in_flight != interrupted_before || job.detail != expected_detail
				|| job.runs != if interrupted_before { u64(0) } else if name == 'watch' { u64(2) } else { u64(1) }
				|| job.attempts != if name in ['watch', 'interrupted'] { u64(2) } else { u64(1) }
				|| job.exit_code != if failed { -1 } else { 0 }
				|| job.started <= 0 || (!interrupted_before && (job.finished < job.started
					|| job.next_due != job.finished + if name == 'watch' { 2 } else { 3600 })) {
				return error('native job deadline, signal, watch or recovery state failed validation')
			}
		}
		expected_artifact := sha256.sum('build-fixture-input\n'.bytes()).hex()
		for name in ['build-a', 'build-b'] {
			receipt := json2.decode[NativeBuild](receipts['/home/developer/' + name + '/receipt.json'],
				strict: true
			)!
			if !receipt.complete || receipt.uid != 1000 || receipt.kernel != 'Vinix'
				|| receipt.epoch != 1700000000 || receipt.steps.len != 1
				|| receipt.steps[0].exit_code != 0 || receipt.steps[0].artifacts['artifact.txt'] != expected_artifact {
				return error('native build receipt failed independent artifact check')
			}
		}
		if sdk_hash != '' {
			report := json2.decode[NativeQualification](receipts['/home/developer/qualification/report.json'],
				strict: true
			)!
			if report.schema != 1 || report.kernel != 'Vinix' || report.architecture != arch || report.command_timeout_seconds != 600
				|| report.runner_sha256 != hashes['vinix-qualify']
				|| !report.complete || !report.all_selected_passed || report.uid != 1000 || report.context != 'vinix-native'
				|| report.requested != profiles || report.results.len != profiles.len
				|| report.results.any(it.status != 'passed' || it.commands.len != 2) {
				return error('native compiler project qualification failed')
			}
			for i, profile in report.results {
				if profile.profile != report.requested[i]
					|| profile.commands.any(it.exit_code != 0 || it.executable_sha256.len != 64)
					|| profile.commands[0].executable_sha256 != compiler_hashes[profile.profile]
					|| profile.commands[1].argv != ['/home/developer/qualification/' + profile.profile + '/project'] {
					return error('native compiler or executed artifact receipt mismatch')
				}
			}
		}
		if v_root_hash != '' {
			mut artifacts := map[string]string{}
			for output in ['native-a', 'native-b'] {
				receipt := json2.decode[NativeBuild](receipts['/home/developer/' + output + '/receipt.json'], strict: true)!
				if !receipt.complete || receipt.uid != 1000 || receipt.kernel != 'Vinix' || receipt.epoch != 1700000000
					|| receipt.source != native_plan.source || receipt.inputs != native_plan.inputs || receipt.tools != native_plan.tools
					|| receipt.steps.len != native_plan.steps.len || receipt.steps.any(it.exit_code != 0 || it.detail != '') {
					return error('native userland build inputs or steps failed validation')
				}
				for i, step in receipt.steps {
					planned := native_plan.steps[i]
					mut expected_argv := planned.argv.map(it.replace('{work}', '/home/developer/' + output + '/work'))
					for name, pin in native_plan.tools {
						expected_argv = expected_argv.map(it.replace('{' + name + '}', pin.path))
					}
					if step.name != planned.name || step.argv != expected_argv {
						return error('native userland step order or executed command changed')
					}
					if planned.artifacts.len != 0 {
						if step.artifacts.len != planned.artifacts.len { return error('missing native build artifacts') }
						for name in planned.artifacts {
							hash := step.artifacts[name]
							if hash.len != 64 { return error('missing native artifact hash') }
							if output == 'native-a' { artifacts[name] = hash }
							else if artifacts[name] != hash { return error('native artifact differs between fresh workspaces: ' + name + ': ' + artifacts[name] + ' / ' + hash) }
						}
					} else if step.artifacts.len != 0 {
						return error('unexpected native userland output artifact')
					}
				}
				release := '/home/developer/' + output + '/work/release/'
				proof := json2.decode[PackageProof](receipts[release + 'index.sig'], strict: true)!
				public_key := ed25519.new_key_from_seed(hex.decode('00'.repeat(32))!).public_key().hex()
				index_text := receipts[release + 'index.json'] + '\n'
				index := pkgcore.verify_index(pkgcore.Repository{id: 'development-fixture', public_key: public_key},
					index_text, proof.signature, time.now().unix())!
				if index.sequence != 1 || index.expires != 2000000000 || index.packages.len != 1
					|| index.packages[0].id != 'org.vinix.native-lscpu' || index.packages[0].architecture != arch
					|| index.packages[0].files.len != 1 || index.packages[0].files[0].path != 'bin/lscpu'
					|| !index.packages[0].files[0].executable || index.packages[0].files[0].sha256 != artifacts['lscpu-bin']
					|| index.packages[0].files[0].sha256 != proof.object_sha256 || index.packages[0].files[0].bytes != proof.object_bytes
					|| sha256.sum(index_text.bytes()).hex() != artifacts['release/index.json']
					|| sha256.sum((proof.signature + '\n').bytes()).hex() != artifacts['release/index.sig'] {
					return error('signed native package failed independent payload/index validation')
				}
			}
		}
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		arch:            arch
		kernel_sha256:   digest(state + '/kernel/bin/vinix')!
		fixture_sha256:  digest(init)!
		sdk_sha256:      sdk_hash
		v_root_sha256:   v_root_hash
		v_smoke_root_sha256: v_smoke_hash
		selfhost_v: selfhost_v
		reference_sdk_sha256: reference_hash
		reference_runtime_sha256: reference_runtime_hash
		reference_profiles: reference.profiles
		reference_jit: reference_jit
		reference_ci: reference_ci
		reference_tools: reference_tools
		native_source_sha256: native_plan.source.sha256
		native_source_revision: source_revision
		tools:           hashes
		command:         command
		native_receipts: receipts
		passed:          result == 0
	}, prettify: true))!
	return result
}

fn main() {
	exit(run() or {
		eprintln(err)
		1
	})
}
