// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The command line, and the run it describes: which scenarios, in which
// directory, and what is printed about each.
module hwhost

import os

pub const usage = "Usage: run --arch aarch64|x86_64 --kernel PATH [--scenario NAME]...
           [--state-dir DIR] [--timeout SECONDS] [--qemu PATH]
       run --list [--arch aarch64|x86_64]

Boots a built kernel in QEMU with a V test program as its init, and judges
each scenario by what the guest prints on the serial port.

  --arch ARCH        the kernel's architecture
  --kernel PATH      the kernel to boot (bin/vinix of a kernel build)
  --scenario NAME    run this scenario; may be repeated. Without it every
                     scenario for the architecture runs, except pending ones
  --list             print the scenarios and exit
  --state-dir DIR    keep each scenario's logs and images in DIR/<scenario>;
                     DIR must be empty or not exist yet
  --failures-only    with --state-dir: keep the images only of scenarios that
                     failed; the logs of all of them stay
  --timeout SECONDS  how long one scenario's machine may run (default 120)
  --qemu PATH        the QEMU to use instead of the one on PATH"

pub struct Options {
pub mut:
	arch      string
	kernel    string
	scenarios []string
	list      bool
	help      bool
	state_dir string
	// With a state directory: the images of a scenario that passed are
	// deleted as they are without one.
	failures_only bool
	timeout       int = 120
	qemu          string
}

// Options take their value as the next argument or after `=`.
pub fn parse_options(arguments []string) !Options {
	mut options := Options{}
	mut index := 0
	for index < arguments.len {
		argument := arguments[index]
		index++
		name := argument.all_before('=')
		if name in ['-h', '--help'] {
			options.help = true
			continue
		}
		if name == '--list' {
			if argument.contains('=') {
				return error('--list takes no value')
			}
			options.list = true
			continue
		}
		if name == '--failures-only' {
			if argument.contains('=') {
				return error('--failures-only takes no value')
			}
			options.failures_only = true
			continue
		}
		if name !in ['--arch', '--kernel', '--scenario', '--state-dir', '--timeout', '--qemu'] {
			return error('unknown argument: ${argument}')
		}
		mut value := ''
		if argument.contains('=') {
			value = argument.all_after_first('=')
		} else {
			if index >= arguments.len {
				return error('${name} needs a value')
			}
			value = arguments[index]
			index++
		}
		if value == '' {
			return error('${name} needs a value')
		}
		match name {
			'--arch' {
				if value !in architectures {
					return error('--arch is ${architectures.join(' or ')}, not ${value}')
				}
				options.arch = value
			}
			'--kernel' {
				options.kernel = value
			}
			'--scenario' {
				options.scenarios << value
			}
			'--state-dir' {
				options.state_dir = value
			}
			'--timeout' {
				seconds := value.int()
				if seconds <= 0 || seconds.str() != value {
					return error('--timeout is a positive number of seconds, not ${value}')
				}
				options.timeout = seconds
			}
			'--qemu' {
				options.qemu = value
			}
			else {}
		}
	}
	if options.help || options.list {
		return options
	}
	if options.arch == '' {
		return error('--arch is required')
	}
	if options.kernel == '' {
		return error('--kernel is required')
	}
	if options.failures_only && options.state_dir == '' {
		return error('--failures-only is about what --state-dir keeps')
	}
	return options
}

// One line per scenario: name, architectures, what it covers.
pub fn list_text(all []Scenario, arch string) string {
	mut width := 0
	for scenario in all {
		if scenario.name.len > width {
			width = scenario.name.len
		}
	}
	mut lines := []string{}
	for scenario in all {
		if arch != '' && arch !in scenario.arches {
			continue
		}
		mut about := scenario.about
		if scenario.left_out() != '' {
			about += ' (${scenario.left_out()})'
		}
		padding := ' '.repeat(width - scenario.name.len)
		lines << '${scenario.name}${padding}  ${scenario.arches.join(',')}  ${about}'
	}
	return lines.join('\n')
}

// The verdict line of a scenario, and under it what explains it.
pub fn report(arch string, outcome Outcome) string {
	verdict := if outcome.passed { 'PASS' } else { 'FAIL' }
	mut lines := ['${verdict} ${arch} ${outcome.scenario} (${outcome.seconds:.1f}s)']
	if !outcome.passed {
		lines << '  ${outcome.reason}'
	}
	for note in outcome.notes {
		lines << '  ${note}'
	}
	if !outcome.passed {
		if outcome.tail.len > 0 {
			lines << '  last ${outcome.tail.len} serial lines:'
			for line in outcome.tail {
				lines << '  | ${line}'
			}
		} else {
			lines << '  nothing was printed on the serial port'
		}
		lines << '  logs: ${outcome.state}'
	}
	return lines.join('\n')
}

// Deletes a directory tree the controller made. A symbolic link is removed,
// never followed: the ISO build directory links to a download cache that
// other checkouts share.
fn remove_tree(path string) {
	if os.is_link(path) || !os.is_dir(path) {
		os.rm(path) or {}
		return
	}
	entries := os.ls(path) or { []string{} }
	for entry in entries {
		remove_tree(os.join_path(path, entry))
	}
	os.rmdir(path) or {}
}

