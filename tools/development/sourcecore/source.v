// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecore

import crypto.sha1
import crypto.sha256
import os
import strings
import time

fn git(root string, args []string, limit int) !string {
	mut process := os.new_process(os.find_abs_path_of_executable('git')!)
	process.set_args(['--literal-pathspecs', '-C', root, ...args])
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	mut output := strings.new_builder(1024)
	mut errors := strings.new_builder(128)
	deadline := time.sys_mono_now() + i64(30_000_000_000)
	for {
		output.write_string(process.stdout_read())
		errors.write_string(process.stderr_read())
		if output.len > limit || errors.len > 65536 || time.sys_mono_now() >= deadline {
			process.signal_kill()
			process.wait()
			return error('Git source read exceeded its output or time limit')
		}
		if !process.is_alive() { break }
		time.sleep(2 * time.millisecond)
	}
	process.wait()
	output.write_string(process.stdout_slurp())
	errors.write_string(process.stderr_slurp())
	if process.code != 0 || errors.len != 0 || output.len > limit {
		return error('Git source read failed: ' + errors.str())
	}
	return output.str()
}

pub fn revision(root string) !string {
	value := git(root, ['rev-parse', '--verify', 'HEAD^{commit}'], 256)!.trim_space()
	if value.len !in [40, 64] || !value.bytes().all(it.is_hex_digit()) {
		return error('Git must report a full commit ID')
	}
	return value
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains('\\')
		&& !path.bytes().any(it < 32 || it == 127)
		&& path.split('/').all(it !in ['', '.', '..'])
}

// Read immutable Git blobs, never working-tree files or source filters. Only
// ordinary selected files are materialized; Python files are always excluded.
// Verify each blob ID so pipe errors or unexpected output cannot alter sources.
pub fn export(root string, commit string, prefixes []string, destination string, accept fn (string) bool) ! {
	if commit.len !in [40, 64] || !commit.bytes().all(it.is_hex_digit())
		|| prefixes.len == 0 || prefixes.any(!relative(it)) || !os.is_dir(destination)
		|| os.is_link(destination) || os.ls(destination)!.len != 0 {
		return error('source export needs a commit, relative prefixes and an empty ordinary destination')
	}
	tree := git(root, ['ls-tree', '-r', '-z', '-l', commit, '--', ...prefixes], 8 * 1024 * 1024)!
	mut copied := 0
	for entry in tree.split('\x00') {
		if entry == '' { continue }
		path := entry.all_after('\t')
		if !relative(path) { return error('unsafe committed source path') }
		if !prefixes.any(path == it || path.starts_with(it + '/')) {
			return error('Git source selection escaped its requested prefixes')
		}
		if path.ends_with('.py') || path.ends_with('.pyc') || path.ends_with('.pyo') || !accept(path) {
			continue
		}
		fields := entry.all_before('\t').fields()
		if fields.len != 4 || fields[0] !in ['100644', '100755'] || fields[1] != 'blob'
			|| fields[2].len != commit.len || !fields[2].bytes().all(it.is_hex_digit())
			|| !fields[3].bytes().all(it >= `0` && it <= `9`) {
			return error('selected source must be a regular Git blob: ' + path)
		}
		size := fields[3].i64()
		if size < 0 || size > 128 * 1024 * 1024 {
			return error('source blob is too large: ' + path)
		}
		contents := git(root, ['cat-file', 'blob', fields[2]], int(size))!
		object := 'blob ${contents.len}\x00' + contents
		hash := if commit.len == 40 {
			sha1.sum(object.bytes()).hex()
		} else {
			sha256.sum(object.bytes()).hex()
		}
		if contents.len != size || hash != fields[2] {
			return error('committed source blob verification failed: ' + path)
		}
		target := destination + '/' + path
		if os.exists(target) || os.is_link(target) {
			return error('source destination already exists: ' + target)
		}
		os.mkdir_all(os.dir(target), mode: 0o755)!
		os.write_file(target, contents)!
		os.chmod(target, if fields[0] == '100755' { 0o755 } else { 0o644 })!
		copied++
	}
	if copied == 0 { return error('source selection is empty') }
}
