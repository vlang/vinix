// SPDX-License-Identifier: GPL-2.0-or-later
// Seal complete external qualification trees without following evidence links.
module main

import crypto.sha256
import json2
import os

struct QualificationReceipt {
mut:
	architecture string
	artifacts map[string]string
	artifact_paths map[string]string
}

struct CapturedInput {
	path string
	sha256 string
}

struct CaptureReceipt {
	format int = 1
	architecture string
	qualification_path string
	qualification_sha256 string
	inputs map[string]CapturedInput
}

fn sha(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn inventory(root string, directory string, mut lines []string) ! {
	mut names := os.ls(directory)!
	names.sort()
	for name in names {
		path := directory + '/' + name
		relative := path[root.len + 1..]
		if relative == 'bundle.sha256' { continue }
		if relative.contains_any('\t\r\n') { return error('unrepresentable evidence path') }
		if os.is_link(path) {
			target := os.readlink(path)!
			if target.contains_any('\t\r\n') { return error('unrepresentable evidence link') }
			lines << 'link\t' + sha256.sum(target.bytes()).hex() + '\t' + relative + '\t' + target
		} else if os.is_dir(path) {
			inventory(root, path, mut lines)!
		} else if os.is_file(path) {
			info := os.lstat(path)!
			if info.mode & 0o170000 != 0o100000 { return error('special evidence file: ' + relative) }
			lines << 'file\t' + sha(path)! + '\t' + relative
		} else { return error('unsupported evidence entry: ' + relative) }
	}
}

fn manifest(root string) !string {
	mut lines := []string{}
	inventory(root, root, mut lines)!
	if lines.len == 0 { return error('cannot seal an empty evidence tree') }
	return lines.join('\n') + '\n'
}

fn check(root string) ! {
	if os.is_link(root + '/bundle.sha256') ||
		os.read_file(root + '/bundle.sha256')! != manifest(root)! {
		return error('complete evidence inventory differs')
	}
}

fn seal(root string, output string) ! {
	archive := os.abs_path(output)
	if os.exists(root + '/bundle.sha256') || os.is_link(root + '/bundle.sha256') ||
		os.exists(archive) || os.is_link(archive) || os.exists(archive + '.sha256') ||
		os.is_link(archive + '.sha256') || !os.is_dir(os.dir(archive)) {
		return error('requires a new manifest and archive with existing parent')
	}
	parent := os.real_path(os.dir(archive))
	if parent == root || parent.starts_with(root + '/') { return error('archive must be outside the evidence tree') }
	os.write_file(root + '/bundle.sha256', manifest(root)!)!
	check(root)!
	mut child := os.new_process(os.find_abs_path_of_executable('tar')!)
	defer { child.close() }
	child.set_args(['-czf', archive, '-C', os.dir(root), '--', os.file_name(root)])
	child.wait()
	if child.code != 0 { return error('evidence archive failed; incomplete output retained') }
	check(root)!
	checksum := sha(archive)!
	os.write_file(archive + '.sha256', checksum + '  ' + os.file_name(archive) + '\n')!
	println('SOFTWARE RELEASE ROUTING BUNDLE PASS manifest=' + sha(root + '/bundle.sha256')! +
		' archive=' + checksum)
}

fn contained(root string, path string) bool {
	return path == root || path.starts_with(root + '/')
}

fn hex_digest(value string) bool {
	if value.len != 64 { return false }
	for byte in value.bytes() {
		if (byte < `0` || byte > `9`) && (byte < `a` || byte > `f`) { return false }
	}
	return true
}

// Preserve external referent bytes; original receipt paths remain authoritative.
fn capture(root string, receipt_path string) ! {
	if os.exists(root + '/bundle.sha256') || os.is_link(root + '/bundle.sha256') {
		return error('cannot capture inputs after sealing')
	}
	receipt_file := os.real_path(receipt_path)
	info := os.stat(receipt_file)!
	if !contained(root, receipt_file) || info.mode & 0o170000 != 0o100000 ||
		info.size == 0 || info.size > 8 * 1024 * 1024 {
		return error('requires a bounded regular receipt inside the evidence tree')
	}
	receipt_hash := sha(receipt_file)!
	receipt := json2.decode[QualificationReceipt](os.read_file(receipt_file)!)!
	if receipt.architecture !in ['aarch64', 'x86_64'] || receipt.artifacts.len == 0 ||
		receipt.artifacts.len > 4096 || receipt.artifacts.len != receipt.artifact_paths.len {
		return error('receipt artifact paths do not cover bounded architecture inputs')
	}
	mut external := map[string]CapturedInput{}
	for name, expected in receipt.artifacts {
		path := receipt.artifact_paths[name] or { return error('missing artifact path: ' + name) }
		if !os.is_abs_path(path) || !hex_digest(expected) { return error('invalid artifact path or digest: ' + name) }
		resolved := os.real_path(path)
		entry := os.stat(resolved)!
		if entry.mode & 0o170000 != 0o100000 { return error('artifact is not a regular file: ' + name) }
		if sha(resolved)! != expected { return error('receipt artifact digest differs: ' + name) }
		if !contained(root, resolved) {
			external[path] = CapturedInput{path: 'original-inputs/' + expected, sha256: expected}
		}
	}
	storage := root + '/original-inputs'
	if os.is_link(storage) || (os.exists(storage) && !os.is_dir(storage)) {
		return error('capture storage must be a real directory')
	}
	output := storage + '/capture-' + receipt.architecture + '-' + receipt_hash + '.json'
	if os.exists(output) || os.is_link(output) { return error('capture receipt already exists') }
	os.mkdir_all(storage)!
	for original, input in external {
		destination := root + '/' + input.path
		if os.is_link(destination) { return error('captured input must not be a symbolic link') }
		if !os.exists(destination) { os.cp(os.real_path(original), destination, fail_if_exists: true)! }
		stored := os.lstat(destination)!
		if stored.mode & 0o170000 != 0o100000 || sha(destination)! != input.sha256 {
			return error('captured input bytes differ')
		}
	}
	if sha(receipt_file)! != receipt_hash { return error('receipt changed during capture') }
	os.write_file(output, json2.encode(CaptureReceipt{architecture: receipt.architecture,
		qualification_path: receipt_file, qualification_sha256: receipt_hash, inputs: external}) + '\n')!
	println('SOFTWARE RELEASE ROUTING INPUT CAPTURE PASS receipt=' + output + ' sha256=' + sha(output)!)
}

fn reject_check(root string, reason string) ! {
	check(root) or {
		if !err.msg().contains(reason) { return error('unexpected check refusal: ' + err.msg()) }
		return
	}
	return error('self-test accepted an invalid inventory')
}

fn reject_seal(root string, archive string, reason string) ! {
	seal(root, archive) or {
		if !err.msg().contains(reason) { return error('unexpected seal refusal: ' + err.msg()) }
		if os.exists(root + '/bundle.sha256') { return error('refused seal created a manifest') }
		return
	}
	return error('self-test accepted an invalid archive destination')
}

fn reject_capture(root string, path string, reason string) ! {
	capture(root, path) or {
		if !err.msg().contains(reason) { return error('unexpected capture refusal: ' + err.msg()) }
		return
	}
	return error('self-test accepted invalid capture inputs')
}

fn self_test(work string) ! {
	if os.exists(work) || os.is_link(work) { return error('self-test requires a new scratch directory') }
	os.mkdir_all(work)!
	root := work + '/--dereference'
	os.mkdir_all(root + '/nested')!
	os.mkdir_all(work + '/outside-directory')!
	os.write_file(root + '/payload', 'payload\n')!
	os.write_file(root + '/nested/data', 'nested\n')!
	os.write_file(work + '/outside-file', 'outside\n')!
	os.write_file(work + '/outside-directory/secret', 'never follow this link\n')!
	links := {
		'cycle': '.'
		'dangling': 'missing'
		'outside-directory': work + '/outside-directory'
		'outside-file': work + '/outside-file'
		'relative': 'nested/data'
	}
	for name, target in links { os.symlink(target, root + '/' + name)! }
	original := manifest(root)!
	mut expected := ['file\t' + sha256.sum('payload\n'.bytes()).hex() + '\tpayload',
		'file\t' + sha256.sum('nested\n'.bytes()).hex() + '\tnested/data']
	for name, target in links {
		expected << 'link\t' + sha256.sum(target.bytes()).hex() + '\t' + name + '\t' + target
	}
	expected.sort()
	mut actual := original.split_into_lines()
	actual.sort()
	if actual != expected { return error('self-test inventory omitted, followed or misclassified an entry') }
	os.write_file(root + '/bundle.sha256', original)!
	check(root)!
	// Link referent bytes are deliberately outside this non-following inventory.
	os.write_file(work + '/outside-file', 'changed outside the tree\n')!
	check(root)!
	os.write_file(root + '/payload', 'changed\n')!
	reject_check(root, 'complete evidence inventory differs')!
	os.write_file(root + '/payload', 'payload\n')!
	os.write_file(root + '/nested/bundle.sha256', 'nested manifests are ordinary evidence\n')!
	reject_check(root, 'complete evidence inventory differs')!
	os.rm(root + '/nested/bundle.sha256')!
	os.rm(root + '/nested/data')!
	reject_check(root, 'complete evidence inventory differs')!
	os.write_file(root + '/nested/data', 'nested\n')!
	os.rm(root + '/relative')!
	os.symlink('payload', root + '/relative')!
	reject_check(root, 'complete evidence inventory differs')!
	os.rm(root + '/relative')!
	os.symlink('nested/data', root + '/relative')!
	os.write_file(root + '/bundle.sha256', original + 'unexpected\n')!
	reject_check(root, 'complete evidence inventory differs')!
	os.rm(root + '/bundle.sha256')!
	os.write_file(work + '/manifest-reference', original)!
	os.symlink(work + '/manifest-reference', root + '/bundle.sha256')!
	reject_check(root, 'complete evidence inventory differs')!
	os.rm(root + '/bundle.sha256')!
	os.write_file(root + '/bad\tname', 'unrepresentable\n')!
	os.write_file(root + '/bundle.sha256', original)!
	reject_check(root, 'unrepresentable evidence path')!
	os.rm(root + '/bad\tname')!
	check(root)!
	os.rm(root + '/bundle.sha256')!
	reject_seal(root, root + '/inside.tar.gz', 'archive must be outside')!
	os.symlink(root, work + '/alias')!
	reject_seal(root, work + '/alias/inside.tar.gz', 'archive must be outside')!
	os.write_file(work + '/existing.tar.gz', 'existing archive\n')!
	reject_seal(root, work + '/existing.tar.gz', 'requires a new manifest and archive')!
	os.symlink('missing', work + '/linked.tar.gz')!
	reject_seal(root, work + '/linked.tar.gz', 'requires a new manifest and archive')!
	os.write_file(work + '/sidecar.tar.gz.sha256', 'existing checksum\n')!
	reject_seal(root, work + '/sidecar.tar.gz', 'requires a new manifest and archive')!
	archive := work + '/proof.tar.gz'
	seal(root, archive)!
	if os.read_file(archive + '.sha256')! != sha(archive)! + '  proof.tar.gz\n' {
		return error('self-test archive checksum differs')
	}
	extracted := work + '/extracted'
	os.mkdir(extracted)!
	mut child := os.new_process(os.find_abs_path_of_executable('tar')!)
	defer { child.close() }
	child.set_args(['-xzf', archive, '-C', extracted])
	child.wait()
	if child.code != 0 { return error('self-test archive extraction failed') }
	for name, target in links {
		path := extracted + '/--dereference/' + name
		if !os.is_link(path) || os.readlink(path)! != target { return error('archive followed or changed an evidence link') }
	}
	check(extracted + '/--dereference')!
	capture_test(work)!
	os.write_file(work + '/result.txt', 'production-safe bundle self-test PASS\n')!
	println('SOFTWARE RELEASE ROUTING BUNDLE SELF TEST PASS')
}

fn capture_test(work string) ! {
	root := work + '/capture-root'
	os.mkdir(root)!
	os.write_file(root + '/internal', 'retained internal bytes\n')!
	os.symlink(work + '/outside-file', work + '/outside-alias')!
	mut receipt := QualificationReceipt{architecture: 'aarch64', artifacts: {
		'internal': sha(root + '/internal')!
		'external': sha(work + '/outside-file')!
		'alias': sha(work + '/outside-file')!
	}, artifact_paths: {
		'internal': root + '/internal'
		'external': work + '/outside-file'
		'alias': work + '/outside-alias'
	}}
	path := root + '/qualification.json'
	valid := json2.encode(receipt) + '\n'
	receipt.artifact_paths.delete('internal')
	os.write_file(path, json2.encode(receipt))!
	reject_capture(root, path, 'do not cover')!
	if os.exists(root + '/original-inputs') { return error('invalid coverage created capture storage') }
	receipt.artifact_paths['unexpected'] = root + '/internal'
	os.write_file(path, json2.encode(receipt))!
	reject_capture(root, path, 'missing artifact path')!
	if os.exists(root + '/original-inputs') { return error('mismatched coverage created capture storage') }
	receipt = json2.decode[QualificationReceipt](valid)!
	receipt.artifacts['internal'] = '0'.repeat(64)
	os.write_file(path, json2.encode(receipt))!
	reject_capture(root, path, 'digest differs')!
	if os.exists(root + '/original-inputs') { return error('invalid digest created capture storage') }
	os.write_file(path, valid)!
	os.symlink(work + '/outside-directory', root + '/original-inputs')!
	reject_capture(root, path, 'real directory')!
	if os.ls(work + '/outside-directory')!.len != 1 { return error('capture followed storage link') }
	os.rm(root + '/original-inputs')!
	capture(root, path)!
	output := root + '/original-inputs/capture-aarch64-' + sha(path)! + '.json'
	captured := json2.decode[CaptureReceipt](os.read_file(output)!)!
	input := captured.inputs[work + '/outside-file'] or { return error('external input was not captured') }
	alias := captured.inputs[work + '/outside-alias'] or { return error('external link was not dereferenced') }
	if captured.format != 1 || captured.architecture != 'aarch64' || captured.qualification_path != path ||
		captured.qualification_sha256 != sha(path)! || captured.inputs.len != 2 || input != alias ||
		input.sha256 != sha(work + '/outside-file')! || input.path != 'original-inputs/' + input.sha256 ||
		sha(root + '/' + input.path)! != sha(work + '/outside-file')! ||
		os.ls(root + '/original-inputs')!.len != 2 {
		return error('capture mapping, internal exclusion, dereference or deduplication differs')
	}
	reject_capture(root, path, 'capture receipt already exists')!
	os.write_file(root + '/bundle.sha256', manifest(root)!)!
	reject_capture(root, path, 'after sealing')!
	check(root)!
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'self-test' {
		self_test(os.abs_path(os.args[2]))!
		return
	}
	if os.args.len !in [3, 4] || os.args[1] !in ['check', 'seal', 'capture'] ||
		(os.args[1] != 'check') != (os.args.len == 4) {
		return error('use check ROOT, seal ROOT NEW_ARCHIVE.tar.gz, capture ROOT RECEIPT or self-test NEW_SCRATCH_DIRECTORY')
	}
	root := os.real_path(os.args[2])
	if !os.is_dir(root) { return error('evidence root is not a directory') }
	if os.args[1] == 'check' { check(root)!; println('SOFTWARE RELEASE ROUTING BUNDLE CHECK PASS') }
	else if os.args[1] == 'seal' { seal(root, os.args[3])! }
	else { capture(root, os.args[3])! }
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
