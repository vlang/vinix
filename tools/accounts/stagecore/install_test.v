// SPDX-License-Identifier: GPL-2.0-or-later
module stagecore

import os

fn fixture() !string {
	base := os.join_path(os.temp_dir(), 'vinix-account-stage-${os.getpid()}')
	os.rmdir_all(base) or {}
	os.mkdir_all(base + '/image/usr/sbin')!
	os.mkdir(base + '/outside')!
	os.write_file(base + '/source', 'new account executable')!
	os.write_file(base + '/image/usr/sbin/vinix-authd', 'old account executable')!
	os.write_file(base + '/outside/marker', 'outside preserved')!
	os.setenv('VINIX_ACCOUNT_STAGE_FIXTURE', base, true)
	return base
}

fn dispose(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }

fn refuse(installer &Installer, source string, relative string) {
	if _ := installer.put(source, relative, 0o755) { assert false } else { dispose(err) }
}

fn replace(phase string) ! {
	if phase != 'written' { return }
	base := os.getenv('VINIX_ACCOUNT_STAGE_FIXTURE')
	defer { unsafe { base.free() } }
	kind := os.getenv('VINIX_ACCOUNT_STAGE_REPLACE')
	defer { unsafe { kind.free() } }
	match kind {
		'root' {
			os.rename(base + '/image', base + '/retained')!
			os.symlink(base + '/outside', base + '/image')!
		}
		'parent' {
			os.rename(base + '/image/usr/sbin', base + '/retained')!
			os.symlink(base + '/outside', base + '/image/usr/sbin')!
		}
		'leaf' { os.rm(base + '/image/usr/sbin/vinix-authd')!; os.symlink(base + '/outside/marker', base + '/image/usr/sbin/vinix-authd')! }
		'temporary' {
			for name in os.ls(base + '/image/usr/sbin')! {
				if !name.starts_with('.account-tool-') { continue }
				path := base + '/image/usr/sbin/' + name
				os.rm(path)!
				os.symlink(base + '/outside/marker', path)!
			}
		}
		else { return error('unknown replacement') }
	}
}

fn short_write(fd int, data voidptr, count usize) isize { return C.write(fd, data, if count > 3 { 3 } else { count }) }
fn refuse_write(_ int, _ voidptr, _ usize) isize { return 0 }
fn refuse_flush(_ int) int { return -1 }
fn refuse_directory_flush(fd int) int {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 == 0o040000 { return -1 }
	return C.fsync(fd)
}

fn test_account_staging_captures_parents_and_preserves_outside_aliases() {
	for kind in ['usr', 'parent', 'leaf', 'hardlink', 'writable', 'root-alias', 'invalid'] {
		base := fixture()!
		defer { os.rmdir_all(base) or {}; unsafe { base.free() } }
		if kind == 'root-alias' {
			os.symlink(base + '/image', base + '/alias')!
			if mut installer := open(base + '/alias') { installer.close(); assert false } else { dispose(err) }
			continue
		}
		mut installer := open(base + '/image')!
		defer { installer.close() }
		match kind {
			'usr' { os.rename(base + '/image/usr', base + '/retained')!; os.symlink(base + '/outside', base + '/image/usr')! }
			'parent' { os.rename(base + '/image/usr/sbin', base + '/retained')!; os.symlink(base + '/outside', base + '/image/usr/sbin')! }
			'leaf' { os.rm(base + '/image/usr/sbin/vinix-authd')!; os.symlink(base + '/outside/marker', base + '/image/usr/sbin/vinix-authd')! }
			'hardlink' { os.rm(base + '/image/usr/sbin/vinix-authd')!; assert C.link((base + '/outside/marker').str, (base + '/image/usr/sbin/vinix-authd').str) == 0 }
			'writable' { os.chmod(base + '/image/usr/sbin', 0o777)! }
			else {}
		}
		if kind == 'invalid' {
			for relative in ['/usr/sbin/auth', '../outside/auth', 'usr/../auth', 'usr//auth', 'usr/sbin/auth\x00tail'] {
				refuse(&installer, base + '/source', relative)
			}
		} else { refuse(&installer, base + '/source', 'usr/sbin/vinix-authd') }
		assert os.read_file(base + '/outside/marker')! == 'outside preserved'
		assert os.ls(base + '/outside')!.len == 1
	}
}

fn test_account_staging_refuses_replaced_paths_before_publication() {
	for kind in ['root', 'parent', 'leaf', 'temporary'] {
		base := fixture()!
		defer { os.rmdir_all(base) or {}; unsafe { base.free() } }
		os.setenv('VINIX_ACCOUNT_STAGE_REPLACE', kind, true)
		mut installer := open(base + '/image')!
		defer { installer.close() }
		if _ := installer.put_with(base + '/source', 'usr/sbin/vinix-authd', 0o755, InstallOptions{ checkpoint: replace }) {
			assert false
		} else { dispose(err) }
		assert os.read_file(base + '/outside/marker')! == 'outside preserved'
		assert os.ls(base + '/outside')!.len == 1
		retained := if kind == 'root' { base + '/retained/usr/sbin' } else if kind == 'parent' { base + '/retained' } else { base + '/image/usr/sbin' }
		assert os.ls(retained)!.len == 1
		if kind != 'leaf' { assert os.read_file(retained + '/vinix-authd')! == 'old account executable' }
	}
}

fn test_account_staging_atomic_output_short_writes_and_failures() {
	for kind in ['success', 'short', 'write-failure', 'flush-failure', 'directory-flush-failure'] {
		base := fixture()!
		defer { os.rmdir_all(base) or {}; unsafe { base.free() } }
		mut installer := open(base + '/image')!
		defer { installer.close() }
		options := match kind {
			'short' { InstallOptions{ write: short_write } }
			'write-failure' { InstallOptions{ write: refuse_write } }
			'flush-failure' { InstallOptions{ flush: refuse_flush } }
			'directory-flush-failure' { InstallOptions{ flush: refuse_directory_flush } }
			else { InstallOptions{} }
		}
		if kind.ends_with('failure') {
			if _ := installer.put_with(base + '/source', 'usr/sbin/vinix-authd', 0o755, options) { assert false } else { dispose(err) }
			assert os.read_file(base + '/image/usr/sbin/vinix-authd')! == if kind == 'directory-flush-failure' { 'new account executable' } else { 'old account executable' }
		} else {
			installer.put_with(base + '/source', 'usr/sbin/vinix-authd', 0o755, options)!
			assert os.read_file(base + '/image/usr/sbin/vinix-authd')! == 'new account executable'
			assert os.lstat(base + '/image/usr/sbin/vinix-authd')!.mode & 0o777 == 0o755
			installer.put(base + '/source', 'usr/share/vinix/actions/packages-launch', 0o644)!
			assert os.read_file(base + '/image/usr/share/vinix/actions/packages-launch')! == 'new account executable'
			assert os.lstat(base + '/image/usr/share/vinix/actions/packages-launch')!.mode & 0o777 == 0o644
		}
		assert os.ls(base + '/image/usr/sbin')!.len == 1
		installer.close()
		installer.close()
	}
}
