// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import cachecli

pub struct InputError {
pub:
	message string
}
pub fn (failure InputError) msg() string { return failure.message }
pub fn (failure InputError) code() int { return 2 }

fn parse_arguments(argv []string, scalar []string, repeated []string, flags []string, minimum int, maximum int, usage string) !cachecli.Arguments {
	return cachecli.arguments(argv, scalar, repeated, flags, minimum, maximum, usage) or { return InputError{err.msg()} }
}

fn required_value(args cachecli.Arguments, flag string) !string { return args.required(flag) or { return InputError{err.msg()} } }

pub fn failure_status(err IError) int {
	if cachecli.cancelled() { return cachecli.interrupt_status() }
	return if err is InputError { 2 } else { 1 }
}
