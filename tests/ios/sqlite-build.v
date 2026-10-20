// SPDX-License-Identifier: GPL-2.0-or-later
// Build an unmodified, hash-pinned SQLite engine with x18 reserved for Darwin.
module main

import os
import json2
import crypto.sha256

struct SqliteSource {
	path   string
	bytes  u64
	sha256 string
}

struct SqliteLock {
	format  int
	version string
	files   []SqliteSource
}

fn sqlite_checked(args []string) {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0, output
}

fn main() {
	assert os.args.len == 3, 'usage: sqlite-build PINNED_AMALGAMATION_DIRECTORY NEW_SDK_DIRECTORY'
	root := os.dir(os.dir(os.dir(@FILE)))
	source := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	assert os.is_dir(source) && !os.is_link(os.args[1]) && !os.exists(out) && !os.is_link(out) && !out.starts_with(source + '/')
	source_lock := json2.decode[SqliteLock](os.read_file(root + '/tests/packages/sqlite-source.json')!)!
	assert source_lock.format == 1 && source_lock.version == '3.53.4'
	for name in ['sqlite3.c', 'sqlite3.h']! {
		item := source_lock.files.filter(it.path == name)
		assert item.len == 1
		path := source + '/' + name
		assert os.is_file(path) && !os.is_link(path) && os.file_size(path) == item[0].bytes
		assert sha256.sum(os.read_bytes(path)!).hex() == item[0].sha256, name
	}
	os.mkdir_all(out + '/source')!
	os.mkdir(out + '/arm64')!
	for name in ['sqlite3.c', 'sqlite3.h']! {
		os.cp(source + '/' + name, out + '/source/' + name)!
		os.chmod(out + '/source/' + name, 0o444)!
	}
	sdk := root + '/build-aarch64-userland/staging'
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
	cc := os.getenv_opt('VINIX_IOS_SQLITE_CLANG') or { '/opt/homebrew/opt/llvm/bin/clang' }
	compile := [cc, '--target=aarch64-linux-musl', '-nostdinc', '-isystem',
		root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
		sdk + '/usr/include', '-O2', '-fPIC', '-ffixed-x18', '-fno-stack-protector',
		'-DSQLITE_OMIT_LOAD_EXTENSION=1', '-DSQLITE_THREADSAFE=1', '-c', out + '/source/sqlite3.c',
		'-o', out + '/arm64/sqlite3.o']
	sqlite_checked(compile)
	archive := ['/opt/homebrew/opt/llvm/bin/llvm-ar', 'rcs', out + '/arm64/libsqlite3.a',
		out + '/arm64/sqlite3.o']
	sqlite_checked(archive)
	mut hashes := map[string]string{}
	for path in [out + '/source/sqlite3.c', out + '/source/sqlite3.h', out + '/arm64/libsqlite3.a',
		cc, '/opt/homebrew/opt/llvm/bin/llvm-ar']! {
		hashes[path] = sha256.sum(os.read_bytes(path)!).hex()
	}
	os.write_file(out + '/commands.json', json2.encode([compile, archive], prettify: true))!
	os.write_file(out + '/sha256.json', json2.encode(hashes, prettify: true))!
	os.write_file(out + '/build.status.txt', '0\n')!
	println('Built pinned SQLite ' + source_lock.version + ' ARM64 backend with x18 reserved and extension loading omitted')
}
