// Private four-profile controller. Preparing or compiling this file builds no kernel.
import crypto.sha256
import json2
import os
import time

const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'
const base = 'ad2c4322bc23e230f46b3631ffc873a03057c09b'
const candidate_commit = '654912d1bb7f12adf9a942bcd03b981129f28942'
const candidate = 'b19ed1590ce7cc7e9b5d3408839799b9ccb8cc8b271876d267e100b57c98e76b'
const make = '/Library/Developer/CommandLineTools/usr/bin/make'
const clang = '/Library/Developer/CommandLineTools/usr/bin/clang'
const linker = '/opt/homebrew/bin/ld.lld'
const archiver = '/opt/homebrew/opt/llvm/bin/llvm-ar'

struct Result {
	code int
	output string
}

struct BuildReceipt {
	base_commit string
	candidate_commit string
	candidate_source_sha256 string
	architecture string
	profile string
	build_executed bool
	build_exit_code int
	started_utc string
	finished_utc string
	command []string
	environment map[string]string
	inputs_before map[string]string
	inputs_after map[string]string
	outputs map[string]string
	baseline map[string]string
	context string = 'Private isolated source; no guest or repository integration'
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn environment() map[string]string {
	// Suppress inherited make/compiler overrides. HOME retains its existing value.
	return {'PATH': '/Library/Developer/CommandLineTools/usr/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'HOME': os.home_dir(), 'TMPDIR': area + '/tmp', 'LC_ALL': 'C', 'LANG': 'C',
		'V': compiler, 'VINIX_V_COMPILER': compiler, 'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'}
}

fn execute(args []string, folder string, log string) !Result {
	return execute_environment(args, folder, log, environment())
}

fn execute_host(args []string, folder string, log string) !string {
	mut env := environment()
	env["SDKROOT"] = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
	r := execute_environment(args, folder, log, env)!
	if r.code != 0 { return error("Host command failed: " + log) }
	return r.output
}

fn execute_environment(args []string, folder string, log string, env map[string]string) !Result {
	os.write_file(log + '.command.json', json2.encode({
		'argv': json2.Any(args.map(json2.Any(it))), 'cwd': folder,
		'environment': json2.encode(env), 'started_utc': time.utc().str()
	}, prettify: true) + '\n')!
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_work_folder(folder)
	p.set_environment(env)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, output)!
	os.write_file(log + '.status', code.str() + '\n')!
	return Result{code, output}
}

fn checked(args []string, folder string, log string) !string {
	r := execute(args, folder, log)!
	if r.code != 0 { return error('Command failed: ' + log) }
	return r.output
}

fn collect_dir(path string, mut pins map[string]string) ! {
	mut files := os.walk_ext(path, '')
	files.sort()
	for file in files {
		if file.contains('/.git/') || !os.is_file(file) { continue }
		pins[file] = digest(file)!
	}
}

fn source_state(tree string, state string, label string) !map[string]string {
	head := checked(['/usr/bin/git', 'rev-parse', 'HEAD'], tree, state + '/' + label + '-head.log')!.trim_space()
	if head != candidate_commit { return error('Unexpected source HEAD: ' + head) }
	clean := checked(['/usr/bin/git', 'status', '--porcelain', '--untracked-files=no'], tree, state + '/' + label + '-clean.log')!.trim_space()
	if clean.len != 0 { return error('Tracked candidate source is dirty: ' + clean) }
	parent := checked(['/usr/bin/git', 'rev-parse', 'HEAD^'], tree, state + '/' + label + '-parent.log')!.trim_space()
	if parent != base { return error('Candidate is not based directly on integration base') }
	names := checked(['/usr/bin/git', 'diff', '--name-only', base, 'HEAD'], tree, state + '/' + label + '-names.log')!.trim_space()
	if names != 'kernel/proc/nice.v\nkernel/syscall/table/linux_common.v' { return error('Unexpected tracked changes: ' + names) }
	checked(['/usr/bin/git', 'diff', '--check', base, 'HEAD'], tree, state + '/' + label + '-diff-check.log')!
	checked(['/usr/bin/git', 'diff', base, 'HEAD', '--', 'kernel/proc/nice.v', 'kernel/syscall/table/linux_common.v'], tree, state + '/' + label + '-source.diff')!
	if digest(tree + '/kernel/proc/nice.v')! != candidate { return error('Candidate source changed') }
	listed := checked(['/usr/bin/git', 'ls-files', '-z', '--', 'kernel', 'build-support',
		'tests/native-generators', 'tests/linuxkpi', 'tests/scheduler-qos', 'tools/sourcecommand', 'tools/hosttest',
		'tools/linux-compat'], tree, state + '/' + label + '-tracked-files.log')!
	mut pins := map[string]string{}
	for name in listed.split('\x00') {
		if name.len > 0 && os.is_file(tree + '/' + name) { pins[tree + '/' + name] = digest(tree + '/' + name)! }
	}
	return pins
}

