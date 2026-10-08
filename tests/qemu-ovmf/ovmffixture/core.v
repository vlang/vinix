// SPDX-License-Identifier: GPL-2.0-only
module ovmffixture

import fixturehost
import hosttest
import json2
import os

fn repository() string {
	return os.getenv_opt('VINIX_OVMF_ROOT') or { os.real_path(os.dir(@FILE) + '/../../..') }
}

fn mkdirs(path string) ! {
	if os.is_dir(path) { return }
	parent := path.all_before_last('/')
	if parent != '' && parent != path { mkdirs(parent)! }
	os.mkdir(path)!
}

fn write_command(path string, body string) ! {
	mkdirs(path.all_before_last('/'))!
	fixturehost.write(path, '#!/bin/sh\n' + body)!
	os.chmod(path, 0o755)!
}

pub struct Context {
	root string
	checkout string
	source string
	driver string
	commands string
mut:
	environment map[string]string
	observations []json2.Any
}

pub fn context(name string) !Context {
	root := if parent := os.getenv_opt('VINIX_OVMF_WORK') {
		path := parent + '/' + name
		os.mkdir(path)!
		path
	} else { hosttest.work_dir('', 'vinix-ovmf-patch.')! }
	mut transferred := false
	defer { if !transferred { hosttest.remove_work_dir(root) or { panic(err) } } }
	os.chmod(root, 0o700)!
	checkout := root + '/vinix'
	for path in [checkout + '/scripts', checkout + '/patches/edk2'] { mkdirs(path)! }
	hosttest.module_copy_file(repository() + '/scripts/build-qemu-ovmf-aarch64.sh', checkout + '/scripts/build-qemu-ovmf-aarch64.sh')!
	hosttest.module_copy_file(repository() + '/' + patch_path, checkout + '/' + patch_path)!
	source := checkout + '/boot-image/edk2-edk2-stable202511'
	mkdirs(source + '/' + driver_path.all_before_last('/'))!
	mkdirs(source + '/BaseTools')!
	commands := checkout + '/test-bin'
	mkdirs(commands)!
	for tool_name, body in {
		'make': 'echo \'test: reached BaseTools build\'\nexit 73\n'
		'clang': 'exit 0\n'
		'llvm-ar': 'exit 0\n'
		'llvm-objcopy': 'exit 0\n'
		'ld.lld': 'exit 0\n'
		'brew': 'exit 1\n'
		'sysctl': 'echo 2\n'
		'nproc': 'echo 2\n'
	} { write_command(commands + '/' + tool_name, body)! }
	mut environment := os.environ()
	environment['PATH'] = commands + ':' + (environment['PATH'] or { '' })
	environment['CLANGDWARF_BIN'] = commands + '/'
	environment['VINIX_EDK2_SOURCE'] = source
	environment['GIT_CONFIG_GLOBAL'] = '/dev/null'
	environment['GIT_CONFIG_NOSYSTEM'] = '1'
	environment['GIT_AUTHOR_NAME'] = 'Firmware Test'
	environment['GIT_AUTHOR_EMAIL'] = 'firmware-test@example.invalid'
	environment['GIT_COMMITTER_NAME'] = 'Firmware Test'
	environment['GIT_COMMITTER_EMAIL'] = 'firmware-test@example.invalid'
	environment['LC_ALL'] = 'C'
	mut c := Context{root, checkout, source, source + '/' + driver_path, commands, environment, []json2.Any{}}
	initial := capture(['git', 'init', '-q', source], os.environ(), '', -1)!
	check(initial.code == 0, initial.stdout + initial.stderr)!
	transferred = true
	return c
}

// Keep the fixture's ten-second deadlines and drain both streams while the
// child runs. The explicit architecture route preserves a Rosetta caller.
fn capture(argv []string, environment map[string]string, directory string, timeout int) !hosttest.Result {
	command := $if darwin { ['/usr/bin/arch', if os.uname().machine == 'x86_64' { '-x86_64' } else { '-arm64' }, ...argv] } $else { argv }
	return hosttest.capture_in(command, '', timeout, environment, directory)!
}

// Returning an error keeps cleanup defers active even when an independent
// fixture assertion fails.
fn check(condition bool, message string) ! {
	if !condition { return error('Firmware fixture check failed: ' + message) }
}

pub fn (c Context) retire() ! { hosttest.remove_work_dir(c.root)! }

fn (mut c Context) git(repository string, arguments []string) !string {
	r := capture(['git', '-C', repository, ...arguments], c.environment, '', 10)!
	check(r.code == 0, r.stdout + r.stderr)!
	return r.stdout.replace('\r\n', '\n').replace('\r', '\n').trim_space()
}

fn (mut c Context) isolate_path() ! {
	for name in ['bash', 'git', 'dirname', 'basename', 'uname', 'sed'] {
		executable := os.find_abs_path_of_executable(name)!
		os.symlink(executable, c.commands + '/' + name)!
	}
	c.environment['PATH'] = c.commands
}

fn file_uri(path string) string {
	mut value := ''
	for byte in path.bytes() {
		if byte.is_alnum() || byte in [`/`, `-`, `_`, `.`, `~`] { value += byte.ascii_str() }
		else { value += '%${byte:02X}' }
	}
	return 'file://' + value
}

