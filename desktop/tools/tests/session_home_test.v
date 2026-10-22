// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_session_identity_requires_an_effective_account_for_ordinary_users() {
	root := desktop_missing_identity(0)!
	assert root.uid == 0 && root.name == 'root' && root.home == '/root'
	if _ := desktop_missing_identity(1000) {
		assert false, 'an ordinary account must never inherit the root fallback'
	}
	user := desktop_account_identity(1000, 'alex', '/home/alex', '/bin/zsh')!
	assert user.uid == 1000 && user.name == 'alex'
	assert user.home == '/home/alex' && user.shell == '/bin/zsh'
	assert desktop_account_identity(1000, 'alex', '/home/alex', '')!.shell == '/bin/sh'
	for path in ['', 'relative', '/home/alex\nHOME=/root', '/home/alex\x00suffix'] {
		if _ := desktop_account_identity(1000, 'alex', path, '/bin/sh') {
			assert false, 'invalid home accepted'
		}
	}
	for name in ['', 'root\nHOME=/root', 'alex=admin', '../alex'] {
		if _ := desktop_account_identity(1000, name, '/home/alex', '/bin/sh') {
			assert false, 'invalid account name accepted'
		}
	}
}

fn test_session_identity_ignores_inherited_home_and_identity() {
	before := desktop_session_identity()
	keys := ['HOME', 'USER', 'LOGNAME', 'SHELL']
	mut previous := []?string{}
	for key in keys {
		previous << os.getenv_opt(key)
		os.setenv(key, '/root', true)
	}
	defer {
		for index, key in keys {
			if value := previous[index] { os.setenv(key, value, true) } else { os.unsetenv(key) }
		}
	}
	after := desktop_session_identity()
	assert after.uid == u32(C.geteuid())
	assert after.name == before.name && after.home == before.home && after.shell == before.shell
	assert desktop_home == before.home
	assert desktop_uses_account_home(desktop_home) == (before.uid != 0)
	assert desktop_user_entry == 'USER=${before.name}'
	assert desktop_logname_entry == 'LOGNAME=${before.name}'
	assert desktop_shell_entry == 'SHELL=${before.shell}'
	assert desktop_runtime_entry == 'XDG_RUNTIME_DIR=/run/user/${before.uid}'
	assert desktop_config_entry == 'XDG_CONFIG_HOME=${before.home}/.config'
	assert desktop_cache_entry == 'XDG_CACHE_HOME=${before.home}/.cache'
	assert desktop_data_entry == 'XDG_DATA_HOME=${before.home}/.local/share'
	assert desktop_state_entry == 'XDG_STATE_HOME=${before.home}/.local/state'
}

fn test_account_home_setup_preserves_the_existing_account_layout() {
	home := os.join_path(os.temp_dir(), 'vinix-account-home-${os.getpid()}')
	os.mkdir(home, mode: 0o700)!
	defer { os.rmdir_all(home) or {} }
	os.mkdir('${home}/Documents', mode: 0o700)!
	os.write_file('${home}/Documents/keep.txt', 'existing account data')!
	assert desktop_prepare_account_home(home) == home
	assert os.stat(home)!.mode & 0o777 == 0o700
	assert os.stat('${home}/Documents')!.mode & 0o777 == 0o700
	assert os.read_file('${home}/Documents/keep.txt')! == 'existing account data'
	for folder in desktop_user_folders {
		assert os.is_dir('${home}/${folder.name}')
	}
	assert !os.exists('${home}/home')
	assert !os.exists('${home}/.vinix-user')
	config := '${home}/.config/user-dirs.dirs'
	assert os.read_file(config)!.contains('XDG_DOWNLOAD_DIR="${home}/Downloads"')
	os.write_file(config, 'existing user configuration')!
	os.write_file('${home}/.vinix-user', 'legacy record is not required')!
	assert desktop_prepare_account_home(home) == home
	assert os.read_file(config)! == 'existing user configuration'
	assert os.read_file('${home}/.vinix-user')! == 'legacy record is not required'
}

fn test_terminal_child_receives_the_effective_identity_and_home() {
	command := r'printf "HOME=%s|USER=%s|LOGNAME=%s|SHELL=%s|RUNTIME=%s|CONFIG=%s|CACHE=%s|DATA=%s|STATE=%s|PWD=%s" "$HOME" "$USER" "$LOGNAME" "$SHELL" "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$PWD"'
	child := desktop_spawn_shell('/bin/sh', command, 24, 80, 640, 480) or {
		panic('could not start a terminal child')
	}
	mut reaped := false
	defer {
		desktop_close(child.terminal)
		if !reaped { desktop_terminate_child(child.pid) }
	}
	expected := 'HOME=${desktop_home}|USER=${desktop_identity.name}|LOGNAME=${desktop_identity.name}|SHELL=${desktop_identity.shell}|RUNTIME=/run/user/${desktop_identity.uid}|CONFIG=${desktop_home}/.config|CACHE=${desktop_home}/.cache|DATA=${desktop_home}/.local/share|STATE=${desktop_home}/.local/state|PWD=${os.real_path(desktop_home)}'
	mut buffer := []u8{len: expected.len}
	// A PTY can hold its writer in close until the master drains the output.
	assert desktop_read_all_with_timeout(child.terminal, buffer.data, u64(buffer.len), 5000)
	output := unsafe { tos(buffer.data, buffer.len) }
	assert output == expected
	mut status := 0
	for _ in 0 .. 5000 {
		if C.waitpid(child.pid, &status, C.WNOHANG) == child.pid {
			reaped = true
			break
		}
		desktop_sleep_ms(1)
	}
	assert reaped
	assert status == 0
}