fn inputs(tree string, state string, label string) !map[string]string {
	mut pins := source_state(tree, state, label)!
	mut links := map[string]string{}
	// Architecture-specific runtime directories are generated outputs. Only
	// cc-runtime's immutable source is a dependency; make clean removes outputs.
	for name in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi'] {
		path := tree + '/kernel/' + name
		links[path] = os.real_path(path)
		collect_dir(path, mut pins)!
	}
	path := tree + '/kernel/c/nanoprintf.h'
	links[path] = os.real_path(path)
	pins[path] = digest(path)!
	collect_dir(os.dir(compiler) + '/vlib', mut pins)!
	for tool in [@FILE, os.executable(), compiler, make, clang, linker, archiver,
		'/usr/bin/xcrun', '/bin/sh', '/usr/bin/sed', '/usr/bin/arch', '/usr/bin/file',
		'/Library/Developer/CommandLineTools/usr/bin/cc', area + '/prepared-source-inputs.json',
		area + '/source/kernel/proc/nice.v', area + '/source/kernel/syscall/table/linux_common.v', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/SDKSettings.json',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/errno.h', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/pthread.h',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/types.h'] {
		pins[tool] = digest(tool)!
		links[tool] = os.real_path(tool)
	}
	os.write_file(state + '/' + label + '-resolved-paths.json', json2.encode(links, prettify: true) + '\n')!
	os.write_file(state + '/' + label + '-inputs.json', json2.encode(pins, prettify: true) + '\n')!
	return pins
}

fn command(suffix string, flavor string) []string {
	return [make, 'ARCH=' + if suffix == 'arm' { 'aarch64' } else { 'x86_64' },
		'V=' + compiler, 'CC=' + clang, 'AR=' + archiver,
		'LD_AARCH64=' + linker, 'LD_X86_64=' + linker, 'PROD=true', '-j1',
		'LIMINE_MP=1', 'ALLOC_TRACK=' + if flavor == 'track' { '1' } else { '0' },
		'KERNEL_LINK_SEED=42']
}

