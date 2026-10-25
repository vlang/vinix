// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve failed diagnostics; this never admits translated execution.
module main

import crypto.sha256
import json2
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#define st_mtimensec st_mtimespec.tv_nsec
#define st_ctimensec st_ctimespec.tv_nsec

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.fstat(int, &C.stat) int
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int

struct Object {
	path string
	kind string
	target string
	mode u32
	size u64
	digest string
}

struct Pin {
	digest string
	link string
}

struct InputPair {
	path string
	before_digest string
	after_digest string
	count int
	identical bool
	note string
}

struct Capture {
	format int = 1
	source_revision string
	original_roots []string
	sources map[string]string
	input_pairs []InputPair
	baseline string
	kernel_receipt string
	kernel_receipt_digest string
	sealer_digest string
	tar_path string
	tar_digest string
	scope string = 'Failed diagnostics only. Selected input pairs are compared, not independently admitted; the complete original baseline remains required. Kernel receipt bytes are pinned, not decoded or qualified. This is not reproducibility, a hermetic toolchain, a kernel qualification, translated-workload success, or Wine execution.'
}

fn ordinary(path string, destination string) !string {
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot open ordinary file without following links: ' + path) }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000
		|| before.st_size < 0 || u64(before.st_size) > u64(32) * 1024 * 1024 * 1024 {
		return error('not a bounded ordinary file: ' + path)
	}
	mut out := -1
	if destination != '' {
		out = C.open(destination.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o644)
		if out < 0 { return error('cannot exclusively create: ' + destination) }
	}
	defer { if out >= 0 { C.close(out) } }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: sha256.size}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	mut remaining := before.st_size
	for remaining > 0 {
		want := if remaining < i64(buffer.len) { int(remaining) } else { buffer.len }
		count := C.read(fd, buffer.data, usize(want))
		if count <= 0 || count > want { return error('incomplete read: ' + path) }
		hash.write(unsafe { buffer[..int(count)] })!
		if out >= 0 {
			mut offset := 0
			for offset < int(count) {
				written := C.write(out, unsafe { &buffer[offset] }, usize(int(count) - offset))
				if written <= 0 { return error('incomplete copy: ' + destination) }
				offset += int(written)
			}
		}
		remaining -= count
	}
	mut extra := u8(0)
	mut after := C.stat{}
	if C.read(fd, unsafe { &extra }, 1) != 0 || C.fstat(fd, unsafe { &after }) != 0
		|| before.st_dev != after.st_dev || before.st_ino != after.st_ino
		|| before.st_size != after.st_size || before.st_mtime != after.st_mtime
		|| before.st_mtimensec != after.st_mtimensec || before.st_ctime != after.st_ctime
		|| before.st_ctimensec != after.st_ctimensec {
		return error('file changed while streaming: ' + path)
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn close_objects(values []Object) {
	unsafe {
		for value in values { value.path.free(); value.kind.free(); value.target.free(); value.digest.free() }
		(&array(&values)).free()
	}
}

fn safe_path(path string) ! {
	if path.len == 0 || path.len > 4096 || path.contains('\t') || path.contains('\n') || path.contains('\r')
		|| path.contains('\x00') { return error('invalid inventory path') }
}

// lstat only: symlink targets and socket/FIFO/device types are literal records.
// Special nodes are never opened, connected to, or recreated in the view.
fn collect(root string, relative string, mut result []Object) ! {
	path := if relative == '' { root.clone() } else { root + '/' + relative }
	defer { unsafe { path.free() } }
	stat := os.lstat(path)!
	if stat.get_filetype() != .directory { return error('inventory root is not an ordinary directory') }
	names := os.ls(path)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	for name in names {
		entry := if relative == '' { name.clone() } else { relative + '/' + name }
		full := root + '/' + entry
		defer { unsafe { full.free() } }
		safe_path(entry)!
		if result.len >= 100000 { return error('inventory exceeds 100000 objects') }
		info := os.lstat(full)!
		kind := info.get_filetype()
		mut target := ''
		mut digest := ''
		if kind == .symbolic_link { target = os.readlink(full)! }
		if kind == .regular { digest = ordinary(full, '')! }
		// Directory byte sizes depend on omitted special children, not content.
		result << Object{entry, kind.str(), target, u32(info.get_mode().bitmask()),
			if kind == .directory { u64(0) } else { info.size }, digest}
		if kind == .directory { collect(root, entry, mut result)! }
	}
}

fn inventory(root string) ![]Object {
	mut result := []Object{cap: 1024}
	unsafe { result.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_objects(result) } }
	collect(root, '', mut result)!
	result.sort(a.path < b.path)
	accepted = true
	return result
}

