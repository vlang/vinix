// SPDX-License-Identifier: MIT
module emulatorbuild

import fixturehost
import hosttest
import json2
import os
import policyhost
import runtime
import strconv

const n64_revision = 'ef73c7e6fa356262f88e05f85cdfad092f8f90e0'
const n64_digest = '0be08e52bb9a759253b802a546a699dc5cc8e2799f9234e45e64550b09ffc396'
const zlib_revision = '51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf'
const zlib_digest = 'd9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522'
const n64_patch_version = 'vinix-interpreter-5'
const ps2_revision = 'c43cd7e6017656a067acf9a4749480ff35e6fb3a'
const ps2_digest = '6030d1870917afed3ce60eb2ee374d0c38e18ccc6f6ce60128af270e339b00a6'

pub struct CoreTask {
pub:
	path string
	target string
	command []string
	stamp string
	directory string
}

struct CoreOutcome {
	index int
	output string
	failure string
}

// Workers own their child groups and pipe pairs. Only the main thread installs
// the signal scope; the cancellation flag is atomic and shared read-only here.
fn core_worker(tasks []CoreTask, queue chan int, results chan CoreOutcome, env map[string]string, arch string) {
	for {
		index := <-queue or { break }
		task := tasks[index]
		output := compile_task(task, env, arch) or {
			results <- CoreOutcome{index: index, failure: err.msg()}
			continue
		}
		results <- CoreOutcome{index: index, output: output}
	}
}

fn compile_task(task CoreTask, env map[string]string, arch string) !string {
	policyhost.command_checkpoint()!
	stamp_path := task.target[..task.target.len - 2] + '.stamp'
	if os.exists(task.target) && os.exists(stamp_path) && hosttest.module_read_text(stamp_path)! == task.stamp { return '' }
	result := fixturehost.capture_owned_bounded(task.command, env, arch, task.directory, -1,
		policyhost.command_interrupted, true)!
	if result.status != 0 { return error('compile failed: ' + task.path + '\n' + diagnostic_text(result.stdout)) }
	policyhost.command_checkpoint()!
	hosttest.module_write_text(stamp_path, task.stamp)!
	return result.stdout
}

// Python's errors=replace consumes the valid prefix of a malformed UTF-8
// sequence as one replacement. Successful compiler logs remain raw bytes.
pub fn diagnostic_text(text string) string {
	mut out := ''
	mut at := 0
	for at < text.len {
		first := text[at]
		if first < 128 { out += first.ascii_str(); at++; continue }
		length := if first >= 0xc2 && first <= 0xdf { 2 } else if first >= 0xe0 && first <= 0xef { 3 } else if first >= 0xf0 && first <= 0xf4 { 4 } else { 0 }
		if length == 0 { out += '�'; at++; continue }
		mut consumed := 1
		for consumed < length && at + consumed < text.len {
			ch := text[at + consumed]
			if ch < 0x80 || ch > 0xbf || (consumed == 1 && ((first == 0xe0 && ch < 0xa0) ||
				(first == 0xed && ch > 0x9f) || (first == 0xf0 && ch < 0x90) || (first == 0xf4 && ch > 0x8f))) { break }
			consumed++
		}
		if consumed == length { out += text[at..at + length] } else { out += '�' }
		at += consumed
	}
	return out
}

pub fn core_pool(tasks []CoreTask, jobs int, log string) ![]string {
	if jobs < 1 { return error('--jobs must be positive') }
	mut queue := chan int{cap: tasks.len}
	mut results := chan CoreOutcome{cap: tasks.len}
	for i in 0 .. tasks.len { queue <- i }
	queue.close()
	mut workers := []thread{}
	env, arch := policyhost.environment(), policyhost.caller_arch()
	for _ in 0 .. if jobs < tasks.len { jobs } else { tasks.len } {
		workers << spawn core_worker(tasks, queue, results, env, arch)
	}
	mut outcomes := []CoreOutcome{len: tasks.len}
	for _ in 0 .. tasks.len {
		outcome := <-results
		outcomes[outcome.index] = outcome
	}
	workers.wait()
	results.close()
	// Return the first failure in input order, after every child is reaped.
	// SIGINT bypasses the legacy Exception-only log rewrite.
	policyhost.command_checkpoint()!
	for outcome in outcomes {
		if outcome.failure != '' { hosttest.module_write_text(log, outcome.failure)!; return error(outcome.failure) }
	}
	mut stream := os.create(log)!
	defer { stream.close() }
	for outcome in outcomes { stream.write_string(outcome.output)! }
	return tasks.map(it.target)
}

