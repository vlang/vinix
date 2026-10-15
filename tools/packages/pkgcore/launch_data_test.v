// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import net.unix

#include <sys/wait.h>
#include <sys/resource.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct LaunchDataLimit { current u64 maximum u64 }

fn launch_data_work() !string {
	path := os.real_path(os.temp_dir()) + '/vlaunch-data-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path)!
	return path
}

fn launch_data_refusal(home string, id string, uid u32) {
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.alarm(2)
		prepare_launch_data(home, id, uid) or { C._exit(0) }
		C._exit(42)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child
	assert status == 0, '${home}/${id}: refused promptly, wait status ${status}'
}

fn test_launch_data_creates_private_owned_directories_preserves_content_and_supports_inventory_purge() {
	work := launch_data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	os.mkdir(home)!
	os.chmod(home, 0o755)!
	uid := u32(os.geteuid())
	prepare_launch_data(home, 'app', uid)!
	data := home + '/.local/share/vinix-apps/app'
	for part in ['.local', '.local/share', '.local/share/vinix-apps', '.local/share/vinix-apps/app', '.local/share/vinix-apps/app/tmp'] {
		info := os.lstat(home + '/' + part)!
		assert info.uid == uid && info.mode & 0o777 == 0o700
	}
	assert os.lstat(home)!.mode & 0o777 == 0o755
	os.write_file(data + '/kept', 'application data')!
	os.write_file(data + '/tmp/kept', 'temporary data')!
	os.chmod(data, 0o755)!
	os.chmod(data + '/tmp', 0o755)!
	prepare_launch_data(home + '/', 'app', uid)!
	assert os.lstat(data)!.mode & 0o777 == 0o700 && os.lstat(data + '/tmp')!.mode & 0o777 == 0o700
	assert os.read_file(data + '/kept')! == 'application data' && os.read_file(data + '/tmp/kept')! == 'temporary data'
	mut status := personal_data_inventory(home, uid, State{})!
	assert status.rows.len == 1 && status.rows[0].id == 'app' && status.rows[0].diagnostic == ''
	status.close()
	assert purge_personal_data(home, 'app', uid)!
	prepare_launch_data(home, 'app', uid)!
	assert os.is_dir(data + '/tmp') && !os.exists(data + '/kept')
	println('Launch data: private owned creation, retained contents, existing modes, inventory, purge and recreation passed')
}

fn test_launch_data_refuses_unsafe_components_without_following_links_or_opening_special_files() {
	for part in ['.local', '.local/share', '.local/share/vinix-apps', '.local/share/vinix-apps/app', '.local/share/vinix-apps/app/tmp'] {
		for kind in ['symlink', 'dangling', 'fifo', 'regular'] {
			work := launch_data_work()!
			defer { os.rmdir_all(work) or { panic(err) } }
			home := work + '/home'
			path := home + '/' + part
			os.mkdir_all(os.dir(path))!
			outside := work + '/outside'
			os.mkdir(outside)!
			os.chmod(outside, 0o755)!
			os.write_file(outside + '/kept', 'outside')!
			match kind {
				'symlink' { os.symlink(outside, path)! }
				'dangling' { os.symlink(outside + '/absent', path)! }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				else { os.write_file(path, 'preserved')! }
			}
			before := os.lstat(path)!
			launch_data_refusal(home, 'app', u32(os.geteuid()))
			after := os.lstat(path)!
			assert before.inode == after.inode && before.mode == after.mode
			assert os.ls(outside)! == ['kept'] && os.read_file(outside + '/kept')! == 'outside'
			assert os.lstat(outside)!.mode & 0o777 == 0o755
		}
	}
	for part in ['.local/share/vinix-apps/app', '.local/share/vinix-apps/app/tmp'] {
		work := launch_data_work()!
		defer { os.rmdir_all(work) or { panic(err) } }
		home := work + '/home'
		path := home + '/' + part
		os.mkdir_all(os.dir(path))!
		mut socket := unix.listen_stream(path, unix.ListenOptions{})!
		defer { socket.close() or {} }
		launch_data_refusal(home, 'app', u32(os.geteuid()))
		assert os.lstat(path)!.get_filetype() == .socket
	}
	println('Launch data: every parent/app/tmp alias, dangling link, FIFO, regular file and app/tmp socket refuses within two seconds')
}

