// mount.v: Main file of mount.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module main

import os

fn C.mount(source charptr, target charptr, filesystem charptr, flags u64, data voidptr) int

fn main() {
	// Get command line options, and set defaults.
	mut filesystem := ''
	mut source := ''
	mut destination := ''

	mut idx := 1
	for idx < os.args.len {
		match os.args[idx] {
			'--help' {
				println('Usage: ${os.args[0]} [options] <source> <destination>')
				println('')
				println('Mount a filesystem')
				println('')
				println('Options:')
				println('--help          display this help')
				println('--help          display this help')
				println('-t <filesystem> filesystem to mount')
				exit(0)
			}
			'--version' {
				println('mount from util-vinix')
				exit(0)
			}
			'-t' {
				idx++
				if idx < os.args.len {
					filesystem = os.args[idx]
				} else {
					println("No filesystem was specified for -t")
					exit(0)
				}
			}
			else {
				break
			}
		}
		idx++
	}

	// Check whether we have all the options we need.
	if filesystem == '' {
		println("No filesystem was specified")
		exit(0)
	}
	if idx < os.args.len {
		source = os.args[idx]
		idx++
	} else {
		println("No source was specified")
		exit(0)
	}
	if idx < os.args.len {
		destination = os.args[idx]
		idx++
	} else {
		println("No destination was specified")
		exit(0)
	}

	// Do the actual mounting.
	if C.mount(source.str, destination.str, filesystem.str, 0, 0) != 0 {
        println("Couldn't mount (${C.errno})")
		exit(0)
	}
}

