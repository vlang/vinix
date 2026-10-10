// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import os

fn scratch_usage(family string) string {
	return 'Usage: check-generated BLOB.c' + if family == 'churn' { ' [--operations]' } else { '' }
}

fn scratch_entry(generated Generated, name string, family string) !string {
	return if family == 'procfs-scratch' {
		procfs_scratch_check(generated, name)!
	} else {
		ipv6_check(generated, name)!
	}
}

// Keep sequential output: a late failing policy leaves earlier PASS lines on
// stdout. The optional operations checks run only after the formatter check.
pub fn run_scratch(args []string, family string) int {
	mut paths := []string{}
	mut positional := false
	mut operations := false
	for argument in args {
		if !positional {
			if argument == '--' {
				positional = true
				continue
			}
			if argument in ['-h', '--help'] {
				println(scratch_usage(family))
				return 0
			}
			if family == 'churn' && '--operations'.starts_with(argument) && argument.starts_with('--') {
				operations = true
				continue
			}
			if argument.starts_with('-') && argument != '-' {
				eprintln(scratch_usage(family))
				return 2
			}
		}
		paths << argument
	}
	if paths.len != 1 {
		eprintln(scratch_usage(family))
		return 2
	}
	generated := parse(os.read_file(paths[0]) or {
		eprintln(err)
		return 1
	}) or {
		eprintln(err)
		return 1
	}
	if family == 'timer' {
		message := timer_check(generated) or {
			eprintln(err)
			return 1
		}
		println(message)
	} else if family == 'churn' {
		message := churn_check(generated) or {
			eprintln(err)
			return 1
		}
		println(message)
		if operations {
			selected := select_check(generated) or {
				eprintln(err)
				return 1
			}
			println(selected)
			cloned := clone_check(generated) or {
				eprintln(err)
				return 1
			}
			println(cloned)
		}
	} else if family == 'socket' {
		for index, name in socket_names {
			message := socket_check(generated, name, socket_slots[index]) or {
				eprintln(err)
				return 1
			}
			println(message)
		}
		for name in ['write_with_fds', 'send_datagram'] {
			message := unix_socket_check(generated, name) or {
				eprintln(err)
				return 1
			}
			println(message)
		}
	} else {
		for name in if family == 'procfs-scratch' {
			procfs_scratch_functions
		} else {
			ipv6_functions
		} {
			message := scratch_entry(generated, name, family) or {
				eprintln(err)
				return 1
			}
			println(message)
		}
	}
	return 0
}
