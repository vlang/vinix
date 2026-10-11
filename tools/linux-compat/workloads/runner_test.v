module main

import os
import time

fn test_nonzero_and_timeout_are_retained_as_failures() {
	work := os.join_path(os.temp_dir(), 'vinix-workload-test-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	mut suite := Suite{ work: work, path: 'native-aarch64', timeout: 1 }
	suite.execute('false', []) or {
		assert suite.commands.len == 1 && suite.commands[0].exit_code != 0
		assert os.is_file(work + '/command-1.json')
		suite.execute('sleep', ['5']) or {
			assert suite.commands.len == 2 && suite.commands[1].timed_out
			assert os.is_file(work + '/command-2.json')
			return
		}
		assert false, 'timeout was accepted'
		return
	}
	assert false, 'nonzero exit was accepted'
}

fn test_missing_dependency_is_not_a_passing_command() {
	mut suite := Suite{ path: 'native-aarch64', timeout: 1 }
	suite.execute('/vinix-nonexistent-compat-fixture', []) or {
		assert err.msg().starts_with('unsupported:')
		assert suite.commands.len == 0
		return
	}
	assert false, 'missing dependency was accepted'
}

fn test_child_environment_is_recorded_without_changing_parent() {
	work := os.join_path(os.temp_dir(), 'vinix-workload-env-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	key := 'VINIX_COMPAT_WORKLOAD_ENV_${os.getpid()}'
	assert os.getenv_opt(key) == none
	mut suite := Suite{ work: work, path: 'native-aarch64', timeout: 1 }
	suite.environment[key] = '42 with spaces'
	assert suite.execute('printenv', [key])!.trim_space() == '42 with spaces'
	assert suite.commands[0].environment_overrides[key] == '42 with spaces'
	assert os.getenv_opt(key) == none
	suite.environment.clear()
	suite.execute('printenv', [key]) or {
		assert suite.commands.len == 2 && suite.commands[1].exit_code != 0
		assert suite.commands[1].environment_overrides.len == 0
		return
	}
	assert false, 'child environment leaked into the parent'
}
