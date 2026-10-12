// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

struct JitMountResult {
	runtime string
	executable string
	mountinfo string
}

fn jit_mount_row(mountinfo string, program string) !string {
	mut row := ''
	mut longest := 0
	for line in mountinfo.split_into_lines() {
		fields := line.fields()
		if fields.len < 10 || fields[4].len <= longest { continue }
		mountpoint := fields[4]
		if program != mountpoint && !program.starts_with(mountpoint.trim_right('/') + '/') { continue }
		longest = mountpoint.len
		row = line
	}
	if longest <= 1 { return error('JIT runtime needs a scoped executable mount') }
	flags := row.fields()[5].split(',')
	if !['ro', 'nosuid', 'nodev', 'wxallowed'].all(it in flags) || 'noexec' in flags {
		return error('JIT runtime mount must be ro,nosuid,nodev,wxallowed and executable')
	}
	return row
}

fn (mut suite Suite) require_jit_mount(name string, program string) ! {
	row := jit_mount_row(os.read_file('/proc/self/mountinfo')!, os.real_path(program))!
	suite.jit_mounts << JitMountResult{name, program, row}
}

fn parse_jit_runtimes(value string, cases []string, path string) ![]string {
	if value == '' { return []string{} }
	if path !in ['native-aarch64', 'native-x86_64'] {
		return error('JIT mount qualification requires a native runtime')
	}
	mut result := []string{}
	for name in value.split(',') {
		if name !in ['firefox', 'java'] || name !in cases || name in result {
			return error('JIT runtimes must name distinct selected Firefox or Java workloads')
		}
		result << name
	}
	return result
}
