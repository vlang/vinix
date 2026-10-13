// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import devcore
import json2
import os
import time

pub const catalog = ['c', 'cpp', 'v', 'node', 'typescript', 'rust', 'cargo', 'go', 'java', 'make',
	'cmake', 'ninja', 'npm', 'gdb', 'sqlite']
const marker = 'VINIX-TOOLCHAIN:PASS'

struct MissingTool {
	name string
}

fn (err MissingTool) msg() string { return 'missing tool: ' + err.name }

fn (err MissingTool) code() int { return 1 }

pub struct CommandReceipt {
pub:
	argv              []string
	executable_sha256 string
	exit_code         int
	log               string
}

pub struct Verdict {
pub:
	profile  string
	status   string
	detail   string
	commands []CommandReceipt
}

pub struct Report {
pub:
	schema        int = 1
	kernel        string
	release       string
	architecture  string
	uid           int
	context       string
	runner_sha256 string
	started       string
	requested     []string
	command_timeout_seconds int = 120
pub mut:
	complete            bool
	all_selected_passed bool
	results             []Verdict
}

struct Runner {
	work string
	env  map[string]string
	timeout_seconds int = 120
mut:
	commands []CommandReceipt
}

fn tool(name string) !string {
	return os.find_abs_path_of_executable(name) or { return MissingTool{name} }
}

fn (mut runner Runner) command(program string, arguments []string) !string {
	executable := if program.contains('/') { program } else { tool(program)! }
	argv := [executable, ...arguments]
	log := runner.work + '/command-${runner.commands.len}.log'
	hash := devcore.file_hash(executable)!
	status := devcore.run(argv, runner.work, runner.env, runner.timeout_seconds, log) or {
		runner.commands << CommandReceipt{argv, hash, -1, log}
		return err
	}
	runner.commands << CommandReceipt{argv, hash, status, log}
	if status != 0 { return error('command failed with ${status}: ${log}') }
	if os.stat(log)!.size > 1024 * 1024 { return error('command output exceeds 1 MiB: ${log}') }
	return os.read_file(log)!
}

fn (mut runner Runner) write(name string, text string) ! {
	os.write_file(runner.work + '/' + name, text)!
}

fn (mut runner Runner) verify_binary(name string) ! {
	output := runner.command(runner.work + '/' + name, [])!
	if output.trim_space() != marker { return error('compiled project returned unexpected output') }
}

fn command_timeout(value string) !int {
	if value.len < 1 || value.len > 5 || !value.bytes().all(it >= `0` && it <= `9`)
		|| value.int() < 1 || value.int() > 86400 {
		return error('VINIX_QUALIFY_TIMEOUT_SECONDS must be 1..86400 seconds')
	}
	return value.int()
}

pub fn qualify(profiles []string, output_path string, require_vinix bool) !Report {
	timeout := if value := os.getenv_opt('VINIX_QUALIFY_TIMEOUT_SECONDS') { command_timeout(value)! } else { 120 }
	if profiles.len == 0 || profiles.any(it !in catalog) {
		return error('unknown or empty qualification profile')
	}
	mut selected := map[string]bool{}
	for profile in profiles {
		if selected[profile] { return error('duplicate qualification profile: ${profile}') }
		selected[profile] = true
	}
	uname := os.uname()
	native := uname.sysname.to_lower() == 'vinix'
	if require_vinix && !native {
		return error('guest qualification requires an installed Vinix system')
	}
	devcore.fresh_directory(output_path)!
	output := os.real_path(output_path)
	mut report := Report{
		kernel:        uname.sysname
		release:       uname.release
		architecture:  uname.machine
		uid:           os.getuid()
		context:       if native { 'vinix-native' } else { 'host-only' }
		runner_sha256: devcore.file_hash(os.executable())!
		started:       time.now().format_rfc3339()
		requested:     profiles
		command_timeout_seconds: timeout
	}
	mut passed := true
	os.write_file(output + '/report.json', json2.encode(report, prettify: true) + '\n')!
	for profile in profiles {
		work := output + '/' + profile
		devcore.fresh_directory(work)!
		os.mkdir(work + '/home', mode: 0o700)!
		os.mkdir(work + '/tmp', mode: 0o700)!
		mut env := devcore.environment(1700000000)
		env['HOME'] = work + '/home'
		env['TMPDIR'] = work + '/tmp'
		env['CARGO_HOME'] = work + '/home/cargo'
		env['GOCACHE'] = work + '/home/go-cache'
		env['GOPATH'] = work + '/home/go'
		env['GOPROXY'] = 'off'
		env['GOSUMDB'] = 'off'
		env['GOENV'] = 'off'
		env['GOTOOLCHAIN'] = 'local'
		env['npm_config_cache'] = work + '/home/npm-cache'
		env['VJOBS'] = '1'
		env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
		mut runner := Runner{ work: work, env: env, timeout_seconds: timeout }
		mut status := 'passed'
		mut detail := 'project compiled and completed its checks'
		runner.profile(profile) or {
			status = if err is MissingTool { 'unsupported' } else { 'failed' }
			detail = err.msg()
			passed = false
		}
		report.results << Verdict{profile, status, detail, runner.commands}
		os.write_file(output + '/report.json', json2.encode(report, prettify: true) + '\n')!
		println('${profile}: ${status} (${detail})')
	}
	report.complete = true
	report.all_selected_passed = passed
	os.write_file(output + '/report.json', json2.encode(report, prettify: true) + '\n')!
	return report
}
