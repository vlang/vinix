// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn launch_account_name(value string) bool {
	if value.len == 0 || value.len > 32 || !((value[0] >= `a` && value[0] <= `z`) || value[0] == `_`) {
		return false
	}
	for byte in value {
		if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [
			`_`,
			`-`,
		]) {
			return false
		}
	}
	return true
}

// Root's desktop is an administrator, not an application identity. An explicit
// root-owned configuration selects a person; no environment UID, HOME or package
// metadata can select credentials. The session tool checks the account database
// and irreversibly drops privileges before this service is started again.
pub fn launch_session(config Config, executable string, id string, documents []string) !Launch {
	return launch_session_mode(config, executable, id, documents, false)
}

fn launch_session_mode(config Config, executable string, id string, documents []string, terminal bool) !Launch {
	return launch_session_request(config, executable, id, LaunchInput{ documents: documents, terminal: terminal })
}

fn launch_session_request(config Config, executable string, id string, input LaunchInput) !Launch {
	config.validate()!
	if config.launch_user == '' {
		return error('run from an ordinary user session, or configure launch_user for the root desktop')
	}
	if !executable.starts_with('/') || !printable(executable, 4096) || !identifier(id) {
		return error('invalid isolated package launch')
	}
	for document in input.documents {
		if !document.starts_with('/') || !printable(document, 4096) {
			return error('invalid launch document')
		}
	}
	if input.command { validate_command(CommandLaunch{ arguments: input.arguments, documents: input.documents })! }
	command := if input.window { 'run-window' } else if input.command { if input.terminal { 'run-terminal-args' } else { 'run-args' } }
		else { if input.terminal { 'run-terminal' } else { 'run' } }
	mut argv := ['run', '--isolated', config.launch_user.clone(), executable.clone(), command.clone(), id.clone()]
	unsafe { argv.flags |= .noslices }
	if input.command {
		if input.data_cwd { argv << '--data-cwd' }
		for document in input.documents { argv << '--file'; argv << document.clone() }
		argv << '--'
		for argument in input.arguments { argv << argument.clone() }
	} else { for document in input.documents { argv << document.clone() } }
	return Launch{
		program:   '/usr/sbin/vinix-session'
		directory: '/'
		arguments: argv
	}
}

pub fn run_in_session(config Config, id string, documents []string) !int {
	return run_in_session_mode(config, id, documents, false)
}

fn run_in_session_mode(config Config, id string, documents []string, terminal bool) !int {
	return run_in_session_request(config, id, LaunchInput{ documents: documents, terminal: terminal })
}

fn session_executable() !string {
	$if linux {
		// The pinned os.executable moves its path buffer to an unretired heap
		// allocation. Read the kernel identity with bounded stack scratch instead.
		mut bytes := [4097]u8{}
		count := C.readlinkat(C.AT_FDCWD, c'/proc/self/exe', unsafe { &bytes[0] }, usize(bytes.len))
		if count <= 0 || count > 4096 {
			return error('cannot determine package service executable from /proc/self/exe')
		}
		return unsafe { tos(&bytes[0], int(count)).clone() }
	} $else { return os.executable() }
}

fn run_in_session_request(config Config, id string, input LaunchInput) !int {
	if os.geteuid() != 0 {
		return error('only the administrator can create an isolated package session')
	}
	executable := session_executable()!
	defer { unsafe { executable.free() } }
	mut launch := launch_session_request(config, executable, id, input)!
	defer { launch.close() }
	if !os.is_executable(launch.program) {
		return error('the account session tool is missing: ${launch.program}')
	}
	mut process := os.new_process(launch.program)
	process.set_args(launch.arguments)
	process.set_work_folder(launch.directory)
	process.wait()
	code := process.code
	process.close()
	return code
}
