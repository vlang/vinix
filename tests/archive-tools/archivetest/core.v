// SPDX-License-Identifier: GPL-2.0-only
module archivetest

import archivehost
import hosttest
import json2
import os
import tarcore
import tarstream
import time

#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

fn C.flock(int, int) int
fn C.utimensat(int, &char, &C.timespec, int) int
fn C.kill(int, int) int

fn command(kind string, args []string) []string {
	if directory := os.getenv_opt('VINIX_ARCHIVE_TOOLS_DIR') {
		name := match kind {
			'parts' { 'split-qemu-initramfs' }
			'desktop' { 'split-desktop-initramfs' }
			else { 'build-qemu-module-iso' }
		}
		return [directory + '/' + name, ...args]
	}
	return [os.executable(), '--worker', kind, ...args]
}

fn invoke(kind string, args []string) !hosttest.Result {
	return hosttest.capture(command(kind, args), '', 60, os.environ())
}

fn success(kind string, args []string) !hosttest.Result {
	result := invoke(kind, args)!
	if result.code != 0 { return error(result.stderr) }
	return result
}

fn tar(args []string) !string {
	result := hosttest.capture(['tar', ...args], '', 60, os.environ())!
	if result.code != 0 { return error(result.stderr) }
	return result.stdout
}

fn files(path string, count int, directory bool) ! {
	mut writer := tarcore.create_stream(path)!
	defer { writer.close() }
	if directory { writer.add(tarcore.Member{ name: 'root/', kind: `5`, mode: 0o755 }, []u8{})! }
	for index in 0 .. count {
		name := if directory { 'root/file-${index}' } else { 'file-${index}' }
		byte := u8(65 + index)
		writer.add(tarcore.Member{ name: name, size: 6000 }, []u8{len: 6000, init: byte})!
	}
	writer.finish()!
}

fn no_temps(path string, prefix string) ! {
	assert os.ls(path)!.filter(it.starts_with(prefix) && !it.ends_with('.lock')).len == 0
}

fn concurrent(kind string, args []string) ! {
	argv := command(kind, args)
	mut first := os.new_process(argv[0])
	mut second := os.new_process(argv[0])
	defer {
		first.close()
		second.close()
	}
	first.set_args(argv[1..])
	first.set_redirect_stdio()
	second.set_args(argv[1..])
	second.set_redirect_stdio()
	first.run()
	second.run()
	first.wait()
	second.wait()
	assert first.code == 0, first.stderr_slurp()
	assert second.code == 0, second.stderr_slurp()
}

fn precise_time(path string, nanoseconds i64) ! {
	times := [C.timespec{ tv_sec: 1234567890, tv_nsec: nanoseconds },
		C.timespec{ tv_sec: 1234567890, tv_nsec: nanoseconds }]!
	if unsafe { C.utimensat(C.AT_FDCWD, path.str, &times[0], 0) } != 0 { return os.error_posix() }
}

fn check_lock(kind string, work string) ! {
	// Hold the exact production lock, then start a producer and observe it waiting.
	source := work + '/locked.tar'
	files(source, 1, false)!
	cache := work + '/locked-parts'
	base := work + '/locked-base.tar'
	seed := work + '/locked-seed.gz'
	manifest := work + '/locked-receipt.json'
	iso := work + '/locked.iso'
	args := match kind {
		'parts' { [source, cache, '--max-bytes', '20480'] }
		'desktop' { [source, base, seed, manifest] }
		else { [source, iso] }
	}
	if kind == 'iso' && os.find_abs_path_of_executable('xorriso') == none { return }
	if kind == 'parts' { os.mkdir(cache)! }
	lock_path := match kind {
		'parts' { cache + '/.lock' }
		'desktop' { work + '/.locked-receipt.json.lock' }
		else { work + '/.locked.iso.lock' }
	}
	mut held := os.open_file(lock_path, 'a+')!
	defer { held.close() }
	assert C.flock(held.fd, C.LOCK_EX) == 0
	argv := [os.executable(), '--worker', kind, ...args]
	ready := work + '/worker-ready'
	mut env := os.environ()
	env['VINIX_ARCHIVE_WORKER_READY'] = ready
	mut child := os.new_process(argv[0])
	defer {
		if child.is_alive() {
			C.kill(child.pid, 9)
			child.wait()
		}
		child.close()
	}
	child.set_args(argv[1..])
	child.set_environment(env)
	child.set_redirect_stdio()
	child.run()
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for !os.exists(ready) && child.is_alive() && time.sys_mono_now() < deadline {
		time.sleep(time.millisecond)
	}
	assert os.exists(ready)
	time.sleep(50 * time.millisecond)
	assert child.is_alive(), child.stderr_slurp()
	assert !os.exists(if kind == 'parts' {
		cache + '/manifest.json'
	} else if kind == 'desktop' {
		manifest
	} else {
		iso
	})
	assert C.flock(held.fd, C.LOCK_UN) == 0
	for child.is_alive() && time.sys_mono_now() < deadline { time.sleep(time.millisecond) }
	assert !child.is_alive()
	child.wait()
	assert child.code == 0, child.stderr_slurp()
}

