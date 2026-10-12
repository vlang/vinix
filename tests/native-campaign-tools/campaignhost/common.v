// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import allocationhost
import cachecli
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand
import time

pub struct Context {
pub:
	root   string
	state  string
	origin string
}

pub fn now() string { return allocationhost.utc_text(time.utc()) }

pub fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

pub fn read_json(path string) !map[string]json2.Any {
	return hosttest.decode_json(os.read_file(path)!)!.as_map().clone()
}

pub fn copy_record(value map[string]json2.Any) !map[string]json2.Any {
	return hosttest.decode_json(json2.encode(value))!.as_map().clone()
}

pub fn write_json(path string, data json2.Any) ! {
	hosttest.write_json(path, data)!
}

pub fn atomic_json(path string, data json2.Any) ! {
	temporary := path + '.tmp'
	write_json(temporary, data)!
	if C.rename(temporary.str, path.str) != 0 { return os.error_posix() }
}

pub fn checked_hash(path string, expected string) !string {
	actual := digest(path)!
	if actual != expected {
		return error('Hash mismatch ' + path + ': ' + actual + ' != ' + expected)
	}
	return actual
}

pub fn text(path string) !string {
	contents := os.read_file(path)!
	hosttest.module_decode_utf8(contents)!
	return contents.replace('\r\n', '\n').replace('\r', '\n')
}

pub fn env_merge(extra map[string]json2.Any) !map[string]string {
	mut env := os.environ()
	for key, value in extra {
		if value !is string { return error('environment value must be a string: ' + key) }
		env[key] = value.str()
	}
	return env
}

struct Wait {
	timeout f64 = -1
	started u64
	pidfile string
}

fn wait_child(pid int, pointer voidptr) ! {
	context := unsafe { &Wait(pointer) }
	if context.pidfile != '' { os.write_file(context.pidfile, pid.str() + '\n')! }
	for !sourcecommand.child_exited(pid)! {
		cachecli.checkpoint()!
		if context.timeout >= 0 && f64(time.sys_mono_now() - context.started) >= context.timeout * f64(time.second) {
			return error('command timed out')
		}
		time.sleep(20 * time.millisecond)
	}
}

pub fn logged(command []string, log string, environment map[string]string, directory string, pidfile string) !int {
	return logged_grace(command, log, environment, directory, pidfile, 0)!
}

pub fn logged_grace(command []string, log string, environment map[string]string, directory string, pidfile string, grace f64) !int {
	cachecli.checkpoint()!
	context := Wait{ started: time.sys_mono_now(), pidfile: pidfile }
	result := sourcecommand.run_logged_owned(command, environment, cachecli.cancelled, log, false, directory, wait_child, unsafe { &context }, grace)!
	cachecli.checkpoint()!
	return result.status
}

pub fn checked(command []string, directory string, environment map[string]string, log string) ! {
	status := logged(command, log, environment, directory, '')!
	if status != 0 {
		return error('Command exit ' + status.str() + ': ' + command.str() + '; see ' + log)
	}
}

pub fn captured(command []string) !string {
	result := sourcecommand.capture(command, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error(command.str() + '\n' + result.stdout + result.stderr) }
	hosttest.module_decode_utf8(result.stdout)!
	return result.stdout
}

pub fn captured_at(command []string, directory string) !string {
	previous := os.getwd()
	os.chdir(directory)!
	defer { os.chdir(previous) or { eprintln(err) } }
	return captured(command)!
}

pub fn strings(data json2.Any) ![]string {
	if data !is []json2.Any { return error('command must be an array') }
	mut result := []string{}
	for value in data.as_array() {
		if value !is string { return error('command arguments must be strings') }
		result << value.str()
	}
	return result
}

pub fn is_zero(data json2.Any) bool {
	return match data {
		int { data == 0 }
		i64 { data == 0 }
		u64 { data == 0 }
		f64 { data == 0 }
		bool { !data }
		else { false }
	}
}

pub fn mkdirs(path string) ! {
	if os.is_dir(path) { return }
	parent := path.all_before_last('/')
	if parent != '' && parent != path { mkdirs(parent)! }
	os.mkdir(path)!
}

pub fn interrupted_status(err IError) int {
	eprintln(err)
	return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
}