// Whether a process with this number exists.
fn process_exists(pid int) bool {
	if pid <= 0 {
		return false
	}
	return C.kill(pid, 0) == 0 || C.errno == C.EPERM
}

// The work directory of a run that was given none: one per architecture,
// used again by the next run, so a machine with little disk never collects
// the images of runs that were killed. Two runs at once would boot each
// other's images; the second is refused while the first is alive.
fn claim_work_directory(arch string) !string {
	parent := os.join_path(os.temp_dir(), 'vinix-hwtest')
	os.mkdir_all(parent)!
	work := os.join_path(parent, arch)
	lock_path := work + '.pid'
	if text := os.read_file(lock_path) {
		owner := text.trim_space().int()
		if owner != os.getpid() && process_exists(owner) {
			return error('another run (process ${owner}) is using ${work}; wait for it or pass --state-dir')
		}
	}
	os.write_file(lock_path, '${os.getpid()}\n')!
	remove_tree(work)
	os.mkdir_all(work)!
	return work
}

fn release_work_directory(work string) {
	os.rm(work + '.pid') or {}
}

fn prepare_state_directory(path string) !string {
	if os.exists(path) {
		if !os.is_dir(path) {
			return error('--state-dir is not a directory: ${path}')
		}
		entries := os.ls(path)!
		if entries.len > 0 {
			return error('--state-dir must be an empty directory, and ${path} is not')
		}
	} else {
		os.mkdir_all(path)!
	}
	return os.real_path(path)
}

// The whole program. Returns the exit status: 0 when every selected scenario
// passed, 1 when one failed, 2 for a mistake in the invocation or the setup
// and 130 when the run was interrupted.
pub fn run(arguments []string, controller_source string) int {
	return run_suite(Suite{
		scenarios: scenarios
	}, arguments, controller_source)
}

// The same for any suite.
pub fn run_suite(suite Suite, arguments []string, controller_source string) int {
	options := parse_options(arguments) or {
		eprintln('run: ${err.msg()}')
		eprintln(usage)
		return 2
	}
	if options.help {
		println(usage)
		return 0
	}
	validate_scenarios(suite.scenarios) or {
		eprintln('run: scenario table: ${err.msg()}')
		return 2
	}
	if options.list {
		println(list_text(suite.scenarios, options.arch))
		return 0
	}
	selection := select_scenarios(suite.scenarios, options.arch, options.scenarios) or {
		eprintln('run: ${err.msg()}')
		return 2
	}
	kernel := os.real_path(options.kernel)
	if !os.is_file(kernel) {
		eprintln('run: --kernel is not a file: ${options.kernel}')
		return 2
	}
	root := find_root(controller_source) or {
		eprintln('run: ${err.msg()}')
		return 2
	}
	host := find_host(root, options.arch, options.qemu) or {
		eprintln('run: ${err.msg()}')
		return 2
	}
	keep := options.state_dir != ''
	work := if keep {
		prepare_state_directory(options.state_dir) or {
			eprintln('run: ${err.msg()}')
			return 2
		}
	} else {
		claim_work_directory(options.arch) or {
			eprintln('run: ${err.msg()}')
			return 2
		}
	}
	watch_interrupts()
	status := run_selection(host, suite, selection, kernel, work, options.timeout, keep,
		options.failures_only)
	if !keep {
		release_work_directory(work)
	}
	return status
}

fn run_selection(host Host, suite Suite, selection Selection, kernel string, work string, timeout int, keep bool, failures_only bool) int {
	guest_directory := os.join_path(work, 'guest')
	guest := build_program(host, os.join_path(host.root, suite.guest), guest_directory,
		'init', suite.module_paths) or {
		if err is Interrupted {
			eprintln('run: interrupted')
			return 130
		}
		eprintln('run: cannot build the guest program:\n${err.msg()}')
		return 2
	}
	extras := build_extras(host, suite, guest_directory) or {
		if err is Interrupted {
			eprintln('run: interrupted')
			return 130
		}
		eprintln('run: cannot build the root file system:\n${err.msg()}')
		return 2
	}
	mut passed := 0
	mut failed := 0
	mut was_interrupted := false
	for scenario in selection.run {
		outcome := run_scenario(host, scenario, Run{
			kernel:  kernel
			guest:   guest
			extras:  extras
			state:   os.join_path(work, scenario.name)
			// A scenario that says it needs longer than the run allows gets it.
			timeout:       if scenario.timeout > timeout { scenario.timeout } else { timeout }
			keep:          keep
			failures_only: failures_only
		})
		if outcome.interrupted {
			was_interrupted = true
			break
		}
		println(report(host.arch, outcome))
		if outcome.passed {
			passed++
		} else {
			failed++
		}
	}
	if !keep {
		remove_tree(guest_directory)
	}
	if was_interrupted {
		eprintln('run: interrupted')
		return 130
	}
	for scenario in selection.skipped {
		println('SKIP ${host.arch} ${scenario.name} (${scenario.left_out()})')
	}
	println('${suite.name} ${host.arch}: ${passed} passed, ${failed} failed, ${selection.skipped.len} skipped')
	return if failed == 0 { 0 } else { 1 }
}
