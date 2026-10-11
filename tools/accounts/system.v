// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-system: the privileged halves of what a desktop does for the person
// at it. Each is one fixed operation with at most one checked argument. The
// authentication service runs this as root when an action allows it
// (tools/accounts/actions); the desktop itself does not need to be root to
// turn the machine off or put it to sleep.
//
//	vinix-system power off|restart|suspend
//	vinix-system hostname NAME
module main

import os

#include <unistd.h>
#include <sys/reboot.h>

fn C.sync()
fn C.reboot(command int) int
fn C.geteuid() u32
fn C.sethostname(name &char, length usize) int

fn fail(message string) {
	eprintln('vinix-system: ${message}')
	exit(1)
}

fn valid_hostname(name string) bool {
	if name.len == 0 || name.len > 63 || name[0] == `-` || name[name.len - 1] == `-` {
		return false
	}
	for i in 0 .. name.len {
		ch := name[i]
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
			|| ch == `-`) {
			return false
		}
	}
	return true
}

fn main() {
	args := os.args[1..]
	if C.geteuid() != 0 {
		fail('only root may do this; ask through vinix-auth')
	}
	if args.len == 2 && args[0] == 'power' {
		match args[1] {
			'off' {
				C.sync()
				// RB_POWER_OFF.
				C.reboot(0x4321fedc)
				fail('the kernel refused to power off')
			}
			'restart' {
				C.sync()
				// RB_AUTOBOOT.
				C.reboot(0x01234567)
				fail('the kernel refused to restart')
			}
			'suspend' {
				offered := os.read_file('/sys/power/state') or {
					fail('this machine cannot sleep')
					return
				}
				// The deepest sleep the kernel offers that keeps memory.
				states := offered.trim_space().split(' ')
				state := if 'mem' in states {
					'mem'
				} else if 'freeze' in states {
					'freeze'
				} else {
					fail('this machine cannot sleep')
					return
				}
				C.sync()
				os.write_file('/sys/power/state', state) or { fail('the kernel refused to sleep') }
				return
			}
			else {}
		}
	}
	if args.len == 2 && args[0] == 'hostname' {
		if !valid_hostname(args[1]) {
			fail('invalid host name')
		}
		if C.sethostname(&char(args[1].str), usize(args[1].len)) != 0 {
			fail('the kernel refused the host name')
		}
		os.write_file('/etc/hostname.new', args[1] + '\n') or { fail('cannot write /etc/hostname') }
		os.rename('/etc/hostname.new', '/etc/hostname') or { fail('cannot write /etc/hostname') }
		C.sync()
		return
	}
	eprintln('usage: vinix-system power off|restart|suspend | hostname NAME')
	exit(2)
}