fn verify_inventory(root string, expected []Object, view bool) ! {
	actual := inventory(root)!
	defer { close_objects(actual) }
	mut selected := []Object{cap: expected.len}
	defer { unsafe { selected.free() } }
	for object in expected {
		if !view || object.kind in ['regular', 'directory', 'symbolic_link'] { selected << object }
	}
	if actual != selected { return error('complete typed inventory changed: ' + root) }
}

fn snapshot(root string, destination string, entries []Object) ! {
	os.mkdir(destination)!
	for entry in entries {
		source := root + '/' + entry.path
		target := destination + '/' + entry.path
		defer { unsafe { source.free(); target.free() } }
		if entry.kind == 'directory' { os.mkdir(target)! }
		else if entry.kind == 'regular' {
			before := os.lstat(source)!
			if before.get_filetype() != .regular || C.link(source.str, target.str) != 0 {
				return error('cannot hardlink ordinary diagnostic file: ' + source)
			}
			after := os.lstat(source)!
			linked := os.lstat(target)!
			if before.dev != after.dev || before.dev != linked.dev
				|| before.inode != after.inode || before.inode != linked.inode
				|| after.get_filetype() != .regular || linked.get_filetype() != .regular
				|| ordinary(target, '')! != entry.digest { return error('hardlinked source changed: ' + source) }
		} else if entry.kind == 'symbolic_link' { os.symlink(entry.target, target)! }
	}
	// Apply directory permissions only after all children have been created.
	for index := entries.len - 1; index >= 0; index-- {
		entry := entries[index]
		if entry.kind == 'directory' { os.chmod(destination + '/' + entry.path, int(entry.mode))! }
	}
	verify_inventory(root, entries, false)!
	verify_inventory(destination, entries, true)!
}

fn write_new(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o644)
	if fd < 0 { return error('output already exists or cannot be created: ' + path) }
	defer { C.close(fd) }
	mut offset := 0
	for offset < text.len {
		count := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if count <= 0 { return error('cannot write output: ' + path) }
		offset += int(count)
	}
}

fn pair(root string, relative string) !InputPair {
	before := root + '/' + relative + '/inputs.json'
	after := root + '/' + relative + '/inputs-verified.json'
	defer { unsafe { before.free(); after.free() } }
	before_hash := ordinary(before, '')!
	values := json2.decode[map[string]Pin](os.read_file(before)!)!
	if values.len == 0 { return error('empty selected-input map') }
	if !os.exists(after) {
		return InputPair{relative, before_hash, '', values.len, false, 'Final verification absent; incomplete diagnostic attempt.'}
	}
	after_hash := ordinary(after, '')!
	verified := json2.decode[map[string]Pin](os.read_file(after)!)!
	if values != verified { return error('selected-input maps differ: ' + relative) }
	return InputPair{relative, before_hash, after_hash, values.len, true,
		'Path/digest/link tuples match; external selected inputs are not re-admitted by this sealer.'}
}

fn invoke(arguments []string, log string) ! {
	write_new(log + '.argv.json', json2.encode(arguments))!
	mut process := os.new_process(arguments[0])
	defer { process.close() }
	process.set_args(arguments[1..])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	errors := process.stderr_slurp()
	process.wait()
	write_new(log, output + errors)!
	if process.code != 0 { return error('archive tool failed; see ' + log) }
}

