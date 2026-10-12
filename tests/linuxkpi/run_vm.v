// SPDX-License-Identifier: GPL-2.0-or-later
// Invoke the maintained native workflow without an interpreter or shell builder.
module main

import agxhost
import encoding.hex
import hosttest
import json2
import os
import strconv

fn main() {
	run() or {
		eprintln(err.msg())
		exit(if err.code() > 0 { err.code() } else { 1 })
	}
}

fn run() ! {
	mut specifications := []hosttest.Option{}
	for name in ['--kernel', '--state-dir', '--firmware', '--qemu', '--cc', '--limine-dir', '--cpu',
		'--timeout'] {
		specifications << hosttest.Option{ name: name, value: true }
	}
	for name in ['--no-linuxkpi', '--mmap-lease-test', '--pci-topology-test'] {
		specifications << hosttest.Option{ name: name }
	}
	parsed := hosttest.parse_arguments(os.args[1..], specifications, 0,
		'Usage: run_vm --kernel ELF --state-dir FRESH [--cpu max] [--timeout 90] [--no-linuxkpi]',
		'Four CPU q35/TCG native LinuxKPI guest; every maintained serial assertion is required.') or { return error_with_code(err.msg(), 2) }
	for name in ['--kernel', '--state-dir'] {
		if name !in parsed.options { return error_with_code('required argument: ' + name, 2) }
	}
	timeout := parsed.options['--timeout'] or { '90' }
	strconv.parse_int(timeout, 10, 64) or { return error_with_code(err.msg(), 2) }
	mut environment := []string{}
	for key, value in os.environ() { environment << key + '=' + value }
	mut row := {
		'root':              json2.Any(hex.encode(hosttest.root().bytes()))
		'kernel':            json2.Any(hex.encode(parsed.options['--kernel'].bytes()))
		'state_dir':         json2.Any(hex.encode(parsed.options['--state-dir'].bytes()))
		'firmware':          json2.Any(json2.Null{})
		'limine_dir':        json2.Any(json2.Null{})
		'environment':       json2.Any(hex.encode(environment.join('\x00').bytes()))
		'timeout_text':      json2.Any(timeout)
		'qemu':              json2.Any(parsed.options['--qemu'] or { 'qemu-system-x86_64' })
		'cc':                json2.Any(parsed.options['--cc'] or { 'clang' })
		'cpu':               json2.Any(parsed.options['--cpu'] or { 'max' })
		'no_linuxkpi':       json2.Any('--no-linuxkpi' in parsed.options)
		'mmap_lease_test':   json2.Any('--mmap-lease-test' in parsed.options)
		'pci_topology_test': json2.Any('--pci-topology-test' in parsed.options)
	}
	for name in ['firmware', 'limine_dir'] {
		option := '--' + name.replace('_', '-')
		if option in parsed.options {
			row[name] = json2.Any(hex.encode(parsed.options[option].bytes()))
		}
	}
	result := agxhost.linux_guest_native(row)!
	if result != 0 { return error_with_code('native guest failed', result) }
}