fn (mut c Context) prepare_bootstrap() !string {
	dependency := c.root + '/brotli-remote'
	mkdirs(dependency)!
	c.git(dependency, ['init', '-q'])!
	fixturehost.write(dependency + '/README', 'required first-level source\n')!
	c.git(dependency, ['add', 'README'])!
	c.git(dependency, ['commit', '-qm', 'Initial source'])!
	nested_commit := c.git(dependency, ['rev-parse', 'HEAD'])!
	fixturehost.write(dependency + '/.gitmodules', '[submodule "unused-tests"]\n\tpath = unused-tests\n\turl = ' + file_uri(c.root + '/unavailable-nested-repository') + '\n')!
	c.git(dependency, ['update-index', '--add', '--cacheinfo', '160000', nested_commit, 'unused-tests'])!
	c.git(dependency, ['add', '.gitmodules'])!
	c.git(dependency, ['commit', '-qm', 'Add unused nested dependency'])!
	remote := c.root + '/edk2-remote'
	mkdirs(remote + '/' + driver_path.all_before_last('/'))!
	c.git(remote, ['init', '-q'])!
	fixturehost.write(remote + '/' + driver_path, upstream.replace('\n', '\r\n'))!
	c.git(remote, ['add', driver_path])!
	c.git(remote, ['commit', '-qm', 'Initial driver'])!
	submodule := 'BaseTools/Source/C/BrotliCompress/brotli'
	fixturehost.write(remote + '/.gitmodules', '[submodule "' + submodule + '"]\n\tpath = ' + submodule + '\n\turl = ' + file_uri(dependency) + '\n')!
	commit := c.git(dependency, ['rev-parse', 'HEAD'])!
	c.git(remote, ['update-index', '--add', '--cacheinfo', '160000', commit, submodule])!
	c.git(remote, ['add', '.gitmodules'])!
	c.git(remote, ['commit', '-qm', 'Add required first-level dependency'])!
	c.git(remote, ['tag', 'edk2-stable202511'])!
	hosttest.remove_work_dir(c.source)!
	c.environment['GIT_CONFIG_COUNT'] = '2'
	c.environment['GIT_CONFIG_KEY_0'] = 'url.' + file_uri(remote) + '.insteadOf'
	c.environment['GIT_CONFIG_VALUE_0'] = 'https://github.com/tianocore/edk2.git'
	c.environment['GIT_CONFIG_KEY_1'] = 'protocol.file.allow'
	c.environment['GIT_CONFIG_VALUE_1'] = 'always'
	return c.source + '/' + submodule
}

fn (mut c Context) builder() !hosttest.Result {
	r := capture(['bash', c.checkout + '/scripts/build-qemu-ovmf-aarch64.sh'], c.environment, c.checkout, 10)!
	c.observations << json2.Any({
		'code': json2.Any(r.code)
		'stdout': json2.Any(r.stdout.replace('\r\n', '\n').replace('\r', '\n'))
		'stderr': json2.Any(r.stderr.replace('\r\n', '\n').replace('\r', '\n'))
		'driver_hex': json2.Any(fixturehost.read(c.driver)!.bytes().hex())
	})
	return r
}

fn reached(r hosttest.Result) ! {
	check(r.code == sentinel, r.stdout + r.stderr)!
	check(r.stdout.contains('Building edk2 BaseTools'), r.stdout)!
	check(r.stdout.contains('test: reached BaseTools build'), r.stdout)!
}

fn rejected(r hosttest.Result) ! {
	check(r.code == 1, r.stdout + r.stderr)!
	check(r.stderr.contains('ERROR: cannot apply'), r.stderr)!
	check(r.stderr.contains('error: patch failed:'), r.stderr)!
	check(r.stderr.contains(driver_path), r.stderr)!
	check(!r.stdout.contains('Building edk2 BaseTools'), r.stdout)!
}

fn (mut c Context) prepare_setup(script string) ! {
	fixturehost.write(c.driver, upstream)!
	fixturehost.write(c.commands + '/make', '#!/bin/sh\nexit 0\n')!
	fixturehost.write(c.source + '/edksetup.sh', script)!
	for name in ['PYTHON_COMMAND', 'WORKSPACE', 'EDK_TOOLS_PATH', 'PACKAGES_PATH', 'CONF_PATH'] { c.environment.delete(name) }
}

fn (mut c Context) prepare_toolchain() ! {
	c.prepare_setup('\nbuild() {\n    echo "test: compiler \${CLANGDWARF_BIN}clang"\n    echo "test: linker $(command -v ld.lld)"\n    return 73\n}\n')!
}

fn toolchain(r hosttest.Result, compiler string, linker string) ! {
	check(r.code == sentinel, r.stdout + r.stderr)!
	check(r.stdout.contains('test: compiler ' + compiler), r.stdout)!
	check(r.stdout.contains('test: linker ' + linker), r.stdout)!
}

pub fn (c Context) save_observations(name string) ! {
	if directory := os.getenv_opt('VINIX_OVMF_OBSERVATIONS') {
		fixturehost.write(directory + '/' + name + '.json', json2.encode(c.observations))!
	}
}
