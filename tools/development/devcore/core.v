// SPDX-License-Identifier: GPL-2.0-or-later
module devcore

import crypto.sha256
import os
import sourcecommand
import time

pub struct Pin {
pub:
	path   string
	sha256 string
}

pub fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 65536}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn hash_tree(path string, root string, relative string, mut digest sha256.Digest) ! {
	st := os.lstat(path)!
	digest.write('${relative.len}:${relative}:${st.mode & 0o777}:'.bytes())!
	match st.get_filetype() {
		.directory {
			digest.write('directory\n'.bytes())!
			mut names := os.ls(path)!
			names.sort()
			for name in names {
				hash_tree(path + '/' + name, root, relative + '/' + name, mut digest)!
			}
		}
		.regular { digest.write(('file:' + file_hash(path)! + '\n').bytes())! }
		.symbolic_link {
			// A build source must be a complete, portable closure. Symlinks to
			// dependencies outside it otherwise escape the receipt's hash.
			target := os.readlink(path)!
			resolved := os.real_path(path)
			if target.starts_with('/') || resolved != root && !resolved.starts_with(root + '/') {
				return error('materialize external source link: ${path}')
			}
			digest.write(('link:' + target + '\n').bytes())!
		}
		else { return error('unsupported input file type: ${path}') }
	}
}

pub fn tree_hash(path string) !string {
	mut digest := sha256.new()
	hash_tree(path, os.real_path(path), '.', mut digest)!
	return digest.sum([]u8{}).hex()
}

// os.cp_all dereferences symlinks and does not preserve directory modes.
// Preserve the exact tree the receipt describes, including internal links.
pub fn copy_tree(source string, destination string) ! {
	st := os.lstat(source)!
	match st.get_filetype() {
		.directory {
			os.mkdir(destination, mode: 0o700)!
			for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
			os.chmod(destination, int(st.mode & 0o777))!
		}
		.regular {
			os.cp(source, destination)!
			os.chmod(destination, int(st.mode & 0o777))!
		}
		.symbolic_link { os.symlink(os.readlink(source)!, destination)! }
		else { return error('unsupported input file type: ${source}') }
	}
}

pub fn verify(pin Pin) ! {
	if pin.path == '' || pin.sha256.len != 64 || !pin.sha256.bytes().all(it.is_hex_digit()) {
		return error('input requires a path and full SHA-256')
	}
	actual := if os.is_dir(pin.path) { tree_hash(pin.path)! } else { file_hash(pin.path)! }
	if actual != pin.sha256 { return error('input changed: ${pin.path}') }
}

pub fn relative_path(path string) ! {
	if path == '' || path.starts_with('/') || path.contains('\x00')
		|| path.split('/').any(it == '..' || it == '') {
		return error('expected a relative path within the workspace: ${path}')
	}
}

// Newly created state is private from its first instant, including before
// receipt/log creation. Never reuse a caller's or another session's directory.
pub fn fresh_directory(path string) ! {
	if os.exists(path) || os.is_link(path) { return error('output already exists: ${path}') }
	os.mkdir(path, mode: 0o700)!
}

pub fn private_directory(path string) ! {
	st := os.lstat(path)!
	if st.get_filetype() != .directory || st.uid != u32(os.getuid()) || st.mode & 0o077 != 0 {
		return error('state must be a directory owned by this user with mode 0700: ${path}')
	}
}

pub fn environment(epoch i64) map[string]string {
	mut env := map[string]string{}
	for name in ['PATH', 'HOME', 'TMPDIR', 'TERM'] {
		if value := os.getenv_opt(name) { env[name] = value }
	}
	env['LC_ALL'] = 'C'
	env['TZ'] = 'UTC'
	env['SOURCE_DATE_EPOCH'] = epoch.str()
	return env
}

struct Clock {
	deadline u64
}

fn wait_command(pid int, context voidptr) ! {
	clock := unsafe { &Clock(context) }
	for !sourcecommand.child_exited(pid)! {
		if time.sys_mono_now() >= clock.deadline { return error('command deadline expired') }
		time.sleep(10 * time.millisecond)
	}
}

pub fn run(argv []string, directory string, env map[string]string, timeout int, log string) !int {
	if timeout < 1 || timeout > 86400 || argv.len == 0 {
		return error('command requires argv and a deadline of 1..86400 seconds')
	}
	clock := Clock{time.sys_mono_now() + u64(timeout) * u64(time.second)}
	result := sourcecommand.run_logged_owned(argv, env, unsafe { nil }, log, false,
		directory, wait_command, unsafe { &clock }, 1)!
	return result.status
}
