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
	config.validate()!
	if config.launch_user == '' {
		return error('run from an ordinary user session, or configure launch_user for the root desktop')
	}
	if !executable.starts_with('/') || !printable(executable, 4096) || !identifier(id) {
		return error('invalid isolated package launch')
	}
	for document in documents {
		if !document.starts_with('/') || !printable(document, 4096) {
			return error('invalid launch document')
		}
	}
	return Launch{
		program:   '/usr/sbin/vinix-session'
		directory: '/'
		arguments: ['run', '--isolated', config.launch_user, executable, if terminal { 'run-terminal' } else { 'run' }, id, ...documents]
	}
}

pub fn run_in_session(config Config, id string, documents []string) !int {
	return run_in_session_mode(config, id, documents, false)
}

fn run_in_session_mode(config Config, id string, documents []string, terminal bool) !int {
	if os.geteuid() != 0 {
		return error('only the administrator can create an isolated package session')
	}
	launch := launch_session_mode(config, os.executable(), id, documents, terminal)!
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
