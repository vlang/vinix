// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A suite: a scenario table, the guest program whose functions are the
// scenarios' other halves, and what else the guest's root file system
// holds. The hardware tests are the suite this module was written for; the
// account and security tests (tests/accounts) are another, with programs of
// their own beside the guest.
module hwhost

import os

// A V program built for the guest and put in its root file system.
pub struct Program {
pub:
	source string // relative to the checkout
	path   string // in the root file system, without a leading slash
	flags  []string // additional V options for this fixture, such as allocation tracking
}

// A file written into the root file system as it is given here.
pub struct RootFile {
pub:
	path string
	text string
	mode int = 0o644
}

// A native V utility built by its production tooling, rather than by the
// standard-library guest compiler. Check the ELF target before copying it.
pub struct RootBinary {
pub:
	source string
	path   string
}

pub struct Suite {
pub:
	name      string = 'hardware-platform'
	scenarios []Scenario
	guest     string = 'tests/hardware-platform/guest'
	// Directories, relative to the checkout, where the guest and the programs
	// find modules that are not beside them.
	module_paths []string
	programs     []Program
	files        []RootFile
	binaries     []RootBinary
	// Directories the root file system has besides the ones every guest
	// gets, each `path` or `path:mode` with the mode in octal.
	directories []string
}

// Build and lay out everything a suite adds to the root file system, under
// `directory`. Returns '' for a suite that adds nothing.
pub fn build_extras(host Host, suite Suite, directory string) !string {
	if suite.programs.len == 0 && suite.files.len == 0 && suite.binaries.len == 0 && suite.directories.len == 0 {
		return ''
	}
	root := os.join_path(directory, 'root')
	os.mkdir_all(root)!
	for entry in suite.directories {
		parts := entry.split(':')
		path := os.join_path(root, parts[0])
		os.mkdir_all(path)!
		if parts.len == 2 {
			os.chmod(path, int(parts[1].parse_int(8, 32)!))!
		}
	}
	for index, program in suite.programs {
		built := build_program_with_flags(host, os.join_path(host.root, program.source), os.join_path(directory,
			'program-${index}'), os.file_name(program.path), suite.module_paths, program.flags)!
		target := os.join_path(root, program.path)
		os.mkdir_all(os.dir(target))!
		os.cp(built, target)!
		os.chmod(target, 0o755)!
	}
	for file in suite.files {
		target := os.join_path(root, file.path)
		os.mkdir_all(os.dir(target))!
		os.write_file(target, file.text)!
		os.chmod(target, file.mode)!
	}
	for binary in suite.binaries {
		data := os.read_bytes(binary.source)!
		if host.arch !in ['aarch64', 'x86_64'] {
			return error('unsupported native fixture target: ${host.arch}')
		}
		machine := if host.arch == 'aarch64' { 183 } else { 62 }
		if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(data[18]) + (int(data[19]) << 8) != machine {
			return error('wrong target for native fixture binary: ${binary.source}')
		}
		target := os.join_path(root, binary.path)
		os.mkdir_all(os.dir(target))!
		os.write_file_array(target, data)!
		os.chmod(target, 0o755)!
	}
	return root
}
