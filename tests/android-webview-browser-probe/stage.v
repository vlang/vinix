// SPDX-License-Identifier: GPL-2.0-or-later
// Append an audited diagnostic module to disposable APFS media clones.
module main

import crypto.sha256
import json2
import modulestream
import os
import tarcore
import tarstream
import time

#include <sys/clonefile.h>
#include <signal.h>
fn C.clonefile(&char, &char, int) int
fn C.kill(int, int) int

const overlay_name = 'browser-probe.tar'
const browser_prefix = 'opt/vinix-browser-probe'
const fixture_prefix = 'opt/vinix-account-authority-fixture'

struct Entry {
	name     string
	kind     string
	mode     u32
	size     u64
	sha256   string
	linkname string
}

struct Config {
	modules []string
	updated string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn safe_name(name string) bool {
	return name != '' && name !in ['.', '..'] && name.len <= 255
		&& name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`])
}

fn configure(original string) !Config {
	if original == '' || original.contains_any('\x00\r') {
		return error('expected an LF-delimited Limine configuration')
	}
	mut modules := []string{}
	mut indent := ''
	mut entries := 0
	for line in original.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('/') || trimmed.starts_with(':') {
			entries++
		}
		if !trimmed.starts_with('module_path:') { continue }
		if entries != 1 || !trimmed.starts_with('module_path: boot():/boot/') {
			return error('unsupported or ambiguous Limine module path')
		}
		name := trimmed.all_after('module_path: boot():/boot/')
		if !safe_name(name) || !name.ends_with('.tar') || name == overlay_name
			|| name in modules {
			return error('unsafe, duplicate, non-tar or existing overlay module: ' + name)
		}
		prefix := line[..line.len - line.trim_left(' \t').len]
		if prefix == '' || (indent != '' && indent != prefix) {
			return error('Limine module indentation is ambiguous')
		}
		indent = prefix
		modules << name
	}
	if entries != 1 || modules.len == 0 { return error('exactly one populated Limine entry required') }
	separator := if original.ends_with('\n') { '' } else { '\n' }
	return Config{modules, original + separator + indent + 'module_path: boot():/boot/' + overlay_name + '\n'}
}

fn normalize(name string) !string {
	if name.starts_with('/') || name.contains_any('\x00\n\r\\') {
		return error('unsafe archive name: ' + name)
	}
	mut clean := name
	for clean.starts_with('./') { clean = clean[2..] }
	clean = clean.trim_right('/')
	if clean == '.' || clean == '' { return '' }
	if clean.split('/').any(it in ['', '.', '..']) { return error('unsafe archive name: ' + name) }
	return clean
}

fn collision(member tarcore.Member, prefixes []string) ! {
	name := normalize(member.name)!
	if name == 'opt' && member.kind != `5` {
		return error('original module supplies a non-directory opt ancestor')
	}
	for prefix in prefixes {
		if name == prefix || name.starts_with(prefix + '/') {
			return error('original module already contains diagnostic destination: ' + name)
		}
	}
}

fn command(root string, label string, argv []string) !string {
	return command_expected(root, label, argv, 0)
}

fn command_expected(root string, label string, argv []string, expected int) !string {
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 2 * 1024 * 1024 { return error('oversized command output: ' + label) }
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline { return error('command deadline: ' + label) }
		time.sleep(10 * time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 2 * 1024 * 1024 { return error('oversized command output: ' + label) }
	}
	child.wait()
	finished = true
	os.write_file(root + '/commands/' + label + '.json', json2.encode({
		'argv': json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout': json2.Any(stdout)
		'stderr': json2.Any(stderr)
	}, prettify: true))!
	if child.code != expected { return error(label + ' unexpected exit ' + child.code.str() + ': ' + stderr) }
	return stdout
}

// Parse tar directly from mcopy's pipe. Do not extract or retain original modules.
fn check_module(mcopy string, image string, name string, prefixes []string) ! {
	mut child := os.new_process(mcopy)
	child.use_pgroup = true
	child.set_args(['-i', image, '::/boot/' + name, '-'])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut archive := tarstream.from_descriptor(i32(child.stdio_fd[1]))!
	defer { archive.close() }
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		collision(member, prefixes)!
	}
	// Tar stops at the first zero block; consume the producer's remaining padding.
	mut stderr := ''
	for {
		child.stdout_read()
		stderr += child.stderr_read()
		if stderr.len > 1024 * 1024 { return error('oversized mcopy diagnostics') }
		if !child.is_alive() { break }
		time.sleep(time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stderr += err
		if stderr.len > 1024 * 1024 { return error('oversized mcopy diagnostics') }
	}
	child.wait()
	finished = true
	if child.code != 0 { return error('collision scan mcopy failed: ' + stderr) }
}

fn inventory(root string, relative string, prefix string, mut result []Entry) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	stat := os.lstat(path)!
	name := if relative == '' { prefix } else { prefix + '/' + relative }
	mode := stat.mode & 0o7777
	match stat.get_filetype() {
		.directory {
			result << Entry{name: name, kind: 'directory', mode: mode}
			mut children := os.ls(path)!
			children.sort()
			for child in children {
				if child.contains_any('\x00\n\r\\') { return error('unsafe bundle filename') }
				next := if relative == '' { child } else { relative + '/' + child }
				inventory(root, next, prefix, mut result)!
			}
		}
		.regular {
			result << Entry{name: name, kind: 'regular', mode: mode, size: stat.size, sha256: hash(path)!}
		}
		.symbolic_link {
			target := os.readlink(path)!
			if target == '' || target.contains_any('\x00\n\r') { return error('unsafe bundle symlink') }
			result << Entry{name: name, kind: 'symlink', mode: mode, linkname: target}
		}
		else { return error('unsupported bundle inode: ' + name) }
	}
}

fn write_overlay(path string, roots map[string]string, entries []Entry) ! {
	mut writer := tarcore.create_stream(path)!
	defer { writer.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for entry in entries {
		member := tarcore.Member{
			name: entry.name
			mode: i64(entry.mode)
			size: if entry.kind == 'regular' { i64(entry.size) } else { 0 }
			kind: match entry.kind { 'directory' { u8(`5`) } 'symlink' { u8(`2`) } else { u8(`0`) } }
			linkname: entry.linkname
		}
		writer.write(tarcore.header(member)!)!
		if entry.kind == 'regular' {
			mut source := ''
			for prefix, root in roots {
				if entry.name.starts_with(prefix + '/') { source = root + entry.name[prefix.len..] }
			}
			if source == '' { return error('overlay entry has no source') }
			mut file := os.open(source)!
			mut remaining := entry.size
			for remaining > 0 {
				mut part := unsafe { buffer[..int(if remaining < u64(buffer.len) { remaining } else { u64(buffer.len) })] }
				n := file.read(mut part) or { file.close(); return err }
				if n == 0 { file.close(); return error('bundle file truncated') }
				writer.write(part[..n])!
				remaining -= u64(n)
			}
			file.close()
		}
		writer.padding(member.size)!
	}
	writer.finish()!
	writer.close_checked()!
}

fn verify_overlay(path string, expected []Entry) ! {
	mut reader := tarstream.open_plain(path)!
	defer { reader.close() }
	mut actual := []Entry{}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		kind := if member.regular() { 'regular' } else if member.kind == `5` { 'directory' } else if member.kind == `2` { 'symlink' } else { return error('unexpected overlay inode') }
		actual << Entry{
			name: normalize(member.name)!
			kind: kind
			mode: u32(member.mode) & 0o7777
			size: u64(member.size)
			sha256: if member.regular() { reader.digest()! } else { '' }
			linkname: member.linkname
		}
	}
	if actual != expected { return error('overlay readback inventory differs') }
}

fn module_hash(root string, label string, image string, name string) !string {
	result := modulestream.hash_member(image, name, root + '/commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 {
		return error('module hash stream failed: ' + name)
	}
	return result.sha256
}

fn external(path string) !string {
	requested := os.abs_path(path)
	if !os.is_dir(os.dir(requested)) { return error('output parent directory must exist') }
	absolute := os.real_path(os.dir(requested)) + '/' + os.file_name(requested)
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if absolute == repo || absolute.starts_with(repo + '/') || absolute.contains_any('\x00\n\r') {
		return error('fresh output must be outside the repository')
	}
	if os.exists(absolute) || os.is_link(absolute) { return error('fresh output required') }
	return absolute
}

fn stage() ! {
	if os.args.len !in [5, 6] {
		return error('usage: stage BASE_BOOT BASE_EFIVARS PREPARED_BUNDLE FRESH_OUTPUT [AUTHORITY_FIXTURE_DIR]')
	}
	$if !macos { return error('staging requires macOS APFS clonefile') }
	boot := os.real_path(os.args[1])
	efivars := os.real_path(os.args[2])
	bundle := os.real_path(os.args[3])
	root := external(os.args[4])!
	if !os.is_file(boot) || !os.is_file(efivars) || !os.is_dir(bundle)
		|| !os.is_file(bundle + '/build.json') || !os.is_file(bundle + '/addon-files.json') {
		return error('expected base media and a prepared browser bundle')
	}
	mut roots := {browser_prefix: bundle}
	if os.args.len == 6 {
		fixture := os.real_path(os.args[5])
		if !os.is_dir(fixture) { return error('authority fixture directory required') }
		roots[fixture_prefix] = fixture
	}
	mut entries := []Entry{}
	mut prefixes := roots.keys()
	prefixes.sort()
	for prefix in prefixes { inventory(roots[prefix], '', prefix, mut entries)! }
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mtype := os.find_abs_path_of_executable('mtype')!
	mdir := os.find_abs_path_of_executable('mdir')!
	shasum := '/usr/bin/shasum'
	// modulestream uses mcopy by basename; pin its first PATH resolution too.
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	mut inputs := map[string]string{}
	for path in [boot, efivars, mcopy, mtype, mdir, shasum, '/usr/bin/git', os.executable()] { inputs[path] = hash(path)! }
	os.mkdir_all(root + '/commands')!
	os.mkdir(root + '/sources')!
	for path in [@FILE, 'build-support/tarcore/writer.v', 'build-support/tarcore/gzip.v',
		'build-support/tarstream/reader.v', 'build-support/tarstream/filter_abi.h',
		'build-support/tarstream/sparse.v',
		'build-support/android/modulestream/stream.v', 'build-support/android/modulestream/spawn_abi.h'] {
		absolute := os.real_path(path)
		inputs[absolute] = hash(absolute)!
		os.cp(absolute, root + '/sources/' + path.replace('/', '_'))!
	}
	os.cp(os.executable(), root + '/stage')!
	original := command(root, 'read-limine', [mtype, '-i', boot, '::/boot/limine.conf'])!
	config := configure(original)!
	command_expected(root, 'overlay-absent', [mdir, '-i', boot, '::/boot/' + overlay_name], 1)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	mut before := map[string]string{}
	for name in config.modules {
		before[name] = module_hash(root, 'original-' + name, boot, name)!
		check_module(mcopy, boot, name, prefixes)!
	}
	for pair in [[boot, root + '/boot.img'], [efivars, root + '/efivars.fd']] {
		if C.clonefile(pair[0].str, pair[1].str, 0) != 0 { return error('APFS clonefile failed: ' + pair[0]) }
		if hash(pair[1])! != inputs[pair[0]]! { return error('media clone differs') }
	}
	write_overlay(root + '/' + overlay_name, roots, entries)!
	verify_overlay(root + '/' + overlay_name, entries)!
	overlay_hash := hash(root + '/' + overlay_name)!
	// Refuse a pre-existing unreferenced overlay as well; omit mcopy -o.
	command(root, 'install-overlay', [mcopy, '-i', root + '/boot.img', root + '/' + overlay_name, '::/boot/' + overlay_name])!
	command(root, 'install-limine', [mcopy, '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	if command(root, 'readback-limine', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated {
		return error('staged Limine configuration differs')
	}
	command(root, 'readback-overlay', [mcopy, '-i', root + '/boot.img', '::/boot/' + overlay_name, root + '/readback-overlay.tar'])!
	if hash(root + '/readback-overlay.tar')! != overlay_hash { return error('staged overlay bytes differ') }
	verify_overlay(root + '/readback-overlay.tar', entries)!
	os.rm(root + '/readback-overlay.tar')!
	mut after := map[string]string{}
	for name in config.modules {
		after[name] = module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != before[name] { return error('original module changed: ' + name) }
	}
	mut final_entries := []Entry{}
	for prefix in prefixes { inventory(roots[prefix], '', prefix, mut final_entries)! }
	if final_entries != entries { return error('prepared bundle changed during staging') }
	for path, expected in inputs {
		if hash(path)! != expected { return error('input changed during staging: ' + path) }
	}
	revision := command(root, 'source-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	os.write_file(root + '/stage.json', json2.encode({
		'format': json2.Any(1)
		'scope': json2.Any('disposable diagnostic media only; no QEMU launched; browser fixture is not Google login evidence')
		'source_base_revision': json2.Any(revision)
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!
		'original_modules_sha256': json2.decode[json2.Any](json2.encode(before))!
		'preserved_modules_sha256': json2.decode[json2.Any](json2.encode(after))!
		'overlay_additions': json2.decode[json2.Any](json2.encode(entries))!
		'overlay_sha256': json2.Any(overlay_hash)
		'limine_before_sha256': json2.Any(sha256.sum(original.bytes()).hex())
		'limine_after_sha256': json2.Any(sha256.sum(config.updated.bytes()).hex())
		'staged_boot_sha256': json2.Any(hash(root + '/boot.img')!)
		'staged_efivars_sha256': json2.Any(hash(root + '/efivars.fd')!)
		'bundle_roots': json2.decode[json2.Any](json2.encode(roots))!
	}, prettify: true))!
	println('BROWSER-STAGE PASS ' + root + '/stage.json')
}

fn self_test() ! {
	config := '/Vinix\n    protocol: limine\n    module_path: boot():/boot/initramfs.tar\n    module_path: boot():/boot/runtime.tar\n'
	parsed := configure(config)!
	assert parsed.modules == ['initramfs.tar', 'runtime.tar']
	assert parsed.updated == config + '    module_path: boot():/boot/browser-probe.tar\n'
	for bad in [config + '/Other\n', config + '    module_path: boot():/boot/runtime.tar\n',
		config + '    module_path: boot():/boot/../escape.tar\n'] {
		mut rejected := false
		configure(bad) or { rejected = true; Config{} }
		assert rejected
	}
	collision(tarcore.Member{name: './opt/', kind: `5`}, [browser_prefix])!
	for bad in [tarcore.Member{name: 'opt', kind: `2`}, tarcore.Member{name: browser_prefix + '/bin/probe'}] {
		mut rejected := false
		collision(bad, [browser_prefix]) or { rejected = true }
		assert rejected
	}
	root := os.join_path(os.temp_dir(), 'vinix-browser-stage-selftest-' + os.getpid().str())
	if os.exists(root) { return error('self-test path exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/bundle')!
	os.write_file(root + '/bundle/payload', 'real-streamed-fixture')!
	os.chmod(root + '/bundle/payload', 0o751)!
	os.symlink('payload', root + '/bundle/link')!
	mut entries := []Entry{}
	inventory(root + '/bundle', '', browser_prefix, mut entries)!
	write_overlay(root + '/overlay.tar', {browser_prefix: root + '/bundle'}, entries)!
	verify_overlay(root + '/overlay.tar', entries)!
	assert entries.len == 3
	println('BROWSER-STAGE SELF-TEST PASS config collision streamed-archive regular-mode symlink')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	stage() or { eprintln(err); exit(1) }
}