fn seal() ! {
	$if prod {} $else { return error('compile failed diagnostic sealer with -prod') }
	if os.args.len != 8 { return error('usage: wine-fork-jit-retain ROOT RAW TOOLS KERNEL_RECEIPT BASELINE NEW_VIEW NEW_ARCHIVE.tar.gz') }
	root := os.real_path(os.args[1])
	raw := os.real_path(os.args[2])
	tools := os.real_path(os.args[3])
	kernel_receipt := os.real_path(os.args[4])
	baseline := os.real_path(os.args[5])
	view := os.abs_path(os.args[6])
	archive := os.abs_path(os.args[7])
	for output in [view, archive, archive + '.sha256', archive + '.tar.log', archive + '.tar.log.argv.json'] {
		if os.exists(output) || os.is_link(output) { return error('refusing existing output: ' + output) }
		if output == raw || output.starts_with(raw + '/') || output == tools || output.starts_with(tools + '/') {
			return error('output must be outside both original roots')
		}
	}
	if archive == view || archive.starts_with(view + '/') { return error('archive must be outside view') }
	if !os.is_dir(baseline) || !os.is_file(baseline + '/inputs.json')
		|| !os.is_file(baseline + '/generated.json') { return error('complete original baseline is required') }
	embedded := sha256.hexhash($embed_file('wine-fork-jit-retain.v').to_string())
	if ordinary(@FILE, '')! != embedded
		|| ordinary(root + '/tests/packages/wine-fork-jit-retain.v', '')! != embedded {
		return error('compiled sealer source changed')
	}
	revision_result := os.exec(['git', '-C', root, 'rev-parse', 'HEAD'])
	if revision_result.exit_code != 0 { return error('cannot record source revision') }
	revision := revision_result.output.trim_space()
	raw_entries := inventory(raw)!
	tools_entries := inventory(tools)!
	defer { close_objects(raw_entries); close_objects(tools_entries) }
	mut pairs := []InputPair{}
	for name in ['altstack', 'jit01', 'jit02'] { pairs << pair(raw, name)! }
	pairs << pair(tools, 'altstack-c6b5455e')!
	mut sources := map[string]string{}
	for relative in ['tests/packages/wine-fork-jit-check.v', 'tests/packages/wine-fork-jit-guest/main.v',
		'tests/packages/wine-fork-jit-retain.v', 'tests/packages/wine-translation-fork-check.v',
		'tests/packages/wine-translation-fork-guest/main.v', 'tests/packages/wine-fork-probe/main.v',
		'tools/packages/wineadapter/patch.v'] {
		sources[relative] = ordinary(root + '/' + relative, '')!
	}
	kernel_digest := ordinary(kernel_receipt, '')!
	sealer := os.executable()
	sealer_digest := ordinary(sealer, '')!
	tar_path := os.real_path('/usr/bin/tar')
	tar_digest := ordinary(tar_path, '')!
	os.mkdir(view)!
	snapshot(raw, view + '/raw', raw_entries)!
	snapshot(tools, view + '/tools', tools_entries)!
	for relative, expected in sources {
		target := view + '/sources/' + relative
		os.mkdir_all(os.dir(target))!
		if ordinary(root + '/' + relative, target)! != expected || ordinary(target, '')! != expected {
			return error('source changed during capture: ' + relative)
		}
	}
	if ordinary(kernel_receipt, view + '/kernel-receipt.json')! != kernel_digest {
		return error('kernel receipt changed during capture')
	}
	if ordinary(sealer, view + '/sealer')! != sealer_digest { return error('sealer changed during capture') }
	write_new(view + '/raw-objects.json', json2.encode(raw_entries))!
	write_new(view + '/tools-objects.json', json2.encode(tools_entries))!
	write_new(view + '/capture.json', json2.encode(Capture{source_revision: revision,
		original_roots: [raw, tools], sources: sources, input_pairs: pairs,
		baseline: baseline, kernel_receipt: kernel_receipt, kernel_receipt_digest: kernel_digest,
		sealer_digest: sealer_digest, tar_path: tar_path, tar_digest: tar_digest}))!
	all := inventory(view)!
	defer { close_objects(all) }
	mut manifest := ''
	for object in all { if object.kind == 'regular' { manifest += object.digest + '  ' + object.path + '\n' } }
	write_new(view + '/SHA256SUMS', manifest)!
	// Add the existing routing inventory format for independent stream readers.
	listed := inventory(view)!
	defer { close_objects(listed) }
	mut bundle_manifest := ''
	for object in listed {
		if object.kind == 'regular' { bundle_manifest += 'file\t' + object.digest + '\t' + object.path + '\n' }
		if object.kind == 'symbolic_link' {
			safe_path(object.target)!
			bundle_manifest += 'link\t' + sha256.hexhash(object.target) + '\t' + object.path + '\t' + object.target + '\n'
		}
	}
	write_new(view + '/bundle.sha256', bundle_manifest)!
	sealed := inventory(view)!
	defer { close_objects(sealed) }
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke([tar_path, '-czf', archive, '-C', os.dir(view), os.file_name(view)], archive + '.tar.log')!
	verify_inventory(view, sealed, false)!
	verify_inventory(raw, raw_entries, false)!
	verify_inventory(tools, tools_entries, false)!
	for relative, expected in sources {
		if ordinary(root + '/' + relative, '')! != expected { return error('source changed after archive: ' + relative) }
	}
	if ordinary(kernel_receipt, '')! != kernel_digest { return error('kernel receipt changed after archive') }
	if ordinary(sealer, '')! != sealer_digest { return error('sealer changed after archive') }
	if ordinary(tar_path, '')! != tar_digest { return error('tar changed after archive') }
	archive_digest := ordinary(archive, '')!
	write_new(archive + '.sha256', archive_digest + '  ' + os.file_name(archive) + '\n')!
	println('FAILED DIAGNOSTIC ARCHIVE SEALED (no qualification)')
	println('Archive SHA256: ' + archive_digest)
	println('SHA256SUMS SHA256: ' + ordinary(view + '/SHA256SUMS', '')!)
	println('bundle.sha256 SHA256: ' + ordinary(view + '/bundle.sha256', '')!)
	println('Capture SHA256: ' + ordinary(view + '/capture.json', '')!)
	println('Raw objects: ' + raw_entries.len.str() + '; tools objects: ' + tools_entries.len.str())
}

