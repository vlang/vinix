// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The collector as a program, against snapshots in a file: what it writes,
// that a second run repeats nothing, that it sets logs aside and deletes by
// the settings, and what it refuses to write into.
module main

import os

const boot = '00112233445566778899aabbccddeeff'

fn snapshot_text(total int, retained int) string {
	mut lines := ['version=1 capacity=256 total=${total} retained=${retained} dropped=0 boot=${boot}',
		'# sequence ns kind denied pid tid uid euid loginuid session arg label']
	for i in 0 .. retained {
		sequence := total - retained + 1 + i
		lines << '${sequence} ${sequence * 1000} 7 1 42 42 1001 1001 1001 3 80 bind'
	}
	lines << ''
	return lines.join('\n')
}

fn run(dir string, extra string) int {
	return os.system('${os.quoted_path(os.join_path(dir, 'collector'))} --once --source ${os.quoted_path(os.join_path(dir,
		'source'))} --directory ${os.quoted_path(os.join_path(dir, 'log'))} --settings ${os.quoted_path(os.join_path(dir,
		'audit.conf'))} ${extra} 2>${os.quoted_path(os.join_path(dir, 'stderr'))}')
}

fn test_collector() ! {
	dir := os.join_path(os.temp_dir(), 'vinix-events-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	built := os.execute('${os.quoted_path(@VEXE)} -cc cc -gc none -o ${os.quoted_path(os.join_path(dir,
		'collector'))} ${os.quoted_path(os.join_path(os.dir(os.dir(@FILE)), 'events.v'))}')
	assert built.exit_code == 0, built.output
	log := os.join_path(dir, 'log', 'events.log')

	os.write_file(os.join_path(dir, 'source'), snapshot_text(3, 3))!
	assert run(dir, '') == 0
	first := os.read_file(log)!
	assert first.split_into_lines().len == 4
	assert first.contains('event boot=${boot} seq=3 ') && first.contains(' kind=network result=denied pid=42 ')
		&& first.contains(' login=1001 session=3 arg=80 label=bind')
	assert os.stat(log)!.mode & 0o777 == 0o600
	assert os.stat(os.join_path(dir, 'log'))!.mode & 0o777 == 0o700
	// Again, nothing new: nothing written. Then two more.
	assert run(dir, '') == 0
	assert os.read_file(log)! == first
	os.write_file(os.join_path(dir, 'source'), snapshot_text(5, 5))!
	assert run(dir, '') == 0
	assert os.read_file(log)!.split_into_lines().len == 6

	// Setting aside: a small size, two kept.
	os.write_file(os.join_path(dir, 'audit.conf'), 'max_bytes = 4096\nkeep_files = 2\nmax_age_days = 0\n')!
	os.chmod(os.join_path(dir, 'audit.conf'), 0o644)!
	mut total := 5
	for _ in 0 .. 6 {
		total += 40
		os.write_file(os.join_path(dir, 'source'), snapshot_text(total, 40))!
		assert run(dir, '') == 0
	}
	names := os.ls(os.join_path(dir, 'log'))!
	assert 'events.log' in names && 'events.log.1' in names && 'events.log.2' in names
	assert names.len == 3, names.str()
	// Every record that is still kept is there once, in order across files.
	mut kept := []int{}
	for name in ['events.log.2', 'events.log.1', 'events.log'] {
		for line in os.read_file(os.join_path(dir, 'log', name))!.split_into_lines() {
			if line.starts_with('event ') {
				kept << line.all_after(' seq=').all_before(' ').int()
			}
		}
	}
	for i in 1 .. kept.len {
		assert kept[i] == kept[i - 1] + 1, 'records ${kept[i - 1]} and ${kept[i]} are adjacent in the logs'
	}
	assert kept[kept.len - 1] == total

	// A gap is written as a gap.
	total += 400
	os.write_file(os.join_path(dir, 'source'), snapshot_text(total, 256))!
	assert run(dir, '') == 0
	assert os.read_file(log)!.contains('loss boot=${boot} first=${total - 399} last=${total - 256} count=144 ')

	// What it will not do.
	os.write_file(os.join_path(dir, 'source'), 'not a snapshot\n')!
	assert run(dir, '') != 0
	os.write_file(os.join_path(dir, 'source'), snapshot_text(total + 1, 1))!
	os.chmod(os.join_path(dir, 'log'), 0o777)!
	assert run(dir, '') != 0
	assert os.read_file(os.join_path(dir, 'stderr'))!.contains('not root\'s alone')
	os.chmod(os.join_path(dir, 'log'), 0o700)!
	os.rename(log, log + '.real')!
	os.symlink(log + '.real', log)!
	assert run(dir, '') != 0
	os.rm(log)!
	os.rename(log + '.real', log)!
	os.write_file(os.join_path(dir, 'audit.conf'), 'keep_files = 0\n')!
	assert run(dir, '') != 0
	os.chmod(os.join_path(dir, 'audit.conf'), 0o666)!
	assert run(dir, '') != 0
}

// Half a line left by a collector that was killed mid-write does not eat
// the record that follows it.
fn test_half_a_line() ! {
	dir := os.join_path(os.temp_dir(), 'vinix-events-half-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'log'))!
	os.chmod(os.join_path(dir, 'log'), 0o700)!
	defer { os.rmdir_all(dir) or {} }
	built := os.execute('${os.quoted_path(@VEXE)} -cc cc -gc none -o ${os.quoted_path(os.join_path(dir,
		'collector'))} ${os.quoted_path(os.join_path(os.dir(os.dir(@FILE)), 'events.v'))}')
	assert built.exit_code == 0, built.output
	log := os.join_path(dir, 'log', 'events.log')
	os.write_file(log, 'event boot=${boot} seq=1 ns=1000 collected=1 kind=network result=denied pid=42 tid=42 uid=1001 euid=1001 login=1001 session=3 arg=80 label=bind\nevent boot=${boot} seq=2 ns=20')!
	os.chmod(log, 0o600)!
	os.write_file(os.join_path(dir, 'source'), snapshot_text(3, 3))!
	assert run(dir, '') == 0
	lines := os.read_file(log)!.split_into_lines()
	// The whole record 1, the half of 2, then 2 and 3 whole.
	assert lines.len == 4
	assert lines[2].starts_with('event boot=${boot} seq=2 ns=2000 ') && lines[3].contains(' seq=3 ')
}