fn core_capture(argv []string, directory string, merge bool) !fixturehost.CapturedCommand {
	policyhost.command_checkpoint()!
	result := fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), directory,
		-1, policyhost.command_interrupted, merge)!
	if result.status != 0 { return error('Command failed (' + result.status.str() + '): ' + argv.map(shell_word(it)).join(' ') + '\n' + diagnostic_text(result.stdout + result.stderr)) }
	policyhost.command_checkpoint()!
	return result
}

fn core_source(archive string, source string, output string, stamp string, prefix string, patch bool) ! {
	if os.is_file(source + '/.vinix-source') && hosttest.module_read_text(source + '/.vinix-source')! == stamp { return }
	work := private_directory(output, prefix)!
	defer { if os.exists(work) { retire(work) } }
	unpack_limit(archive, work, 16 * 1024 * 1024)!
	if patch { patch_n64(work)! }
	hosttest.module_write_text(work + '/.vinix-source', stamp)!
	policyhost.command_checkpoint()!
	if os.exists(source) { hosttest.remove_work_dir(source)! }
	os.rename(work, source)!
}

fn core_sdk(sdk string) !string {
	base := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	mut versions := os.ls(base) or { return ArgumentError{'ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh'} }
	versions.sort()
	if versions.len == 0 || !os.is_file(sdk + '/usr/lib/libc.a') { return ArgumentError{'ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh'} }
	gcc := base + '/' + versions.last()
	for path in [sdk + '/usr/include/c++/' + versions.last() + '/vector', sdk + '/usr/lib/libstdc++.a'] {
		if !os.is_file(path) { return ArgumentError{'build input missing: ' + path} }
	}
	return gcc
}

pub fn core_flags(values map[string]string, cpp bool) ![]string {
	key := if cpp { 'CXX_FLAGS' } else { 'C_FLAGS' }
	return hosttest.shell_split(values[key] or { return error('Missing manifest field: ' + key) })!.filter(it != '-MMD' && !it.starts_with('-DGIT_VERSION='))
}