fn check_parts(work string) ! {
	source := work + '/source.tar'
	cache := work + '/parts'
	args := [source, cache, '--max-bytes', '20480']
	files(source, 5, true)!
	first := success('parts', args)!
	parts := first.stdout.trim_space().split_into_lines()
	assert parts.len == 5 && first.stderr.contains('Splitting')
	mut names := []string{}
	for index, part in parts {
		assert os.file_size(part) <= 20480
		names << tar(['-tf', part])!.trim_space().split_into_lines()
		assert tar(['-xOf', part, 'root/file-${index}'])! == rune(65 + index).str().repeat(6000)
	}
	assert names == ['root/', 'root/file-0', 'root/file-1', 'root/file-2', 'root/file-3', 'root/file-4']
	second := success('parts', args)!
	assert second.stdout == first.stdout && second.stderr == ''
	// Cleanup must unlink obsolete symlinks and preserve unrelated files/directories.
	os.write_file(cache + '/other.tar', 'keep')!
	os.mkdir(work + '/outside')!
	os.write_file(work + '/outside/keep.tar', 'keep outside')!
	os.symlink(work + '/outside', cache + '/part-999.tar')!
	os.mkdir(cache + '/part-888.tar')!
	files(source, 1, false)!
	shrunk := success('parts', args)!
	assert shrunk.stdout.trim_space() == parts[0]
	for old in parts[1..] {
		assert !os.exists(old)
	}
	assert !os.is_link(cache + '/part-999.tar') && os.is_dir(cache + '/part-888.tar')
	assert os.read_file(cache + '/other.tar')! == 'keep'
	assert os.read_file(work + '/outside/keep.tar')! == 'keep outside'
	manifest := cache + '/manifest.json'
	old_manifest := os.read_file(manifest)!
	old_part := os.read_bytes(parts[0])!
	for payload in ['invalid tar', '\x00'.repeat(10240)] {
		os.write_file(source, payload)!
		failed := invoke('parts', args)!
		assert failed.code == 1
		assert os.read_file(manifest)! == old_manifest && os.read_bytes(parts[0])! == old_part
		no_temps(cache, '.parts.')!
	}
	mut writer := tarcore.create_stream(source)!
	writer.add(tarcore.Member{ name: 'large', size: 12000 }, []u8{len: 12000})!
	writer.finish()!
	writer.close()
	oversized := invoke('parts', args)!
	assert oversized.code == 1 && oversized.stderr.contains('tar member exceeds module limit: large')
	assert os.read_file(manifest)! == old_manifest && os.read_bytes(parts[0])! == old_part
	no_temps(cache, '.parts.')!
	files(source, 3, false)!
	os.write_file(manifest, '{"identity":null,"parts":[17]}')!
	concurrent('parts', args)!
	current := success('parts', args)!
	assert current.stderr == '' && current.stdout.trim_space().split_into_lines().len == 3
	// An exact receipt above 2^53 must round-trip and cache without rebuilding.
	saved := hosttest.decode_json(os.read_file(manifest)!)!
	assert saved is map[string]json2.Any
	identity := saved['identity'] or { panic('missing identity') }
	mut expected := archivehost.source_identity(source)!
	expected['max_bytes'] = u64(20480)
	assert identity == json2.Any(expected)
	assert success('parts', args)!.stderr == ''
	precise_time(source, 987654320)!
	changed_time := success('parts', args)!
	assert changed_time.stderr.contains('Splitting'), json2.encode(archivehost.source_identity(source)!) + changed_time.stdout
	assert success('parts', args)!.stderr == ''
	precise_time(source, 987654321)!
	changed_tick := success('parts', args)!
	assert changed_tick.stderr.contains('Splitting'), json2.encode(archivehost.source_identity(source)!) + changed_tick.stdout
	assert success('parts', args)!.stderr == ''
	check_lock('parts', work)!
	// In-process repeated owners must release archive streams, descriptors and locks.
	fd_dir := if os.is_dir('/proc/self/fd') { '/proc/self/fd' } else { '/dev/fd' }
	before_fds := os.ls(fd_dir)!.len
	for _ in 0 .. 64 {
		assert archivehost.qemu_split(source, cache, 20480)!.len == 3
	}
	for index in 0 .. 8 {
		os.write_file(source, 'invalid ${index}')!
		archivehost.qemu_split(source, cache, 20480) or { continue }
		assert false
	}
	assert os.ls(fd_dir)!.len == before_fds
	no_temps(cache, '.parts.')!
}

