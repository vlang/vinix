// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const shim = 'module main

import os
#include <sys/statvfs.h>
struct C.statvfs {
	f_frsize uint
	f_bavail uint
}

@[export: "vinix_release_fixture_statvfs"]
fn fixture_statvfs(path &char, output &C.statvfs) int {
	available := os.getenv("VINIX_RELEASE_FIXTURE_AVAILABLE")
	if available == "error" || unsafe { tos3(path) } != os.getenv("VINIX_RELEASE_FIXTURE_FILESYSTEM") {
		return -1
	}
	unsafe {
		output.f_frsize = 1
		output.f_bavail = uint(available.u64())
	}
	return 0
}
'

struct FixtureAsset {
	name string
	state string = 'uploaded'
	digest string
}

struct FixtureDraft {
	id u64 = 42
	tag_name string = 'fixture'
	name string = 'Vinix fixture'
	draft bool = true
	prerelease bool
	body string = 'Verified fixture'
	html_url string = 'https://example.invalid/fixture'
	upload_url string = 'https://uploads.github.com/repos/local/fixture/releases/42/assets{?name,label}'
	assets []FixtureAsset
}

fn command(executable string, args []string) (int, string) {
	mut child := os.new_process(executable)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn check(helper string, state string, scenario string, args []string, available string, diagnostic string) ! {
	os.setenv('VINIX_RELEASE_FIXTURE_AVAILABLE', available, true)
	code, output := command(helper, args)
	os.write_file(os.join_path(state, scenario + '.log'), output)!
	if (code == 0) != (diagnostic == '') || !output.contains(diagnostic) {
		return error('unexpected ${scenario} status ${code}\n${output}')
	}
	println('ISO release staging space ${scenario} PASS')
}

fn require_absent(path string) ! {
	if os.exists(path) { return error('unexpected staging output: ' + path) }
}

fn run() ! {
	if os.args.len !in [3, 4]! || (os.args.len == 4 && os.args[3] != '--asan') {
		return error('usage: iso-release-staging-space-check REPOSITORY NEW_STATE [--asan]')
	}
	repository := os.real_path(os.args[1])
	state := os.abs_path(os.args[2])
	os.mkdir(state, mode: 0o700)!
	source := os.join_path(state, 'source')
	os.mkdir(source)!
	header := os.join_path(state, 'fixture.h')
	os.write_file(header, '#include <sys/statvfs.h>\n#define statvfs(...) vinix_release_fixture_statvfs(__VA_ARGS__)\n')!
	os.cp(os.join_path(repository, 'build-support', 'isoboot', 'release-assets.v'), os.join_path(source, 'release-assets.v'))!
	os.write_file(os.join_path(source, 'statvfs.v'), shim)!
	helper := os.join_path(state, 'release-assets')
	mut flags := ['-backend', 'c', '-cc', 'cc', '-nocache', '-path',
		'@vlib|@vmodules|${repository}|${repository}/tools/accounts']
	mut cflags := '-include "${header}"'
	if os.args.len == 4 {
		cflags += ' -O1 -fsanitize=address,undefined -fno-omit-frame-pointer'
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
		os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	} else {
		flags << '-prod'
	}
	flags << ['-cflags', cflags, '-o', helper, source]
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	code, log := command(v, flags)
	os.write_file(os.join_path(state, 'build.log'), log)!
	if code != 0 { return error('cannot compile release-assets with fixture statvfs\n${log}') }

	bin := os.join_path(state, 'empty-bin')
	os.mkdir(bin)!
	os.setenv('PATH', bin, true)
	original := os.join_path(state, 'original')
	os.mkdir(original)!
	a := 'a'.repeat(2048)
	b := 'b'.repeat(2049)
	os.write_file(os.join_path(original, 'a.iso'), a)!
	os.write_file(os.join_path(original, 'b.iso'), b)!
	checksums := '${sha256.hexhash(a)}  a.iso\n${sha256.hexhash(b)}  b.iso\n'
	manifest := os.join_path(state, 'SHA256SUMS')
	os.write_file(manifest, checksums)!
	notes := FixtureDraft{}.body
	os.write_file(os.join_path(state, 'RELEASE_NOTES.md'), notes)!
	filesystem := os.join_path(state, 'staging')
	os.mkdir(filesystem)!
	os.setenv('VINIX_RELEASE_FIXTURE_FILESYSTEM', filesystem, true)
	capture := os.join_path(filesystem, 'capture')
	stage := os.join_path(filesystem, 'upload')
	check(helper, state, 'capture-short', ['capture', original, capture, 'a.iso', 'b.iso'], '4096',
		'4097 bytes needed, 4096 bytes available')!
	require_absent(capture)!
	check(helper, state, 'capture-exact', ['capture', original, capture, 'a.iso', 'b.iso'], '4097', '')!
	if os.read_file(os.join_path(capture, 'a.iso'))! != a
		|| os.read_file(os.join_path(capture, 'b.iso'))! != b {
		return error('capture changed the original contents')
	}
	check(helper, state, 'stage-short', ['stage', original, manifest, stage], '4096',
		'4097 bytes needed, 4096 bytes available')!
	require_absent(stage)!
	os.symlink(os.join_path(original, 'a.iso'), os.join_path(original, 'alias.iso'))!
	check(helper, state, 'capture-alias', ['capture', original, stage, 'a.iso', 'alias.iso'], '4097',
		'release asset must be a regular file')!
	require_absent(stage)!

	first := FixtureAsset{name: 'a.iso', digest: 'sha256:' + sha256.hexhash(a)}
	draft := FixtureDraft{assets: [first]}
	response := os.join_path(state, 'draft.json')
	os.write_file(response, json2.encode(draft))!
	args := ['upload-draft', stage, state, response, 'local/fixture', '42', 'fixture', 'false', original]
	needed := b.len + checksums.len + notes.len
	check(helper, state, 'resume-short', args, (needed - 1).str(),
		'${needed} bytes needed, ${needed - 1} bytes available')!
	require_absent(stage)!
	metadata_bytes := checksums.len + notes.len
	os.setenv('VINIX_RELEASE_FIXTURE_FILESYSTEM', capture, true)
	check(helper, state, 'metadata-short', ['upload-draft', capture, state, response, 'local/fixture',
		'42', 'fixture', 'false', ''], (metadata_bytes - 1).str(),
		'${metadata_bytes} bytes needed, ${metadata_bytes - 1} bytes available')!
	require_absent(os.join_path(capture, 'SHA256SUMS'))!
	require_absent(os.join_path(capture, 'RELEASE_NOTES.md'))!
	os.write_file(response, json2.encode(FixtureDraft{
		...draft
		assets: [first, FixtureAsset{name: 'b.iso', digest: 'sha256:' + sha256.hexhash(b)},
			FixtureAsset{name: 'SHA256SUMS', digest: 'sha256:' + sha256.hexhash(checksums)}]
	}))!
	check(helper, state, 'resume-complete', args, 'error', '')!
	require_absent(stage)!
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