fn attempt(state string, suffix string, flavor string, build bool) ! {
	tree := area + '/kernel-' + suffix
	started := time.utc().str()
	before := inputs(tree, state, 'before')!
	for pair in [['v', compiler, 'version'], ['cc', clang, '--version'],
		['make', make, '--version'], ['ld', linker, '--version'], ['ar', archiver, '--version']] {
		checked(pair[1..], tree, state + '/version-' + pair[0] + '.log')!
	}
	baseline := '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/prioquery-evidence/' + suffix + '/build'
	mut old := map[string]string{}
	for path in [baseline + '/kernel/bin/vinix', baseline + '/blob.c',
		baseline + '/receipt.json', baseline + '/build-inputs.json'] {
		old[path] = digest(path)!
	}
	os.write_file(state + '/baseline-inputs.json', json2.encode(old, prettify: true) + '\n')!
	args := command(suffix, flavor)
	os.write_file(state + '/planned-command.json', json2.encode(args, prettify: true) + '\n')!
	mut code := 0
	mut outputs := map[string]string{}
	if build {
		// Cleaning this private tree also removes initial runtime-output symlinks.
		checked([make, 'clean'], tree + '/kernel', state + '/clean.log')!
		if suffix == 'x86' {
			// Private host generator uses explicit native flags; kernel source/flags stay exact S.
			sdk_path := checked(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], tree, state + '/host-sdk.log')!.trim_space()
			if sdk_path != '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk' { return error('Unexpected native SDK path') }
			module_path := tree + '/tests/native-generators|' + tree + '/tools|' + tree + '/build-support|@vlib'
			execute_host([compiler, '-gc', 'none', '-cc', clang, '-showcc', '-cflags', '-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk', '-path', module_path, '-o',
				state + '/native-generators', tree + '/tests/native-generators/main.v'],
				tree + '/kernel', state + '/host-generator-compile.log')!
			os.mkdir_all(tree + '/kernel/obj')!
			execute_host([state + '/native-generators', 'sampler', 'obj/heap_benchmark.c'],
				tree + '/kernel', state + '/host-generator-run.log')!
			os.cp(tree + '/kernel/obj/heap_benchmark.c', state + '/heap_benchmark.c')!
			outputs[state + '/native-generators'] = digest(state + '/native-generators')!
			outputs[state + '/heap_benchmark.c'] = digest(state + '/heap_benchmark.c')!
		}
		result := execute(args, tree + '/kernel', state + '/build.log')!
		code = result.code
		if code == 0 {
			os.mkdir_all(state + '/kernel/bin')!
			for pair in [['kernel/bin/vinix', 'kernel/bin/vinix'], ['kernel/obj/blob.c', 'blob.c']] {
				os.cp(tree + '/' + pair[0], state + '/' + pair[1])!
				outputs[state + '/' + pair[1]] = digest(state + '/' + pair[1])!
			}
			runtime := tree + '/kernel/cc-runtime-' + if suffix == 'arm' { 'aarch64' } else { 'x86_64' } + '/cc-runtime.a'
			os.cp(runtime, state + '/cc-runtime.a')!
			outputs[state + '/cc-runtime.a'] = digest(state + '/cc-runtime.a')!
		}
	}
	after := inputs(tree, state, 'after')!
	if before != after { return error('Build inputs changed; before/after manifests preserved') }
	if os.read_file(state + '/before-resolved-paths.json')! != os.read_file(state + '/after-resolved-paths.json')! {
		return error('Dependency/tool resolution changed')
	}
	if os.read_file(state + '/before-source.diff')! != os.read_file(state + '/after-source.diff')! {
		return error('Candidate diff changed')
	}
	os.write_file(state + '/receipt.json', json2.encode(BuildReceipt{
		base_commit: base
		candidate_commit: candidate_commit
		candidate_source_sha256: candidate
		architecture: suffix
		profile: flavor
		build_executed: build
		build_exit_code: code
		started_utc: started
		finished_utc: time.utc().str()
		command: args
		environment: environment()
		inputs_before: before
		inputs_after: after
		outputs: outputs
		baseline: old
	}, prettify: true) + '\n')!
	if code != 0 { return error('Kernel build failed; raw log/status and after-inputs preserved') }
	if build {
		// Flat consumer schema; all supporting records bind exact build inputs.
		mut native := {
			'architecture': suffix, 'profile': flavor,
			'kernel_directory': state + '/kernel', 'source_directory': tree,
			'kernel_commit': candidate_commit,
			'kernel_sha256': digest(state + '/kernel/bin/vinix')!,
			'generated_c': state + '/blob.c', 'generated_c_sha256': digest(state + '/blob.c')!,
			'build_status': state + '/build.log.status'
		}
		for path in os.walk_ext(state, '') {
			if !os.is_file(path) { continue }
			native['artifact:' + path] = digest(path)!
		}
		for path in [@FILE, os.executable(), compiler, make, clang, linker, archiver] {
			native['artifact:' + path] = digest(path)!
		}
		os.write_file(state + '/build-inputs.json', json2.encode(native, prettify: true) + '\n')!
	}
	println(if build { 'Kernel build/input pins: PASS ' + state } else { 'Kernel build plan/input pins: PASS (no build) ' + state })
}

fn main() {
	assert os.args.len == 5 && os.args[1] in ['plan', 'build'], 'Usage: build-kernels plan|build arm|x86 track|prod FRESH_TAG'
	mode, suffix, flavor, tag := os.args[1], os.args[2], os.args[3], os.args[4]
	assert suffix in ['arm', 'x86'] && flavor in ['track', 'prod']
	assert tag.len > 0 && tag.bytes().all(it.is_alnum() || it in [`-`, `_`])
	state := area + '/states/kernel-' + tag + '-' + suffix + '-' + flavor
	assert !os.exists(state), 'Refusing to overwrite an attempt'
	os.mkdir_all(state)!
	os.mkdir_all(area + '/tmp')!
	build_lock := area + '/kernel-' + suffix + '.build-lock'
	os.mkdir(build_lock) or { panic('Another controller owns this architecture; inspect ' + build_lock) }
	defer { os.rmdir(build_lock) or {} }
	attempt(state, suffix, flavor, mode == 'build') or {
		os.write_file(state + '/controller-error.log', err.str() + '\n') or { panic(err) }
		os.write_file(state + '/status', '1\n') or { panic(err) }
		eprintln(err)
		exit(1)
	}
	os.write_file(state + '/status', '0\n')!
}
