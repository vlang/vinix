// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module officenative

import cachecli
import cachekey
import hosttest
import json2
import os
import sourcecommand
import strconv

pub struct Options {
pub:
	repo    string
	office  string
	ui2     string
	output  string
	work    string
	v       string
	arch    string
	clang   string
	strip   string
	target  string
	sysroot string
	gcclib  string
	cc_shim string
	llvm    string
	jobs    int = 4
	only    []string
}

fn path_argument(args cachecli.Arguments, key string) string {
	if key !in args.options { return '' }
	value := args.value(key, '')
	return if value == '' { '.' } else { value }
}

pub fn parse(argv []string) !Options {
	required := ['--repo', '--office-source', '--ui2-source', '--output', '--work', '--v', '--arch',
		'--clang', '--strip', '--target', '--sysroot', '--gcclib']
	args := cachecli.arguments(argv, [...required, '--cc-shim', '--llvm-bin', '--jobs'], ['--only'], []string{}, 0, 0, 'usage: build_voffice --repo DIR --office-source DIR --ui2-source DIR --output DIR --work DIR --v FILE --arch x64|arm64 --clang FILE --strip FILE --target TRIPLE --sysroot DIR --gcclib DIR [--only calc|writer] [--jobs N]')!
	for key in required { args.required(key)! }
	arch := args.value('--arch', '')
	if arch !in ['x64', 'arm64'] { return error('invalid --arch') }
	for name in args.options['--only'] {
		if name !in ['calc', 'writer'] { return error('invalid --only') }
	}
	jobs := strconv.atoi(args.value('--jobs', os.getenv_opt('VINIX_OFFICE_JOBS') or { '4' })) or { return error('invalid integer for --jobs') }
	return Options{
		repo:    path_argument(args, '--repo')
		office:  path_argument(args, '--office-source')
		ui2:     path_argument(args, '--ui2-source')
		output:  path_argument(args, '--output')
		work:    path_argument(args, '--work')
		v:       path_argument(args, '--v')
		arch:    arch
		clang:   path_argument(args, '--clang')
		strip:   path_argument(args, '--strip')
		target:  args.value('--target', '')
		sysroot: path_argument(args, '--sysroot')
		gcclib:  path_argument(args, '--gcclib')
		cc_shim: path_argument(args, '--cc-shim')
		llvm:    path_argument(args, '--llvm-bin')
		jobs:    if jobs > 0 { jobs } else { 1 }
		only:    args.options['--only']
	}
}

