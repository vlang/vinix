// SPDX-License-Identifier: GPL-2.0-or-later
// V orchestration of unmodified, pinned upstream SQLite and the V SDK runner.
module main

import json2
import os
import tools.packages.pkgcore

struct SourceFile {
	path string @[required]
	bytes u64 @[required]
	sha256 string @[required]
}

struct SourceLock {
	format int @[required]
	version string @[required]
	url string @[required]
	files []SourceFile @[required]
}

struct Artifact {
	path string
	bytes u64
	sha256 string
}

struct BuildRecord {
	format int = 1
	version string
	source SourceLock
	commands [][]string
	artifacts []Artifact
}

fn run(argv []string) !string {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	if child.code != 0 { return error('SQLite input build failed: ${argv}: ${output}') }
	return output.trim_space()
}

fn build() ! {
	if os.args.len != 3 { return error('usage: sqlite-build PINNED_AMALGAMATION_DIRECTORY NEW_OUTPUT_DIRECTORY') }
	repository := os.dir(os.dir(os.dir(@FILE)))
	source := os.abs_path(os.args[1])
	output := os.abs_path(os.args[2])
	if os.is_link(source) || !os.is_dir(source) || os.exists(output) || os.is_link(output)
		|| output.starts_with(source + '/') { return error('source must be ordinary and output fresh/outside it') }
	source_lock := json2.decode[SourceLock](os.read_file(repository + '/tests/packages/sqlite-source.json')!)!
	assert source_lock.format == 1 && source_lock.version == '3.53.4' && source_lock.files.len == 4
	os.mkdir_all(output + '/source', mode: 0o700)!
	for item in source_lock.files {
		assert item.path in ['sqlite3.c', 'shell.c', 'sqlite3.h', 'sqlite3ext.h']
		path := source + '/' + item.path
		if os.is_link(path) || !os.is_file(path) { return error('missing ordinary pinned source: ${item.path}') }
		os.cp(path, output + '/source/' + item.path)!
		assert os.file_size(output + '/source/' + item.path) == item.bytes
		assert pkgcore.hash_file(output + '/source/' + item.path)! == item.sha256, item.path
		os.chmod(output + '/source/' + item.path, 0o444)!
	}
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut commands := [][]string{}
	mut artifacts := []Artifact{}
	header := os.read_file(output + '/source/sqlite3.h')!
	notice_end := header.index('\n*************************************************************************') or { return error('SQLite copyright header unavailable') }
	for architecture in ['aarch64', 'x86_64'] {
		cc := os.find_abs_path_of_executable(os.getenv_opt('VINIX_MUSL_CC_' + architecture.to_upper()) or { architecture + '-linux-musl-gcc' })!
		loader := run([cc, '-print-file-name=libc.so'])!
		for variant in ['base', 'math'] {
			root := output + '/' + variant + '/' + architecture
			for directory in ['bin', 'lib', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
			mut flags := ['-O2', '-fno-stack-protector', '-DSQLITE_OMIT_LOAD_EXTENSION=1']
			if variant == 'math' { flags << '-DSQLITE_ENABLE_MATH_FUNCTIONS=1' }
			library := [cc, ...flags, '-shared', '-fPIC', '-Wl,-soname,libsqlite3.so.0',
				output + '/source/sqlite3.c', '-o', root + '/lib/libsqlite3.so.0', '-lm', '-lpthread']
			app := [cc, '-O2', '-fno-stack-protector', '-DSQLITE_OMIT_LOAD_EXTENSION=1', '-fPIE', '-pie', output + '/source/shell.c', '-L' + root + '/lib',
				'-lsqlite3', '-o', root + '/bin/sqlite3', '-lm', '-lpthread']
			commands << library
			run(library)!
			os.symlink('libsqlite3.so.0', root + '/lib/libsqlite3.so')!
			commands << app
			run(app)!
			os.rm(root + '/lib/libsqlite3.so')!
			os.cp(loader, root + '/lib/libc.so')!
			if variant == 'base' {
				generated := output + '/runner-' + architecture + '.c'
				generate := [v, '-os', 'linux', '-arch', if architecture == 'aarch64' { 'arm64' } else { 'amd64' },
					'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', generated, repository + '/tools/packages/linux-runner.v']
				compile := [cc, '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', generated,
					'-o', root + '/bin/vinix-linux-runner', '-lm', '-lpthread']
				commands << generate
				run(generate)!
				commands << compile
				run(compile)!
			} else { os.cp(output + '/base/' + architecture + '/bin/vinix-linux-runner', root + '/bin/vinix-linux-runner')! }
			for path in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libsqlite3.so.0'] { os.chmod(root + '/' + path, 0o755)! }
			os.write_file(root + '/licenses/sqlite-COPYRIGHT', header[..notice_end] + '\n*/\n')!
			os.cp(repository + '/build-support/musl/COPYRIGHT', root + '/licenses/musl-COPYRIGHT')!
			os.cp(repository + '/LICENSE', root + '/licenses/vinix-COPYING')!
			for path in os.walk_ext(root, '').filter(os.is_file(it)) {
				artifacts << Artifact{ path: path, bytes: os.file_size(path), sha256: pkgcore.hash_file(path)! }
			}
		}
		assert pkgcore.hash_file(output + '/base/' + architecture + '/bin/sqlite3')!
			== pkgcore.hash_file(output + '/math/' + architecture + '/bin/sqlite3')!, 'runtime-only qualification must retain the exact CLI bytes'
	}
	os.write_file(output + '/build.json', json2.encode(BuildRecord{ version: source_lock.version, source: source_lock,
		commands: commands, artifacts: artifacts }) + '\n')!
	println('SQLite inputs: pinned source, both target CLI/runtime variants and identical CLI bytes built')
}

fn main() { build() or { eprintln(err); exit(1) } }
