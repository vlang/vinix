// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed sampler qualification recorder. Every child belongs to the supplied
// controller callback; this module starts and owns no subprocesses.
module currenttargetrecord

import crypto.sha256
import json2
import os
import time

const section = '/Users/alex/Library/Caches/vinix-codex/section14'
const root = section + '/current-peer-frame-integration-20261105-01/target-consumer-host-01'
const sources = root + '/source-03'
const toolchain = section + '/current-target-v-2f91-20261105-01/toolchain'
const compiler = toolchain + '/v'
const compiler_sha = '482d0c3b5fe591e4b72c613e032c5bc212126c3a0708e18db87dc36e7d907d40'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const clang_sha = '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
const resource_headers = '/opt/homebrew/Cellar/llvm/23.1.0/lib/clang/23/include'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'

struct Job {
	output string
	project string
	arch string
	sampler bool
	sanitizer bool
	args []string
}

struct Scan {
mut:
	started i64 = time.sys_mono_now()
	entries int
	bytes u64
	project_source_bytes u64
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn under(path string, directory string) bool { return path == directory || path.starts_with(directory + '/') }

fn bound(mut scan Scan) ! {
	scan.entries++
	require(scan.entries <= 20000 && scan.bytes <= u64(256) << 20
		&& time.sys_mono_now() - scan.started < 300 * time.second, 'fixed recorder observation bound')!
}

fn ordinary(path string) !os.Stat {
	info := os.lstat(path)!
	require(info.mode & 0o170000 == 0o100000 && info.nlink == 1,
		'ordinary unaliased file required: ' + path)!
	return info
}

fn same(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string, mut scan Scan) !string {
	before := ordinary(path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	for {
		bound(mut scan)!
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		scan.bytes += u64(n)
		hash.write(buffer[..n])!
	}
	require(same(before, ordinary(path)!), 'file changed during hash: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn directory(path string) ! {
	info := os.lstat(path)!
	require(os.real_path(path) == path && info.mode & 0o170000 == 0o040000
		&& info.uid == u32(os.getuid()) && info.mode & 0o022 == 0,
		'canonical private directory required: ' + path)!
}

fn job(args []string) !Job {
	require(args.len in [14, 15] && args.all(!it.contains('\x00')), 'only fixed C-generation argv accepted')!
	output := args[args.len - 2]
	project := args.last()
	parent := os.dir(output)
	name := os.base(parent)
	require(os.dir(parent) == root && name in ['sampler-arm64-plain', 'sampler-arm64-san',
		'sampler-amd64-plain', 'sampler-amd64-san'], 'fixed sampler output phase required')!
	directory(parent)!
	require(!present(output), 'fresh generated C required')!
	require(os.dir(project) == root + '/tmp', 'private temporary project root required')!
	directory(project)!
	arch := if name.starts_with('sampler-arm64-') { 'arm64' } else { 'amd64' }
	is_sampler := os.base(output) == 'sampler.c'
	require(is_sampler || os.base(output) == 'fixture.c', 'only sampler.c or fixture.c accepted')!
	require(os.base(project).starts_with(if is_sampler { 'vinix-kalloc-v-' } else { 'vinix-v-module-' }),
		'generator temporary project kind differs')!
	mut expected := ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers']
	if is_sampler { expected << '-nofloat' }
	expected << ['-gc', 'none', '-manualfree', '-o', output, project]
	require(args == expected, 'existing generator argv differs')!
	return Job{output, project, arch, is_sampler, name.ends_with('-san'), args}
}

fn environment() ! {
	require(os.getenv('CC') == clang && os.getenv('SDKROOT') == sdk
		&& os.getenv('VFLAGS') == '' && os.getenv('CFLAGS') == ''
		&& os.getenv('CPPFLAGS') == '' && os.getenv('LDFLAGS') == '',
		'fixed compiler/SDK environment and empty ambient flags required')!
	// Environment construction, the frozen V identity, cache/temp isolation and
	// inherited read/write sandbox belong to the calling fixed controller.
	require(os.getenv('V') == compiler && os.getenv('VEXE') == compiler
		&& os.getenv('V_MACOS_V3_NO_FALLBACK') == '1'
		&& os.getenv('TMPDIR') == root + '/tmp', 'fixed private compiler environment required')!
}

fn capture(argv []string, seconds int, proof string, label string, unique string,
	run fn (string, []string, int) !string, mut scan Scan) !string {
	bound(mut scan)!
	remaining := int((300 * time.second - (time.sys_mono_now() - scan.started)) / time.second)
	require(remaining > 0, 'no fixed recorder wall remains')!
	wall := if remaining < seconds { remaining } else { seconds }
	os.write_file(proof + '/' + label + '.argv.json', json2.encode(argv) + '\n')!
	result := run(unique + '-' + label, argv, wall)!
	require(result.len < 256 * 1024, 'complete bounded command stdout required')!
	os.write_file(proof + '/' + label + '.stdout', result)!
	os.write_file(proof + '/' + label + '.status.json', json2.encode({
		'ownership': 'Supplied controller callback returned successfully; module owns no child.'}) + '\n')!
	bound(mut scan)!
	return result
}

fn project_tree(path string, relative string, copy string, depth int, mut scan Scan,
	mut files map[string]string) ! {
	bound(mut scan)!
	require(depth <= 16 && files.len < 256, 'bounded temporary generator project required')!
	before := os.lstat(path)!
	require(before.uid == u32(os.getuid()) && !os.is_link(path), 'private project source alias refused')!
	kind := before.mode & 0o170000
	if kind == 0o040000 {
		files[relative] = 'directory:' + before.mode.str()
		if copy != '' { os.mkdir(copy)! }
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			project_tree(path + '/' + name, if relative == '.' { name } else { relative + '/' + name },
				if copy == '' { '' } else { copy + '/' + name }, depth + 1, mut scan, mut files)!
		}
	} else {
		require(kind == 0o100000 && before.nlink == 1 && before.size <= 512 * 1024,
			'bounded ordinary temporary source required')!
		scan.project_source_bytes += before.size
		require(scan.project_source_bytes <= 512 * 1024, 'complete temporary project exceeds 512KiB')!
		hash := digest(path, mut scan)!
		files[relative] = json2.encode({'mode': before.mode.str(), 'size': before.size.str(),
			'mtime': before.mtime.str(), 'ctime': before.ctime.str(), 'sha256': hash})
		if copy != '' {
			os.cp(path, copy)!
			os.chmod(copy, int(before.mode & 0o7777))!
			require(digest(copy, mut scan)! == hash, 'independent project source copy differs')!
		}
	}
	require(same(before, os.lstat(path)!), 'temporary project changed while observed')!
}

fn allowed(path string, active Job) bool {
	return under(path, active.project) || under(path, toolchain) || under(path, sources)
		|| under(path, sdk) || under(path, resource_headers) || path == active.output
}

fn dependencies(paths []string, active Job, v_only bool, mut scan Scan) !map[string]string {
	require(paths.len > 0 && paths.len <= 2048, 'bounded nonempty dependency list required')!
	mut result := map[string]string{}
	for literal in paths {
		require(literal.starts_with('/') && !literal.contains('\x00') && !literal.contains('\r')
			&& literal !in result, 'absolute unique dependency required')!
		resolved := os.real_path(literal)
		require(allowed(literal, active) && resolved != '' && allowed(resolved, active),
			'dependency escaped declared literal/resolved private/SDK roots: ' + literal)!
		if v_only {
			require(literal.ends_with('.v') && (under(resolved, active.project) || under(resolved, toolchain + '/vlib')),
				'V source escaped private project/library roots')!
		}
		info := os.lstat(literal)!
		result[literal] = json2.encode({'resolved': resolved, 'mode': info.mode.str(),
			'link': if os.is_link(literal) { os.readlink(literal)! } else { '' },
			'sha256': digest(resolved, mut scan)!})
	}
	return result
}

fn lines(text string) ![]string {
	require(text.len > 0 && text.len <= 256 * 1024 && text.ends_with('\n'), 'complete dependency list required')!
	return text.trim_right('\n').split('\n')
}

fn native_paths(text string) ![]string {
	require(text.len > 0 && text.len <= 256 * 1024 && text.ends_with('\n'), 'bounded complete native dependency output required')!
	joined := text.replace('\\\r\n', ' ').replace('\\\n', ' ')
	require(joined.starts_with('proxy-native:') && joined.count(':') == 1
		&& !joined.contains('\\') && !joined.contains('$') && !joined.contains('#'),
		'unsupported native Make dependency framing; raw output retained')!
	mut seen := map[string]bool{}
	mut result := []string{}
	for path in joined['proxy-native:'.len..].fields() {
		require(path.starts_with('/'), 'absolute native dependency path required')!
		if path !in seen { result << path; seen[path] = true }
	}
	return result
}

fn native_argv(active Job) []string {
	mut args := [clang, '-arch', if active.arch == 'amd64' { 'x86_64' } else { 'arm64' },
		'-isysroot', sdk, '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
	if active.sanitizer { args << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	if active.sampler { args << ['-DVINIX_KALLOC_HOST_TEST', '-I', sources + '/kernel/c'] }
	else { args << ['-Wno-unused-function', '-Wno-unused-parameter', '-I', sources + '/tests/alloc-bench/samplerfixture'] }
	args << ['-M', '-MT', 'proxy-native', active.output]
	return args
}

fn generate(active Job, run fn (string, []string, int) !string, mut scan Scan) !string {
	proof := active.output + '.inputs'
	unique := os.base(os.dir(active.output)) + '-' + os.base(active.output).all_before_last('.')
	require(!present(proof), 'fresh per-output proof directory required')!
	os.mkdir(proof)!
	environment()!
	os.write_file(proof + '/environment.json', json2.encode(os.environ()) + '\n')!
	mut before := map[string]string{}
	scan.project_source_bytes = 0
	project_tree(active.project, '.', proof + '/project', 0, mut scan, mut before)!
	os.write_file(proof + '/project-before.json', json2.encode(before) + '\n')!
	strict := [compiler, '-new-compiler', '-b', 'c', '-no-retry-compilation', '-nocache',
		'-no-parallel', '-cflags', '-isysroot ' + sdk, '-path', active.project + '|' + toolchain + '/vlib']
	printed := capture([...strict, '-cc', '/usr/bin/false', '-print-v-files', ...active.args],
		60, proof, 'v-paths', unique, run, mut scan)!
	v_paths := lines(printed)!
	v_before := dependencies(v_paths, active, true, mut scan)!
	os.write_file(proof + '/v-dependencies.json', json2.encode(v_before) + '\n')!
	_ = capture([...strict, '-cc', '/usr/bin/false', '-check-syntax', ...active.args],
		60, proof, 'syntax', unique, run, mut scan)!
	actual_manifest := proof + '/actual.files'
	require(!present(actual_manifest), 'fresh actual compiler manifest required')!
	emitted := capture([...strict, '-cc', clang, '-dump-files', actual_manifest, ...active.args],
		120, proof, 'emit', unique, run, mut scan)!
	require(ordinary(active.output)!.size <= 2 * 1024 * 1024, 'bounded sampler/fixture generated C required')!
	raw_sha := digest(active.output, mut scan)!
	os.cp(active.output, proof + '/raw.c')!
	require(digest(proof + '/raw.c', mut scan)! == raw_sha, 'raw generated C copy differs')!
	manifest_paths := lines(os.read_file(actual_manifest)!)!
	for path in v_paths { require(path in manifest_paths, 'actual compiler manifest omitted parsed V source')! }
	manifest_before := dependencies(manifest_paths, active, false, mut scan)!
	os.write_file(proof + '/actual-dependencies.json', json2.encode(manifest_before) + '\n')!
	native := capture(native_argv(active), 30, proof, 'native', unique, run, mut scan)!
	n_paths := native_paths(native)!
	require(active.output in n_paths, 'native compiler omitted actual generated C')!
	native_before := dependencies(n_paths, active, false, mut scan)!
	os.write_file(proof + '/native-dependencies.json', json2.encode(native_before) + '\n')!
	mut after := map[string]string{}
	scan.project_source_bytes = 0
	project_tree(active.project, '.', '', 0, mut scan, mut after)!
	require(before == after && v_before == dependencies(v_paths, active, true, mut scan)!
		&& manifest_before == dependencies(manifest_paths, active, false, mut scan)!
		&& native_before == dependencies(n_paths, active, false, mut scan)!
		&& digest(active.output, mut scan)! == raw_sha, 'generator sources/dependencies changed during proxy operation')!
	os.write_file(proof + '/project-after.json', json2.encode(after) + '\n')!
	os.write_file(proof + '/qualification.json', json2.encode({'format': '1', 'compiler': compiler,
		'compiler_sha256': compiler_sha, 'clang': clang, 'clang_sha256': clang_sha,
		'generated_c_sha256': raw_sha, 'v_source_count': v_paths.len.str(),
		'actual_manifest_count': manifest_paths.len.str(), 'native_dependency_count': n_paths.len.str(),
		'scope': 'Fixed generator raw C plus parsed V paths, separate syntax gate, actual compiler dump and successful LLVM native dependency preprocessing. Sources/dependencies hashed while private temporary project exists. No processed-C, object, executable, sampler-result or complete SDK qualification.'}) + '\n')!
	return emitted
}

// Only the sampler or independent sampler fixture C-emission argv are
// accepted. The callback must reject nonzero status, preserve complete stderr,
// clamp the supplied wall to its outer deadline, and retain its nativeguard
// cleanup receipts. Compiler selection remains with the generator callback.
pub fn emit(argv []string, run fn (string, []string, int) !string) !string {
	$if !prod { return error('compile fixed recorder with -prod for embedded source binding') }
	require(os.read_file(@FILE)! == $embed_file('core.v').to_string(), 'recorder source changed')!
	mut scan := Scan{}
	require(digest(compiler, mut scan)! == compiler_sha && digest(clang, mut scan)! == clang_sha,
		'fixed compiler identity differs')!
	require(argv.len > 1 && argv[0] == compiler, 'literal frozen V compiler required')!
	directory(root)!
	directory(root + '/tmp')!
	result := generate(job(argv[1..])!, run, mut scan)!
	require(digest(compiler, mut scan)! == compiler_sha && digest(clang, mut scan)! == clang_sha,
		'fixed compiler changed during recorder operation')!
	return result
}