fn test_launch_data_refuses_shared_or_foreign_directories_and_invalid_home_or_id() {
	for part in ['', '/.local', '/.local/share', '/.local/share/vinix-apps', '/.local/share/vinix-apps/app', '/.local/share/vinix-apps/app/tmp'] {
		work := launch_data_work()!
		defer { os.rmdir_all(work) or { panic(err) } }
		home := work + '/home'
		data := home + '/.local/share/vinix-apps/app'
		os.mkdir_all(data + '/tmp')!
		os.chmod(data, 0o755)!
		os.chmod(home + part, 0o777)!
		launch_data_refusal(home, 'app', u32(os.geteuid()))
		assert os.lstat(home + part)!.mode & 0o777 == 0o777
		if part != '/.local/share/vinix-apps/app' { assert os.lstat(data)!.mode & 0o777 == 0o755 }
	}
	work := launch_data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	os.mkdir(home)!
	for invalid in ['', '/', 'relative', home + '/../home', home + '//child', home + '/.'] { launch_data_refusal(invalid, 'app', u32(os.geteuid())) }
	for invalid in ['', '../outside', '/outside', 'App'] { launch_data_refusal(home, invalid, u32(os.geteuid())) }
	launch_data_refusal(home, 'app', u32(os.geteuid()) + 1)
	os.symlink(home, work + '/home-alias')!
	launch_data_refusal(work + '/home-alias', 'app', u32(os.geteuid()))
	assert !os.exists(home + '/.local')
	// Check the child ownership gate independently of the home gate.
	os.mkdir(home + '/child')!
	parent := C.open(home.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	assert parent >= 0
	defer { C.close(parent) }
	mut foreign := false
	personal_data_child(parent, 'child', u32(os.geteuid()) + 1, true) or { foreign = true }
	assert foreign
}

fn test_launch_data_repeated_success_and_failure_retires_descriptors_with_low_limit() {
	work := launch_data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	os.mkdir(home)!
	prepare_launch_data(home, 'app', u32(os.geteuid()))!
	data := home + '/.local/share/vinix-apps/app'
	mut original := LaunchDataLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := LaunchDataLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 { prepare_launch_data(home, 'app', u32(os.geteuid()))! }
	os.rmdir(data + '/tmp')!
	os.symlink(work, data + '/tmp')!
	for _ in 0 .. 128 {
		mut refused := false
		prepare_launch_data(home, 'app', u32(os.geteuid())) or { refused = true }
		assert refused
	}
	os.rm(data + '/tmp')!
	prepare_launch_data(home, 'app', u32(os.geteuid()))!
	println('Launch data: 128 success/refusal cycles under a 32-descriptor limit and restored-directory retry passed')
}

fn test_launch_refuses_aliased_app_data_before_creating_or_chmodding_the_target() {
	if os.geteuid() == 0 || C.getegid() == 0 { return }
	work := launch_data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	parent := home + '/.local/share/vinix-apps'
	os.mkdir_all(parent)!
	os.mkdir(work + '/outside')!
	os.chmod(work + '/outside', 0o755)!
	os.write_file(work + '/outside/kept', 'preserved')!
	os.symlink(work + '/outside', parent + '/app')!
	directory := work + '/store'
	file := directory + '/generations/1/apps/app/bin/app'
	os.mkdir_all(os.dir(file))!
	// Invalid ELF bytes: even a regression must never run a synthetic script.
	os.write_file(file, '\x7fELFfixture')!
	os.chmod(file, 0o755)!
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'fixture', public_key: key }] }
	app := Package{ id: 'app', name: 'App', version: '1.0.0', architecture: 'aarch64', kind: 'native', license: 'MIT', entrypoint: 'bin/app',
		files: [Payload{ path: 'bin/app', bytes: os.file_size(file), sha256: hash_file(file)!, executable: true }] }
	state := State{ generation: 1, architecture: 'aarch64', requested: ['app'], packages: [Installed{ package: app, repository: 'fixture', public_key: key, sequence: 1 }] }
	os.mkdir_all(directory + '/generations/1/share/applications')!
	os.write_file(directory + '/generations/1/share/applications/vinix-app.desktop', desktop_entry(app))!
	original_home := os.getenv('HOME')
	os.setenv('HOME', home, true)
	defer { os.setenv('HOME', original_home, true) }
	mut refused := false
	run_leased_mode(config, directory, state, 'app', LaunchInput{}) or { refused = err.msg().contains('ordinary directory') }
	println('Launch alias probe: refused=${refused} outside_tmp=${os.exists(work + '/outside/tmp')} outside_mode=${os.lstat(work + '/outside')!.mode & 0o777}')
	assert refused && !os.exists(work + '/outside/tmp') && os.lstat(work + '/outside')!.mode & 0o777 == 0o755
	assert os.read_file(work + '/outside/kept')! == 'preserved' && os.is_link(parent + '/app')
}