fn check_desktop(work string) ! {
	source := work + '/desktop.tar'
	base := work + '/base.tar'
	seed := work + '/root.tar.gz'
	manifest := work + '/receipt.json'
	args := [source, base, seed, manifest]
	large := 'office'.repeat(400000)
	mut writer := tarcore.create_stream(source)!
	writer.add(tarcore.Member{ name: './root/', kind: `5`, mode: 0o700, uid: 12, gid: 34, mtime: 123 }, []u8{})!
	writer.add(tarcore.Member{ name: './root/.wine/', kind: `5` }, []u8{})!
	writer.add(tarcore.Member{ name: './root/.wine/state', mode: 0o640, uid: 12, gid: 34, mtime: 123, size: large.len }, large.bytes())!
	writer.add(tarcore.Member{ name: './root/hard', kind: `1`, linkname: './root/.wine/state' }, []u8{})!
	writer.add(tarcore.Member{ name: './root/link', kind: `2`, linkname: '../usr/bin/app' }, []u8{})!
	writer.add(tarcore.Member{ name: './usr/bin/app', size: 4 }, 'base'.bytes())!
	writer.finish()!
	writer.close()
	result := success('desktop', args)!
	assert result.stdout.contains('(4 root entries, 2400000 bytes)')
	assert tar(['-tf', base])!.trim_space().split_into_lines() == ['./root/', './usr/bin/app']
	assert tar(['-xOf', base, './usr/bin/app'])! == 'base'
	assert tar(['-tf', seed])!.trim_space().split_into_lines() == ['.wine/', '.wine/state', 'hard',
		'link']
	assert tar(['-xOf', seed, '.wine/state'])! == large
	gzip := os.read_bytes(seed)!
	assert gzip[..4] == [u8(31), 139, 8, 0] && gzip[4..8] == [u8(0), 0, 0, 0]
	mut input := tarstream.open(seed)!
	assert input.next()!.name == '.wine'
	state := input.next()!
	assert state.mode == 0o640 && state.uid == 12 && state.gid == 34 && state.mtime == 123
	hard := input.next()!
	assert hard.kind == `1` && hard.linkname == '.wine/state'
	link := input.next()!
	assert link.kind == `2` && link.linkname == '../usr/bin/app'
	input.close()
	mut root := tarstream.open_plain(base)!
	marker := root.next()!
	assert marker.mode == 0o700 && marker.uid == 12 && marker.gid == 34
	root.close()
	identity := archivehost.source_identity(source)!
	assert archivehost.cache_matches(manifest, identity, [base, seed])
	before := hosttest.bounds_file_state(seed)!
	assert success('desktop', args)!.stdout.starts_with('QEMU storage images are current:')
	assert hosttest.bounds_file_state(seed)! == before
	os.rm(seed)!
	assert !archivehost.cache_matches(manifest, identity, [base, seed])
	assert success('desktop', args)!.stdout.starts_with('Split desktop initramfs:')
	old_base := os.read_bytes(base)!
	old_seed := os.read_bytes(seed)!
	old_manifest := os.read_file(manifest)!
	for name in ['../escape', '/escape', './root/../escape'] {
		mut unsafe_tar := tarcore.create_stream(source)!
		unsafe_tar.add(tarcore.Member{ name: name }, []u8{})!
		unsafe_tar.finish()!
		unsafe_tar.close()
		failed := invoke('desktop', args)!
		assert failed.code == 1 && failed.stderr.contains('unsafe archive member')
		assert os.read_bytes(base)! == old_base && os.read_bytes(seed)! == old_seed
		assert os.read_file(manifest)! == old_manifest
		no_temps(work, '.base.tar.')!
		no_temps(work, '.root.tar.gz.')!
	}
	// A missing mountpoint is synthesized, and uncompressed input is enforced.
	files(source, 1, false)!
	empty_root := success('desktop', args)!
	assert empty_root.stdout.contains('(0 root entries, 0 bytes)'), empty_root.stdout
	assert tar(['-tf', base])!.trim_space().split_into_lines() == ['file-0', './root/']
	compressed := work + '/compressed.tar.gz'
	gz := hosttest.capture(['/bin/sh', '-c', 'exec gzip -n -c "$1" > "$2"', 'compress-test', source,
		compressed], '', 60, os.environ())!
	assert gz.code == 0
	assert invoke('desktop', [compressed, base, seed, manifest])!.code == 1
	concurrent('desktop', args)!
	check_lock('desktop', work)!
}

