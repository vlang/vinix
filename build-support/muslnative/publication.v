// SPDX-License-Identifier: GPL-2.0-or-later
module muslnative

import cachecli
import hosttest
import json2
import os
import tarstream
import time

pub fn exports(table string) []string {
	mut names := map[string]bool{}
	for line in table.split_into_lines() {
		parts := line.fields()
		if parts.len >= 8 && parts[4] in ['GLOBAL', 'WEAK'] && parts[6] != 'UND' {
			names[parts[7].all_before('@')] = true
		}
	}
	mut result := names.keys()
	result.sort()
	return result
}

pub fn validate_archive(path string, version string) ! {
	mut reader := tarstream.open(path)!
	defer { reader.close() }
	for {
		cachecli.checkpoint()!
		entry := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		parts := entry.name.split('/').filter(it != '' && it != '.')
		if entry.name.starts_with('/') || parts.len == 0 || parts[0] != 'musl-' + version || '..' in parts || entry.kind in [
			u8(`1`),
			`2`,
		] {
			return error('unsafe musl archive entry: ' + entry.name)
		}
	}
}

fn rebuild(plan Plan, build string, published string) ! {
	archive := plan.options.cache + '/musl-' + plan.version + '.tar.gz'
	if !os.is_file(archive) {
		target := temporary(plan.options.cache + '/musl-download')!
		defer { os.rm(target) or {} }
		captured(['curl', '--fail', '--silent', '--show-error', '--location', '--connect-timeout',
			'60', '--speed-time', '60', '--speed-limit', '1', '--output', target, plan.source_url])!
		if digest(target)! != plan.source_sha { return error('musl release checksum mismatch') }
		replace_file(target, archive)!
	}
	if digest(archive)! != plan.source_sha { return error('musl release checksum mismatch') }
	if os.is_link(build) { return error('unpublished musl build must not be a symlink') }
	if os.exists(build) { os.rmdir_all(build)! }
	parents(build)!
	validate_archive(archive, plan.version)!
	// Validation precedes extraction; the release checksum also pins every byte.
	log := build + '/build.log'
	logged(['tar', '-xf', archive, '-C', build], os.environ(), '', log, false)!
	source := build + '/musl-' + plan.version
	parents(build + '/patches')!
	for patch in plan.patches {
		path := build + '/patches/' + patch.name
		os.write_file_array(path, patch.data)!
		logged(['patch', '--batch', '-p1', '-i', path], os.environ(), source, log, true)!
	}
	if plan.version == '1.2.6' {
		for name in ['memcpy.s', 'memmove.s'] { os.rm(source + '/src/string/x86_64/' + name)! }
	}
	objects := build + '/objects'
	parents(objects)!
	mut env := os.environ()
	for key, value in {
		'CC':      hosttest.shell_join(plan.cc)
		'AR':      plan.ar
		'RANLIB':  plan.ranlib
		'CFLAGS':  plan.cflags
		'LDFLAGS': plan.ldflags
	} {
		env[key] = value
	}
	configure := [source + '/configure', '--target=' + plan.options.arch + '-linux-musl',
		'--prefix=/usr', '--syslibdir=/lib', '--disable-wrapper',
		'--enable-optimize=' + plan.optimization]
	logged(configure, env, objects, log, true)!
	logged(['make', '-j' + plan.options.jobs.str()], env, objects, log, true)!
	mut manifest := plan.manifest.clone()
	manifest['configure_argv'] = configure.map(json2.Any(it))
	manifest['libc_so_sha256'] = digest(objects + '/lib/libc.so')!
	manifest['libc_a_sha256'] = digest(objects + '/lib/libc.a')!
	hosttest.write_json(published, manifest)!
}

fn lock(fd int) ! {
	for C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		if C.errno !in [C.EINTR, C.EWOULDBLOCK, C.EAGAIN] { return os.error_posix() }
		cachecli.checkpoint()!
		time.sleep(20 * time.millisecond)
	}
}

pub fn publish(plan Plan) ! {
	lock_path := plan.options.cache + '/build.lock'
	fd := unsafe { C.open(lock_path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	lock(fd)!
	cachecli.checkpoint()!
	build := plan.options.cache + '/' + plan.options.arch + '/' + plan.key
	published := build + '/build.json'
	if !os.is_file(published) { rebuild(plan, build, published)! }
	objects := build + '/objects'
	cached := hosttest.decode_json(os.read_file(published)!)!.as_map()
	for key, value in plan.manifest {
		if (cached[key] or { json2.Any(json2.Null{}) }) != value {
			return error('cached musl build inputs do not match: ' + key)
		}
	}
	for name, field in {
		'libc.so': 'libc_so_sha256'
		'libc.a':  'libc_a_sha256'
	} {
		path := objects + '/lib/' + name
		if digest(path)! != (cached[field] or { json2.Any('') }).str() {
			return error('cached musl library checksum mismatch: ' + path)
		}
	}
	readelf := captured([...plan.cc, '-print-prog-name=readelf'])!.trim_space()
	loader := plan.options.stage + '/lib/ld-musl-' + plan.options.arch + '.so.1'
	existing := exports(captured([readelf, '--dyn-syms', '--wide', loader])!)
	rebuilt := exports(captured([readelf, '--dyn-syms', '--wide', objects + '/lib/libc.so'])!)
	missing := existing.filter(it !in rebuilt)
	if missing.len > 0 {
		return error('rebuilt libc would remove existing exports: ' + missing.join(', '))
	}
	mut required_set := map[string]bool{}
	for name in plan.options.required_exports { if name !in rebuilt { required_set[name] = true } }
	mut required := required_set.keys()
	required.sort()
	if required.len > 0 {
		return error('rebuilt libc lacks required runtime exports: ' + required.join(', '))
	}
	install(objects + '/lib/libc.so', loader, 0o755)!
	replace_link(plan.options.stage + '/lib/libc.musl-' + plan.options.arch + '.so.1', 'ld-musl-' + plan.options.arch + '.so.1')!
	if os.is_file(plan.options.stage + '/usr/include/stdlib.h') {
		install(objects + '/lib/libc.a', plan.options.stage + '/usr/lib/libc.a', 0o644)!
		install(build + '/musl-' + plan.version + '/include/malloc.h', plan.options.stage + '/usr/include/malloc.h', 0o644)!
		replace_link(plan.options.stage + '/usr/lib/libc.so', '../../lib/ld-musl-' + plan.options.arch + '.so.1')!
	}
	install(published, plan.options.stage + '/usr/share/vinix/musl-build.json', 0o644)!
	install(build + '/musl-' + plan.version + '/COPYRIGHT', plan.options.stage + '/usr/share/licenses/musl/COPYRIGHT', 0o644)!
	println('    staged Vinix musl ' + plan.version + ' (' + plan.options.arch + ', retention=' + plan.retain + ', ' + plan.key[..12] + ')')
}