fn core_build(kind string, output string, options map[string]string) ! {
	root := hosttest.root()
	support := root + '/build-support/' + kind
	sdk := hosttest.module_resolve(options['--sysroot'] or { root + '/build-aarch64-userland/staging' })!
	llvm := hosttest.module_resolve(options['--llvm-bin'] or { os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' } })!
	jobs := strconv.atoi(options['--jobs'] or { (if runtime.nr_cpus() < 8 { runtime.nr_cpus() } else { 8 }).str() }) or { return ArgumentError{'invalid integer for --jobs'} }
	if jobs < 1 { return ArgumentError{'--jobs must be positive'} }
	native := kind == 'n64' && '--host' in options
	gcc := if native { '' } else { core_sdk(sdk)! }
	cpp := if native { '' } else { sdk + '/usr/include/c++/' + os.file_name(gcc) }
	mut common := if kind == 'n64' {
		['-O2', '-DNDEBUG', '-D_GNU_SOURCE', '-DNO_ASM', '-DVINIX_NO_FALLOC', '-fcommon', '-fno-stack-protector', '-ffunction-sections', '-fdata-sections', '-Wno-everything']
	} else {
		['--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc, '-O2', '-fno-stack-protector', '-ffunction-sections', '-fdata-sections', '-funwind-tables', '-fexceptions', '-D_GNU_SOURCE', '-Wno-everything', '-I' + output + '/source/src', '-I' + support + '/include']
	}
	mut cxx := []string{}
	if kind == 'ps2' { cxx << '-std=c++20' }
	if !native {
		if kind == 'n64' {
			common << ['--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc]
			linux := hosttest.module_resolve(options['--linux-headers'] or { os.getenv_opt('VINIX_AARCH64_LINUX_HEADERS') or { root + '/build-aarch64-userland/sysroot/include' } })!
			if !os.is_file(linux + '/linux/futex.h') { return ArgumentError{'Linux headers missing; run scripts/build-userland-aarch64.sh'} }
			common << ['-idirafter', linux]
		}
		cxx << ['-nostdinc++', '-isystem' + cpp, '-isystem' + cpp + '/aarch64-alpine-linux-musl', '-isystem' + cpp + '/backward']
	}
	for name in ['clang', 'clang++', 'llvm-ar'] { if !os.is_file(llvm + '/' + name) { return ArgumentError{'build input missing: ' + llvm + '/' + name} } }
	mkdir(output)!
	archive, source := output + if kind == 'n64' { '/parallel-source.tar.gz' } else { '/iris-source.tar.gz' }, output + '/source'
	digest, revision := if kind == 'n64' { n64_digest } else { ps2_digest }, if kind == 'n64' { n64_revision } else { ps2_revision }
	fetch_as(archive, 'https://codeload.github.com/' + if kind == 'n64' { 'libretro/parallel-n64' } else { 'allkern/iris' } + '/tar.gz/' + revision,
		digest, if kind == 'n64' { 16 * 1024 * 1024 } else { 8 * 1024 * 1024 }, if kind == 'n64' { 'Vinix-N64-build' } else { 'Vinix-PS2-build' })!
	core_source(archive, source, output, digest + if kind == 'n64' { n64_patch_version } else { '' }, if kind == 'n64' { 'n64-source-' } else { 'iris-source-' }, kind == 'n64')!
	mut values := map[string]string{}
	mut inputs := []CoreInput{}
	mut headers := digest
	if kind == 'n64' {
		manifest := output + '/manifest.mk'
		hosttest.module_write_text(manifest, 'vinix-manifest:\n\t@echo C_SOURCES=$(SOURCES_C)\n\t@echo CXX_SOURCES=$(SOURCES_CXX)\n\t@echo C_FLAGS=$(CFLAGS)\n\t@echo CXX_FLAGS=$(CXXFLAGS)\n')!
		result := core_capture(['make', '--no-print-directory', '-s', '-f', 'Makefile', '-f', manifest, 'vinix-manifest',
			'platform=unix', 'WITH_DYNAREC=', 'HAVE_OPENGL=0', 'HAVE_THR_AL=1', 'HAVE_PARALLEL=0', 'HAVE_PARALLEL_RSP=0', 'HAVE_LTCG=0',
			'STATIC_LINKING=0', 'UNAME=Linux', 'ARCH=aarch64', 'CPUOPTS=-O2', 'GIT_VERSION=' + revision[..7], 'CC=' + llvm + '/clang'], source, false)!
		eprint(result.stderr)
		hosttest.module_decode_utf8(result.stdout)!
		for line in result.stdout.split_into_lines() { if at := line.index('=') { values[line[..at]] = line[at + 1..] } }
		for key in ['C_SOURCES', 'CXX_SOURCES'] {
			for file in (values[key] or { return error('Missing manifest field: ' + key) }).fields() {
				// Path's lexical join discards './' in upstream make entries.
				inputs << CoreInput{source + '/' + file.split('/').filter(it != '' && it != '.').join('/'), key == 'CXX_SOURCES'}
			}
		}
		zarchive, zsource := output + '/zlib-source.tar.gz', output + '/zlib-source'
		fetch_as(zarchive, 'https://codeload.github.com/madler/zlib/tar.gz/' + zlib_revision, zlib_digest, 16 * 1024 * 1024, 'Vinix-N64-build')!
		core_source(zarchive, zsource, output, zlib_digest, 'zlib-source-', false)!
		for name in ['adler32', 'compress', 'crc32', 'deflate', 'gzclose', 'gzlib', 'gzread', 'gzwrite', 'inflate', 'infback', 'inftrees', 'inffast', 'trees', 'uncompr', 'zutil'] { inputs << CoreInput{zsource + '/' + name + '.c', false} }
		common << '-I' + zsource
		headers += n64_patch_version + zlib_digest
		for name in ['bridge.h', 'budget.h'] { headers += hosttest.file_digest(support + '/' + name)! }
	} else { inputs = ps2_inputs(source, support)! }
	obj := output + '/obj'
	mkdir(obj)!
	compiler_result := core_capture([llvm + '/clang', '--version'], '', false)!
	eprint(compiler_result.stderr)
	hosttest.module_decode_utf8(compiler_result.stdout)!
	libc := if native { 'host' } else { hosttest.file_digest(sdk + '/usr/lib/libc.a')! }
	mut tasks := []CoreTask{}
	for input in inputs {
		relative := if input.path.starts_with(source + '/') { input.path[source.len + 1..] } else { os.file_name(input.path) }
		target := obj + '/' + relative.replace('/', '_') + '.o'
		mut command := [llvm + if input.cpp { '/clang++' } else { '/clang' }]
		if kind == 'n64' { command << core_flags(values, input.cpp)!; command << '-DGIT_VERSION=" ' + revision[..7] + '"' }
		command << common
		if input.cpp { command << cxx }
		name := os.file_name(input.path)
		if kind == 'n64' && name in ['pure_interp.c', 'rsp.c'] { command << ['-include', support + '/budget.h'] }
		if kind == 'ps2' {
			if name == 'bridge.c' { command << ['-x', 'c++'] } else { command << ['-include', support + '/include/core.h', '-D__assert_fail=vinix_ps2_core_assert'] }
			if name == 'spu2.c' { command << ['-Dps2_spu2_init=vinix_ps2_unused_spu2_init', '-Dps2_spu2_destroy=vinix_ps2_unused_spu2_destroy'] }
		}
		command << ['-c', input.path, '-o', target]
		mut stamp := {'command': json2.Any(command.map(json2.Any(it))), 'source': json2.Any(hosttest.file_digest(input.path)!), 'headers': json2.Any(headers), 'compiler': json2.Any(compiler_result.stdout), 'libc': json2.Any(libc)}
		if kind == 'ps2' { for key, file in {'shim': 'include/SDL3/SDL.h', 'exit_shim': 'include/core.h', 'bridge_header': 'bridge.h', 'native_abi': 'vbridge/native-abi.h'} { stamp[key] = json2.Any(hosttest.file_digest(support + '/' + file)!) } }
		tasks << CoreTask{input.path, target, command, cache_json(json2.Any(stamp)), if kind == 'n64' { source } else { '' }}
	}
	mut objects := core_pool(tasks, jobs, output + '/core-build.log')!
	bridge := support + if kind == 'n64' { '/bridgecore' } else { '/vbridge' }
	generated := output + '/bridge.generated.c'
	architecture := if !native || os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	producer := hosttest.generate_module_with_capture(bridge, generated, architecture, []string{}, module_capture)!
	print(producer.stdout); eprint(producer.stderr)
	mut strict := if kind == 'n64' { core_flags(values, false)! } else { []string{} }
	strict << common.filter(it != '-Wno-everything')
	strict << ['-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-I' + bridge]
	bridge_obj := obj + '/bridge-v.o'
	policyhost.owned_inherited_environment([llvm + '/clang', ...strict, '-c', generated, '-o', bridge_obj], policyhost.environment(), policyhost.caller_arch(), if kind == 'n64' { source } else { '' })!
	abi_obj := obj + if kind == 'n64' { '/bridge-abi.o' } else { '/bridge-unwind.o' }
	mut abi_flags := if kind == 'ps2' { common.clone() } else if native { []string{} } else { ['--target=aarch64-linux-musl', '--sysroot=' + sdk] }
	policyhost.inherited([llvm + '/clang', ...abi_flags, '-c', bridge + if kind == 'n64' { '/varargs.S' } else { '/unwind-arm.S' }, '-o', abi_obj])!
	objects << [bridge_obj, abi_obj]
	library, temporary := output + '/libvinix_' + kind + '.a', output + '/libvinix_' + kind + '.new.a'
	if os.exists(temporary) { os.rm(temporary)! }
	defer { if os.exists(temporary) { os.rm(temporary) or {} } }
	policyhost.inherited([llvm + '/llvm-ar', 'rcs', temporary, ...objects])!
	policyhost.command_checkpoint()!
	os.rename(temporary, library)!
	core_notices(kind, output, source, support, archive)!
	println(if kind == 'n64' { 'Built paraLLEl-N64 ' + revision[..7] + ' (pure CPU/LLE RSP/synchronous Angrylion): ' + library } else { 'Built Iris 0.15-alpha ' + revision[..7] + ' (interpreter/software GS): ' + library })
}

struct CoreInput { path string; cpp bool }

fn ps2_inputs(source string, support string) ![]CoreInput {
	mut c := []string{}
	mut cpp := []string{}
	collect_core_files(source + '/src', mut c, mut cpp)!
	c.sort_with_compare(core_path_compare)
	cpp.sort_with_compare(core_path_compare)
	c << cpp
	mut inputs := []CoreInput{}
	for path in c {
		name := os.file_name(path)
		if name in ['ee_uncached.c', 'ps2_elf.c', 'ioman.cpp'] || ('renderer' in path.split('/') && name != 'software.cpp') { continue }
		inputs << CoreInput{path, path.ends_with('.cpp')}
	}
	inputs << [CoreInput{support + '/bridge.c', true}, CoreInput{support + '/ioman.cpp', true}]
	return inputs
}

// pathlib orders components, so 'disc/cue.c' precedes 'disc.c'. Sorting
// entire POSIX strings reverses those two archive members.
fn core_path_compare(a &string, b &string) int {
	left, right := a.split('/'), b.split('/')
	for index in 0 .. if left.len < right.len { left.len } else { right.len } {
		if left[index] < right[index] { return -1 }
		if left[index] > right[index] { return 1 }
	}
	return if left.len < right.len { -1 } else if left.len > right.len { 1 } else { 0 }
}

fn collect_core_files(directory string, mut c []string, mut cpp []string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_dir(path) && !os.is_link(path) { collect_core_files(path, mut c, mut cpp)! }
		else if path.ends_with('.c') { c << path }
		else if path.ends_with('.cpp') { cpp << path }
	}
}

fn core_notices(kind string, output string, source string, support string, archive string) ! {
	notices := output + '/staging/usr/share/licenses/vinix-' + kind
	mkdir(notices)!
	if kind == 'ps2' {
		os.cp(source + '/LICENSE', notices + '/Iris-LICENSE')!
		os.cp(support + '/README.md', notices + '/SOURCES.md')!
		for name in ['Play-LICENSE', 'Play-Framework-LICENSE', 'THIRD-PARTY-NOTICES'] { os.cp(support + '/' + name, notices + '/' + name)! }
		return
	}
	for name in ['README.md', 'THIRD-PARTY-NOTICES', 'GPL-2.0', 'MAME-LICENSE', 'CXD4-CC0', 'ZLIB-LICENSE'] { os.cp(support + '/' + name, notices + '/' + name)! }
	corresponding := output + '/staging/usr/share/vinix/n64/source'
	if os.exists(corresponding) { hosttest.remove_work_dir(corresponding)! }
	mkdir(corresponding)!
	for path in [archive, output + '/zlib-source.tar.gz'] { os.cp(path, corresponding + '/' + os.file_name(path))! }
	root := hosttest.root()
	for relative in ['build-support/n64', 'games/n64', 'build-support/n64-homebrew', 'build-support/native-emulator-tools',
		'build-support/tarcore', 'tools/tarstream', 'tests/linuxkpi/hosttest', 'tests/qemu-core/fixturehost', 'tests/host-policy/policyhost',
		'build-support/native-compat-tools', 'tests/native-guest-tools/guesthost', 'tests/native-policy-tools/nativepolicy', 'tests/native-policy-tools/cpufixture',
		'kernel/abiargs', 'build-support/aarch64-cc-shim'] { stage_core_tree(root + '/' + relative, corresponding + '/' + relative)! }
	for relative in ['scripts/build-n64-aarch64.sh', 'build-support/find-v.sh', 'build-support/run-v-tool.sh',
		'build-support/compile-v-module', 'tests/linuxkpi/generate_module.v'] {
		mkdir(os.dir(corresponding + '/' + relative))!
		hosttest.module_copy_file_preserving_stat(root + '/' + relative, corresponding + '/' + relative)!
	}
}

// Preserve relative module links. Copy source files and build entrypoints,
// excluding host executables, caches and temporary outputs in a shared tree.
fn stage_core_tree(source string, target string) ! {
	policyhost.command_checkpoint()!
	mkdir(target)!
	for name in os.ls(source)! {
		if name.starts_with('.') || name == '__pycache__' || name.ends_with('.pyc') { continue }
		from, to := source + '/' + name, target + '/' + name
		if os.is_link(from) {
			// The only module links in this distributed closure belong to the
			// native toolbox. Do not stage unrelated untracked links.
			if (source == hosttest.root() + '/build-support/native-emulator-tools' && name in ['hosttest', 'fixturehost', 'policyhost', 'tarstream', 'tarcore']) ||
				(source == hosttest.root() + '/build-support/native-compat-tools' && name in ['hosttest', 'fixturehost', 'policyhost', 'guesthost', 'nativepolicy']) {
				os.symlink(os.readlink(from)!, to)!
			}
			continue
		}
		if os.is_dir(from) { stage_core_tree(from, to)!; continue }
		if name.ends_with('.py') { continue }
		if name.all_after_last('.') in ['v', 'h', 'c', 'cpp', 'S', 'ld', 'md', 'sh', 'mod'] || name in ['build', 'test-bridge', 'download-homebrew', 'LICENSE', 'CXD4-CC0', 'GPL-2.0', 'MAME-LICENSE', 'ZLIB-LICENSE', 'THIRD-PARTY-NOTICES'] {
			hosttest.module_copy_file_preserving_stat(from, to)!
		}
	}
}
