// SPDX-License-Identifier: GPL-2.0-only
module policyhost
import encoding.hex
import fixturehost
import hosttest
import json2
import os

pub struct PolicyError { pub: kind string message string }
pub fn (e PolicyError) msg() string { return e.message }
pub fn (e PolicyError) code() int { return 0 }
fn failure(kind string, message string) IError { return PolicyError{kind, message} }
fn text(row map[string]json2.Any, name string) string { return (row[name] or { json2.Any('') }).str() }
fn decoded(value string) !string { return hex.decode(value)!.bytestr() }
fn read_text(path string) !string { return hosttest.module_read_text(path)! }
fn read_bytes(path string) ![]u8 { return fixturehost.read(path)!.bytes() }
fn write_text(path string, content string) ! { hosttest.module_write_text(path, content)! }
fn temporary(prefix string) !string { return hosttest.work_dir('', prefix)! }
fn retire(path string) ! { hosttest.remove_work_dir(path)! }
fn caller_arch() string {
	$if amd64 { return 'amd64' } $else { return 'arm64' }
}
fn run(argv []string) ! {
	fixturehost.inherited_command_environment_preferred(argv, os.environ(), caller_arch())!
}
fn output(argv []string) !string {
	return fixturehost.capture_in_preferred(argv, '', os.environ(), false, '', false, caller_arch())!
}
fn emit(value string) ! { println(value) }
