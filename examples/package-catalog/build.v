// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgcore

struct Artifact {
	path string
	bytes u64
	sha256 string
}

struct Build {
	format int = 1
	profile string = 'native-sdk'
	version string
	compiler string
	artifacts []Artifact
	catalog_sha256 string
}

fn command(program string, arguments []string) ! {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed (${code})') }
}

fn build(version string, destination string) ! {
	pkgcore.version_parts(version)!
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut compilers := map[string]string{}
	for architecture in ['aarch64', 'x86_64'] {
		compilers[architecture] = os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!
	}
	output := os.abs_path(destination)
	if os.exists(output) || os.is_link(output) { return error('native SDK build output must be new') }
	// Reserve a private output exclusively; remove this build's partial results
	// on failure. No signing key, repository enrollment or network is involved.
	os.mkdir(output, mode: 0o700)!
	mut completed := false
	defer { if !completed { os.rmdir_all(output) or {} } }
	for architecture in ['aarch64', 'x86_64'] {
		root := output + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/licenses')!
		os.cp(repository + '/tools/packages/appsdk/LICENSE', root + '/licenses/application-sdk-MIT.txt')!
		os.cp(os.dir(v) + '/LICENSE', root + '/licenses/v-MIT.txt')!
		os.cp(os.getenv_opt('VINIX_MUSL_COPYRIGHT') or { repository + '/build-support/musl/COPYRIGHT' }, root + '/licenses/musl-MIT.txt')!
		for example in ['hello', 'counter', 'memo'] {
			name := if example == 'hello' { 'package-hello' } else { example }
			c_file := output + '/' + architecture + '-' + name + '.c'
			command(v, ['-nocache', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository,
				'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
				if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', c_file,
				repository + '/examples/package-' + example + '/main.v'])!
			command(compilers[architecture], ['-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', c_file,
				'-o', root + '/bin/' + name, '-lm', '-lpthread'])!
			os.rm(c_file)!
		}
	}
	profile := pkgcore.native_catalog(version, output + '/roots', output + '/lock')!
	pkgcore.pack_catalog(profile.catalog, output + '/roots', output + '/workspace')!
	mut paths := os.walk_ext(output + '/roots', '')
	paths << v
	for _, compiler in compilers { paths << compiler }
	paths.sort()
	mut artifacts := []Artifact{}
	for path in paths {
		if !os.is_file(path) { continue }
		bytes := os.read_bytes(path)!
		artifacts << Artifact{ path: if path.starts_with(output + '/') { path[output.len + 1..] } else { path },
			bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
		unsafe { bytes.free() }
	}
	os.write_file(output + '/build.json', json2.encode(Build{ version: version, compiler: v, artifacts: artifacts,
		catalog_sha256: profile.catalog_sha256 }) + '\n')!
	completed = true
	println('Native SDK catalog is ready for review/signing: ' + output + '/workspace')
}

fn main() {
	if os.args.len != 3 { eprintln('usage: v run examples/package-catalog/build.v VERSION NEW_BUILD_DIRECTORY'); exit(2) }
	build(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
