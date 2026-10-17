// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bootpolicy
import bundlehost as bh
import fixturehost
import hosttest
import os
import policyhost

pub fn cli(family string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked(family, args) or {
		eprintln(err.msg())
		return if policyhost.command_interrupted() || err.code() == 130 {
			130
		} else if err is bh.ArgumentError {
			2
		} else {
			1
		}
	}
	return 0
}

fn checked(family string, args []string) ! {
	match family {
		'boot-test' { boot_test(args)! }
		'root-test' { root_test(args)! }
		'root-host' { root_host(args)! }
		'boot-runtime' { boot_runtime(args)! }
		'root-runtime' { root_runtime(args)! }
		else { return error('Unknown verified test') }
	}
}

fn options(names []string) []hosttest.Option {
	return names.map(hosttest.Option{ name: it, value: true })
}

fn temporary(prefix string) !string { return bh.temporary(os.temp_dir(), prefix)! }

fn require_invalid(operation fn () !) ! {
	mut rejected := false
	operation() or {
		if err !is bootpolicy.InvalidBundle { return err }
		rejected = true
	}
	if !rejected { return error('Expected an invalid boot bundle to be rejected') }
}

fn require_failed(operation fn () !) ! {
	mut rejected := false
	operation() or {
		if err !is fixturehost.CommandError { return err }
		rejected = true
	}
	if !rejected { return error('Expected command failure') }
}

fn module_capture(argv []string, _log string, _timeout int, env map[string]string) !hosttest.Result {
	result := fixturehost.capture_owned_bounded(argv, env, policyhost.caller_arch(), '', -1, policyhost.command_interrupted, false)!
	return hosttest.Result{ code: result.status, stdout: result.stdout, stderr: result.stderr }
}

fn put16(mut data []u8, offset int, value u16) {
	for i in 0 .. 2 { data[offset + i] = u8(value >> (i * 8)) }
}

fn put32(mut data []u8, offset int, value u32) {
	for i in 0 .. 4 { data[offset + i] = u8(value >> (i * 8)) }
}

fn joined(parts ...[]string) []string {
	mut result := []string{}
	for part in parts { result << part }
	return result
}

fn bytes_joined(parts ...[]u8) []u8 {
	mut result := []u8{}
	for part in parts { result << part }
	return result
}

pub fn elf(arch string) ![]u8 {
	mut data := []u8{len: 64}
	for i, b in [u8(0x7f), `E`, `L`, `F`, 2, 1] { data[i] = b }
	put16(mut data, 18, bootpolicy.architecture(arch)!.elf_machine)
	return data
}

// Parser fixture only. A synthetic image is never signed or booted.
pub fn pe(arch string) ![]u8 {
	mut data := []u8{len: 2048}
	data[0], data[1] = `M`, `Z`
	put32(mut data, 0x3c, 128)
	data[128], data[129] = `P`, `E`
	put16(mut data, 132, bootpolicy.architecture(arch)!.pe_machine)
	put16(mut data, 134, 1)
	put16(mut data, 148, 240)
	put16(mut data, 152, 0x20b)
	put16(mut data, 220, 10)
	put32(mut data, 260, 16)
	put32(mut data, 408, 1024)
	put32(mut data, 412, 512)
	for i, b in bootpolicy.config_marker.bytes() { data[512 + i] = b }
	for i in 0 .. 128 { data[512 + bootpolicy.config_marker.len + i] = `0` }
	label := 'Limine 12.9.3 (' + if arch == 'x86_64' { 'x86-64' } else { arch } + ', UEFI)'
	for i, b in label.bytes() { data[800 + i] = b }
	return data
}