fn self_test() ! {
	if os.args.len != 3 { return error('usage: wine-fork-jit-retain --self-test NEW_EXTERNAL_DIRECTORY') }
	root := os.abs_path(os.args[2])
	if os.exists(root) || os.is_link(root) { return error('self-test output exists') }
	os.mkdir(root)!
	os.mkdir(root + '/original')!
	mut bytes := []u8{len: 131073}
	for index in 0 .. bytes.len { bytes[index] = u8(index % 251) }
	os.write_file_array(root + '/original/bytes', bytes)!
	os.write_file(root + '/original/empty', '')!
	os.symlink('missing-target', root + '/original/dangling')!
	os.mkdir(root + '/original/subdirectory')!
	if C.mkfifo((root + '/original/subdirectory/fifo').str, 0o600) != 0 { return error('cannot create self-test FIFO') }
	entries := inventory(root + '/original')!
	defer { close_objects(entries); unsafe { bytes.free() } }
	if entries.len != 5 { return error('self-test inventory count differs') }
	snapshot(root + '/original', root + '/snapshot', entries)!
	if os.exists(root + '/snapshot/subdirectory/fifo') || os.readlink(root + '/snapshot/dangling')! != 'missing-target' {
		return error('self-test special-node or symlink handling differs')
	}
	copied := root + '/copy'
	if ordinary(root + '/original/bytes', copied)! != ordinary(copied, '')! { return error('self-test streaming copy differs') }
	mut refused := false
	ordinary(root + '/original/bytes', copied) or { refused = true; '' }
	if !refused { return error('self-test overwrote existing output') }
	refused = false
	ordinary(root + '/original/dangling', '') or { refused = true; '' }
	if !refused { return error('self-test followed symlink') }
	refused = false
	ordinary(root + '/original/subdirectory/fifo', '') or { refused = true; '' }
	if !refused { return error('self-test opened a FIFO as file') }
	os.write_file(root + '/snapshot/empty', 'changed')!
	refused = false
	verify_inventory(root + '/snapshot', entries, true) or { refused = true }
	if !refused { return error('self-test failed to detect changed hardlink') }
	println('PASS streaming/copy, exclusive output, empty/large files, dangling symlink, FIFO typed inventory, no-follow refusal, full-view mutation refusal')
}

fn main() {
	if os.args.len >= 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err.msg()); exit(1) }
		return
	}
	seal() or { eprintln(err.msg()); exit(1) }
}