pub fn command(argv []string, quiet bool) !string {
	cachecli.checkpoint()!
	result := if quiet {
		sourcecommand.capture_combined(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	} else {
		sourcecommand.capture(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	}
	if quiet {
		if result.status != 0 { eprint(result.stdout) }
	} else {
		print(result.stdout)
		eprint(result.stderr)
	}
	if result.status != 0 {
		return error('command exit ' + result.status.str() + ': ' + argv.join(' '))
	}
	return result.stdout
}

pub fn compiler_root(v string) !string {
	root := os.dir(hosttest.module_resolve(v)!)
	if !os.is_dir(root + '/vlib') || !os.is_dir(root + '/thirdparty/mbedtls') {
		return error(v + ' must be an executable in a V source checkout with bundled mbedTLS')
	}
	return root
}

pub fn cc_base(args Options, vroot string, headers string) []string {
	mut argv := [args.clang, '--target=' + args.target, '-nostdinc']
	if args.cc_shim != '' { argv << ['-isystem', args.cc_shim] }
	if args.target.starts_with('aarch64-') { argv << ['-isystem', headers] }
	for path in [args.gcclib + '/include', args.sysroot + '/usr/include'] {
		argv << ['-isystem', path]
	}
	for path in ['include', 'library', '3rdparty/everest/include', '3rdparty/everest/include/everest',
		'3rdparty/everest/include/everest/kremlib'] {
		argv << ['-I', vroot + '/thirdparty/mbedtls/' + path]
	}
	argv << ['-O2', '-fno-stack-protector', '-w']
	return argv
}

pub fn tls_sources(vroot string) ![]string {
	text := os.read_file(vroot + '/vlib/net/mbedtls/mbedtls.c.v')!
	mut sources := []string{}
	for line in text.split_into_lines() {
		if line.starts_with('#flag @VEXEROOT/thirdparty/mbedtls/') && line.ends_with('.o') {
			sources << line.all_after('#flag @VEXEROOT/thirdparty/mbedtls/').trim_string_right('.o') + '.c'
		}
	}
	if sources.len == 0 { return error('could not find bundled mbedTLS object inventory') }
	return sources
}

fn object_name(source string) string {
	return source.trim_string_right('.c').replace('/', '_') + '.o'
}

pub fn tls_command(args Options, vroot string, headers string, source string) []string {
	return [...cc_base(args, vroot, headers), '-c', vroot + '/thirdparty/mbedtls/' + source, '-o',
		args.work + '/mbedtls/' + object_name(source)]
}

struct CompileFailure {
	index   int
	message string
}

fn tls_worker(args Options, vroot string, headers string, sources []string, worker int, workers int) []CompileFailure {
	mut failures := []CompileFailure{}
	for index, source in sources {
		if index % workers != worker { continue }
		command(tls_command(args, vroot, headers, source), true) or { failures << CompileFailure{index, err.msg()} }
	}
	return failures
}

pub fn build_tls(args Options, vroot string, headers string) ![]string {
	os.mkdir_all(args.work + '/mbedtls')!
	sources := tls_sources(vroot)!
	mut tasks := []thread []CompileFailure{}
	workers := if args.jobs < sources.len { args.jobs } else { sources.len }
	for worker in 0 .. workers {
		tasks << spawn tls_worker(args, vroot, headers, sources, worker, workers)
	}
	mut failure := CompileFailure{ index: sources.len }
	for task in tasks {
		for item in task.wait() { if item.index < failure.index { failure = item } }
	}
	if failure.message != '' { return error(failure.message) }
	println('    built ' + sources.len.str() + ' bundled mbedTLS objects')
	return sources.map(args.work + '/mbedtls/' + object_name(it))
}

pub fn app_command(args Options, name string) []string {
	path := if name == 'calc' { 'cmd/excel' } else { 'cmd/word' }
	return [args.v, '-new-compiler', '--no-parallel', '-no-memory-limit', '-os', 'linux', '-arch',
		args.arch, '-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d',
		'no_backtrace', '-d', 'ui2_headless', '-path', '@vlib|' + args.work + '/vmodules', '-o',
		args.work + '/' + name + '.c', args.office + '/' + path]
}

pub fn link_command(args Options, vroot string, headers string, objects []string, name string) []string {
	base := cc_base(args, vroot, headers)
	mut cmd := [base[0], '-static', '-nostdlib', ...base[1..], '-I', args.office,
		'-Wno-error=incompatible-function-pointer-types', args.sysroot + '/usr/lib/crt1.o',
		args.sysroot + '/usr/lib/crti.o', args.gcclib + '/crtbeginT.o', args.work + '/' + name + '.c',
		...objects, '-L' + args.sysroot + '/usr/lib', '-L' + args.gcclib, '-lgcc_eh', '-lc', '-lgcc',
		'-lm', args.gcclib + '/crtend.o', args.sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld']
	if args.llvm != '' { cmd << '-B' + args.llvm }
	cmd << ['-o', args.work + '/voffice-' + name]
	return cmd
}

pub fn usable(path string) bool {
	return os.is_file(path) && os.file_size(path) > 0 && os.is_executable(path)
}

pub struct State {
pub:
	version    int
	shared_key string
	apps       map[string]string
}

pub fn load_state(output string) State {
	text := os.read_file(output + '/.vinix-voffice-build-state.json') or { return State{} }
	value := json2.decode[State](text, strict: true) or { return State{} }
	return if value.version == 3 { value } else { State{} }
}

pub fn protect(args Options, vroot string) ! {
	protected := [os.home_dir(), args.repo, args.office, args.ui2, vroot].map(hosttest.module_resolve(it)!)
	output := hosttest.module_resolve(args.output)!
	work := hosttest.module_resolve(args.work)!
	if output == work { return error('VOffice output and work directories must be different') }
	for path in [output, work] {
		if path == '/' || path in protected {
			return error('refusing unsafe VOffice build directory: ' + path)
		}
		// An ancestor would remove a protected input; likewise, work may not
		// contain the published output that a partial build must preserve.
		if protected.any(it.starts_with(path + '/')) {
			return error('build directory contains a protected input: ' + path)
		}
	}
	if output.starts_with(work + '/') || work.starts_with(output + '/') {
		return error('VOffice output and work directories may not contain each other')
	}
}

pub fn build(args Options, builder string) ! {
	for path in [args.office + '/v.mod', args.office + '/cmd/excel/main.v',
		args.office + '/cmd/word/main.v', args.office + '/assets/logo.png', args.ui2 + '/v.mod'] {
		if !os.is_file(path) { return error('missing VOffice/ui2 input: ' + path) }
	}
	headers := command([args.clang, '--print-resource-dir'], true)!.trim_space() + '/include'
	if !os.is_dir(headers) { return error('Clang resource headers not found at ' + headers) }
	vroot := compiler_root(args.v)!
	protect(args, vroot)!
	os.mkdir_all(args.output)!
	for name in os.ls(args.output)! {
		if name.starts_with('voffice-') && name !in ['voffice-calc', 'voffice-writer'] && os.is_file(args.output + '/' + name) {
			os.rm(args.output + '/' + name)!
		}
	}
	names := if args.only.len > 0 { args.only } else { ['calc', 'writer'] }
	shared := cachekey.office_shared(cachekey.OfficeInputs{ repo: args.repo, builder: builder, office: args.office, ui2: args.ui2, v: args.v, vroot: vroot, arch: args.arch, target: args.target, clang: args.clang, strip: args.strip, clang_headers: headers, sysroot: args.sysroot, gcclib: args.gcclib, cc_shim: args.cc_shim, llvm: args.llvm })!
	state := load_state(args.output)
	mut cached := if state.shared_key == shared { state.apps.clone() } else { map[string]string{} }
	mut keys := map[string]string{}
	mut dirty := []string{}
	for name in names {
		keys[name] = cachekey.office_key(args.office, shared, name)!
		if cached[name] != keys[name] || !usable(args.output + '/voffice-' + name) { dirty << name }
	}
	if dirty.len == 0 {
		println('    reusing ' + names.len.str() + ' cached VOffice applications')
		return
	}
	if os.is_link(args.work) { return error('refusing linked VOffice work directory') }
	if os.exists(args.work) { hosttest.remove_work_dir(args.work)! }
	os.mkdir_all(args.work)!
	modules := args.work + '/vmodules'
	command([args.repo + '/desktop/tools/stage_ui2', modules + '/ui2', args.ui2,
		args.repo + '/desktop/tools/ui2_vinix_backend.v'], false)!
	os.symlink(hosttest.module_resolve(args.office)!, modules + '/office')!
	objects := build_tls(args, vroot, headers)!
	for name in dirty {
		command(app_command(args, name), true)!
		command(link_command(args, vroot, headers, objects, name), true)!
		command([args.strip, args.work + '/voffice-' + name], true)!
		cachecli.replace_file(args.work + '/voffice-' + name, args.output + '/voffice-' + name)!
		println('    built VOffice ' + if name == 'calc' { 'Calc' } else { 'Writer' })
		cached[name] = keys[name]
	}
	for key in cached.keys() { if key !in ['calc', 'writer'] { cached.delete(key) } }
	cachecli.publish(args.output + '/.vinix-voffice-build-state.json', json2.encode(State{3, shared, cached},
		prettify: true
	) + '\n')!
	reused := names.len - dirty.len
	println('    built ' + dirty.len.str() + ' VOffice applications' + if reused > 0 {
		'; reused ' + reused.str() + ' cached'
	} else {
		''
	})
}

pub fn cli(argv []string, builder string) int {
	args := parse(argv) or {
		eprintln(err.msg())
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	build(args, builder) or {
		eprintln('VOffice build failed: ' + err.msg())
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}
