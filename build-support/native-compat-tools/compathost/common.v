// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import hosttest
import os
import policyhost

const original = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'

fn root() string { return hosttest.root() }
fn read(path string) !string { return hosttest.module_read_text(path)! }
fn write(path string, value string) ! { hosttest.module_write_text(path, value)! }
fn resolve(path string) !string { return hosttest.module_resolve(path)! }
fn run(argv []string) ! { policyhost.inherited(argv)! }
fn output(argv []string) !string { return policyhost.capture(argv)! }
fn captured(argv []string) !fixturehost.CapturedCommand {
	result := fixturehost.capture_both_preferred(argv, policyhost.environment(), policyhost.caller_arch())!
	if result.status != 0 {
		eprint(result.stderr)
		return error('Command exited ' + result.status.str() + ': ' + argv[0])
	}
	return result
}

fn generate(source string, destination string, arch string, defines []string, header string) ! {
	mut argv := [root() + '/build-support/compile-v-module', resolve(source)!, resolve(destination)!, '--arch', arch]
	for define in defines { argv << ['-d', define] }
	if header != '' { argv << ['--header', resolve(header)!] }
	run(argv)!
}

fn compiler_prefix(name string, fallback string) ![]string {
	value := os.getenv_opt(name) or { fallback }
	words := hosttest.shell_split(value)!
	if words.len == 0 { return error('Empty compiler: ' + name) }
	return words
}

fn retire(work string) { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
fn needed(parsed hosttest.Arguments, names []string) ! {
	for name in names {
		if name !in parsed.options { return error_with_code('missing required ' + name, 2) }
	}
}

pub fn command(args []string, family string) int {
	result := command_checked(args, family) or { eprintln(err.msg()); return if err.code() in [2, 130] { err.code() } else { 1 } }
	return result
}

fn command_checked(args []string, family string) !int {
	match family {
		'robust-compile' { return robust_compile(args)! }
		'robust-test' { return robust_test(args)! }
		'robust-guest' { return robust_guest(args)! }
		'office-compile' { return office_compile(args)! }
		'office-test' { return office_test(args)! }
		'office-guest' { return office_guest(args)! }
		'net-random' { return random_command(args)! }
		'n64-bridge' { return n64_bridge(args)! }
		'security-compile' { return security_compile(args)! }
		'x11-compile' { return x11_compile(args)! }
		'x11-build' { return x11_build(args)! }
		'security-stage' { return stage_command(args, true)! }
		'volume-stage' { return stage_command(args, false)! }
		'volume-host' { return volume_host(args)! }
		'volume-guest' { return volume_guest(args)! }
		'xinput-test' { return xinput_test(args)! }
		'xinput-guest' { return x11_guest(args, false)! }
		'wine-guest' { return x11_guest(args, true)! }
		'mac-host' { return security_host(args, 'mac')! }
		'sandbox-host' { return security_host(args, 'sandbox')! }
		'audit-host' { return security_host(args, 'audit')! }
		'process-smp', 'scheduler-qos', 'tlb', 'memory-retention' { return process_command(args, family)! }
		'listen-backlog' { return backlog_command(args)! }
		'resource-open', 'proc-thread-lock', 'proc-map-lookup', 'kernel-retention' { return inspection_command(args, family)! }
		'aarch64-sigreturn' { return sigreturn_command(args)! }
		'kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg' { return regression_command(args, family)! }
		'stack-protector' { return protector_command(args)! }
		'userland-demo' { return demo_command(args)! }
		'elf-text' { return elf_guest_command(args)! }
		'elf-text-host' { return elf_host_command(args)! }
		'uname' { return uname_command(args)! }
		'kernel-stack-guards', 'cpu-mitigations' { return optin_guest_command(args, family)! }
		'smt-policy' { return smt_guest_command(args)! }
		'acpi-sync' { return acpi_command(args)! }
		'resource-groups' { return groups_command(args)! }
		'speculation-policy' { return speculation_command(args)! }
		'resource-accounting', 'pagecache', 'ext2-sparse' { return filesystem_command(args, family)! }
		'hypervisor-host', 'mounted-disk-host', 'securelevel-host', 'securelevel-dispatch', 'securelevel-attributes' { return host_suite_command(args, family)! }
		else { return error_with_code('Unknown compatibility command', 2) }
	}
}
