// SPDX-License-Identifier: GPL-2.0-or-later
module tlsbuild

import os
import crypto.sha256

#include <sys/file.h>
fn C.flock(int, int) int

pub fn includes(vroot string) []string {
	base := vroot + '/thirdparty/mbedtls/'
	return ['-I' + base + 'library', '-I' + base + 'include',
		'-I' + base + '3rdparty/everest/include', '-I' + base + '3rdparty/everest/include/everest',
		'-I' + base + '3rdparty/everest/include/everest/kremlib']
}

fn checked(out string, label string, args []string) {
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.set_work_folder(out); p.set_redirect_stdio_merged()
	p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(out + '/' + label + '.log', args.map(os.quoted_path(it)).join(' ') + '\n' + output) or { panic(err) }
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n') or { panic(err) }
	if code != 0 { panic('TLS build failed: ' + out + '/' + label + '.log') }
}

fn archive_matches(archiver string, archive string, objects []string) bool {
	listing := os.exec([archiver, 't', archive])
	if listing.exit_code != 0 { return false }
	// Apple's ar also lists its symbol-table member.
	mut members := listing.output.split_into_lines().filter(it.ends_with('.o'))
	mut expected := objects.map(os.file_name(it))
	members.sort(); expected.sort()
	return members == expected
}

// Use the same pinned source list as normal V builds. Keep cross and sanitizer
// objects in the caller's external output directory, never in the toolchain.
pub fn build(root string, vroot string, out string, compiler []string) string {
	deps := os.read_file(root + '/compat/ios/iostls/deps.c.v') or { panic(err) }
	// VM builds run several compiler jobs concurrently. Separate incompatible
	// configurations and serialize identical builds without replacing an archive
	// that another job might already be linking.
	mut digest := sha256.new()
	digest.write((compiler.join('\x00') + '\x00' + deps).bytes()) or { panic(err) }
	helper := os.read_file(root + '/tests/ios/tlsbuild/tlsbuild.v') or { panic(err) }
	digest.write(helper.bytes()) or { panic(err) }
	base := vroot + '/thirdparty/mbedtls'
	mut files := os.walk_ext(base, '.c')
	files << os.walk_ext(base, '.h')
	files.sort()
	for file in files {
		contents := os.read_bytes(file) or { panic(err) }
		digest.write(file.bytes()) or { panic(err) }
		digest.write(sha256.sum(contents)) or { panic(err) }
		unsafe { contents.free() }
	}
	dir := os.abs_path(out) + '/tls/' + digest.sum([]u8{}).hex()
	os.mkdir_all(dir) or { panic(err) }
	mut build_lock := os.open_file(dir + '/build.lock', 'a', 0o600) or { panic(err) }
	defer { C.flock(build_lock.fd, C.LOCK_UN); build_lock.close() }
	if C.flock(build_lock.fd, C.LOCK_EX) != 0 { panic('cannot lock TLS build') }
	archive := dir + '/libios-tls.a'
	mut compile := compiler.clone()
	compile << ['-O1', '-w', '-c']; compile << includes(vroot)
	mut objects := []string{}
	for line in deps.split_into_lines() {
		if !line.starts_with('#flag @VEXEROOT/') || !line.ends_with('.o') { continue }
		path := line.all_after('#flag @VEXEROOT/').replace('.o', '.c')
		compile << vroot + '/' + path
		objects << dir + '/' + os.file_name(path).replace('.c', '.o')
	}
	if objects.len < 100 { panic('incomplete bundled TLS source list') }
	llvm_ar := os.dir(compiler[0]) + '/llvm-ar'
	// Apple's ar can silently discard ELF members while returning success.
	archiver := if os.exists(llvm_ar) { llvm_ar } else { '/usr/bin/ar' }
	archive_status := os.read_file(dir + '/archive.status.txt') or { '' }
	if os.exists(archive) && archive_status == '0\n' && archive_matches(archiver, archive, objects) { return archive }
	checked(dir, 'compile', compile)
	// Remove stale archive members when the pinned source list changes.
	if os.exists(archive) { os.rm(archive) or { panic(err) } }
	mut args := [archiver, 'rcs', archive]; args << objects
	checked(dir, 'archive', args)
	if !archive_matches(archiver, archive, objects) {
		panic('incomplete TLS archive: ' + archive)
	}
	return archive
}
