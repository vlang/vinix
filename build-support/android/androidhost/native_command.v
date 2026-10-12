// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module androidhost

import os

pub type NativeCommandRunner = fn ([]string, bool, string) !string

__global native_command_runner NativeCommandRunner

pub fn set_command_runner(runner NativeCommandRunner) NativeCommandRunner {
	previous := native_command_runner
	native_command_runner = runner
	return previous
}

pub fn command_spawn_error(program string, number int) IError {
	return FileError{message: os.get_error_msg(number), number: number, filename: program}
}

pub fn command_failure(arguments []string, status int, capture bool, output string) IError {
	if capture { return ProbeCaptureError{arguments.clone(), status, output} }
	return ProbeCommandError{arguments.clone(), status}
}