fn fake_xorriso() ! {
	index := os.args.index('-o')
	assert index > 0 && index + 1 < os.args.len
	source := os.args.last().all_after('boot/initramfs.tar=')
	mode := os.getenv('VINIX_FAKE_ISO_MODE')
	if mode == 'fail' {
		eprintln('fixture xorriso failed')
		exit(17)
	}
	if mode == 'changed' { os.write_file(source, 'changed during build')! }
	os.write_file(os.args[index + 1], if mode == 'small' { '' } else { 'iso'.repeat(10000) })!
}

fn check_iso(work string) ! {
	source := work + '/initramfs.tar'
	output := work + '/module.iso'
	args := [source, output]
	os.write_file(source, 'first archive\n')!
	if xorriso := os.find_abs_path_of_executable('xorriso') {
		first := success('iso', args)!
		assert first.stdout.trim_space() == output && first.stderr.contains('Building ISO9660')
		before := hosttest.bounds_file_state(output)!
		assert success('iso', args)!.stderr == ''
		check_lock('iso', work)!
		assert hosttest.bounds_file_state(output)! == before
		extracted := work + '/extracted.tar'
		result := hosttest.capture([xorriso, '-osirrox', 'on', '-indev', output, '-extract',
			'/boot/initramfs.tar', extracted], '', 60, os.environ())!
		assert result.code == 0, result.stderr
		assert os.read_bytes(extracted)! == os.read_bytes(source)!
		os.write_file(source, 'second archive\n')!
		concurrent('iso', args)!
		assert hosttest.bounds_file_state(output)! != before
		assert success('iso', args)!.stderr == ''
	} else {
		println('SKIP real ISO extraction: xorriso is not installed')
	}
	// The fake builder is this V executable: failures must retain the old cache.
	os.write_file(output, 'old ISO')!
	os.write_file(output + '.json', 'old manifest')!
	old_path := os.getenv('PATH')
	defer {
		os.setenv('PATH', old_path, true)
		os.unsetenv('VINIX_FAKE_ISO_MODE')
	}
	os.mkdir(work + '/bin')!
	os.symlink(os.executable(), work + '/bin/xorriso')!
	os.setenv('PATH', work + '/bin:' + old_path, true)
	for mode in ['fail', 'small', 'changed'] {
		os.setenv('VINIX_FAKE_ISO_MODE', mode, true)
		failed := invoke('iso', args)!
		assert failed.code == 1
		assert failed.stderr.contains(match mode {
			'fail' { 'xorriso failed:\nfixture xorriso failed' }
			'small' { 'ISO is smaller than its initramfs' }
			else { 'initramfs changed while building the ISO' }
		})
		assert os.read_file(output)! == 'old ISO' && os.read_file(output + '.json')! == 'old manifest'
		no_temps(work, '.module.iso.')!
	}
	os.setenv('PATH', work + '/bin', true)
	os.rm(work + '/bin/xorriso')!
	assert invoke('iso', args)!.code == 2
}

fn check_cli(kind string, work string) ! {
	assert invoke(kind, ['--help'])!.code == 0
	assert invoke(kind, ['--bogus'])!.code == 2
	assert invoke(kind, []string{})!.code == 2
	if kind == 'parts' {
		for value in ['nan', '20479', '4294967296', '9999999999999999999999999'] {
			assert invoke(kind, ['unused', work + '/unused', '--max-bytes', value])!.code == 2
		}
		assert !os.exists(work + '/unused')
	} else if kind == 'iso' {
		source := work + '/same.tar'
		os.write_file(source, 'source')!
		assert invoke(kind, [source, work + '/./same.tar'])!.code == 2
		assert os.read_file(source)! == 'source'
	}
}

// Each test entry can exercise the exact production CLI in a child process.
pub fn run(kind string) {
	if os.file_name(os.args[0]) == 'xorriso' {
		fake_xorriso() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len >= 3 && os.args[1] == '--worker' {
		if ready := os.getenv_opt('VINIX_ARCHIVE_WORKER_READY') {
			os.write_file(ready, 'ready') or { panic(err) }
		}
		archivehost.run(os.args[2], os.args[3..])
		return
	}
	check(kind) or {
		eprintln(err)
		exit(1)
	}
	println('PASS native ${kind} archive checks')
}

fn check(kind string) ! {
	work := hosttest.resolve_path(hosttest.work_dir('', 'vinix-archive-${kind}-')!)!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	check_cli(kind, work)!
	match kind {
		'parts' { check_parts(work)! }
		'desktop' { check_desktop(work)! }
		else { check_iso(work)! }
	}
}
