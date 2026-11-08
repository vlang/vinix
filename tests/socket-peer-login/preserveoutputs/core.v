// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only preservation of a retired kernel build's three output directories.
module preserveoutputs

import json2
import os

#include <errno.h>
#include <stdio.h>
#include <sys/stat.h>

const journal_name = 'preserve-outputs.jsonl'
const maximum_journal_bytes = 64 * 1024

pub enum Phase {
	admission
	ready
	rename
	complete
	refused
	failed
}

pub enum State {
	planned
	absent
	pending
	moved
	failed
}

pub struct Identity {
pub:
	dev u64
	inode u64
	mode u32
	uid u32
	gid u32
	nlink u64
	size u64
	mtime i64
	ctime i64
	flags u32
}

pub struct Item {
pub:
	name string
	source string
	destination string
pub mut:
	state State = .planned
	attempted bool
	number i32
	before Identity
	after Identity
}

pub struct Record {
pub:
	format string = 'kernel-output-rename-v1'
	root string
	step string
	arch string
	device u64
	scope string = 'Three fixed directory renames under trusted quiescent source and exclusive owned destination parents. Internal links remain literal. No copy, rollback, removal, hostile concurrent namespace or crash-durability claim.'
pub mut:
	phase Phase = .admission
	ordinal int = -1
	reason string
	number i32
	items []Item
}

pub struct Failure {
pub:
	reason string
	number i32
	journal string
}

pub fn (failure Failure) msg() string { return failure.reason + '; preserve journal: ' + failure.journal }
pub fn (failure Failure) code() int { return int(failure.number) }

struct Writer {
	file &C.FILE = unsafe { nil }
mut:
	rows int
	bytes int
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }

pub fn journal_path(step string) string { return step + '/' + journal_name }

// os.Stat omits Darwin's st_flags. Keep the native declaration from the pinned
// os module and read that field without changing flags or source metadata.
pub fn identity(path string) !Identity {
	$if !macos { return error('kernel output preservation is qualified for Darwin only') }
	mut native := C.stat{}
	if unsafe { C.lstat(&char(path.str), &native) } != 0 {
		number := i32(C.errno)
		return error_with_code('cannot lstat preserved object: ' + path, int(number))
	}
	return Identity{u64(native.st_dev), native.st_ino, u32(native.st_mode), native.st_uid,
		native.st_gid, u64(native.st_nlink), u64(native.st_size), native.st_mtime,
		native.st_ctime, native.st_flags}
}

fn directory(path string) !Identity {
	value := identity(path)!
	need(value.mode & 0o170000 == 0o040000 && os.real_path(path) == path
		&& value.uid == u32(os.getuid()) && value.mode & 0o022 == 0,
		'canonical owned non-writable-by-group directory required: ' + path)!
	return value
}

fn parent_unchanged(before Identity, after Identity) bool {
	// Each successful rename changes parent link counts and timestamps.
	return before.dev == after.dev && before.inode == after.inode
		&& before.mode == after.mode && before.uid == after.uid && before.gid == after.gid
		&& before.flags == after.flags
}

pub fn same_object(before Identity, after Identity) bool {
	// Renaming may change ctime. The inode and all named ownership/mode/link
	// properties must still identify the same directory, never a copied tree.
	return parent_unchanged(before, after) && before.nlink == after.nlink
}

fn (mut writer Writer) append(record Record) ! {
	body := json2.encode(record) + '\n'
	need(writer.rows < 12 && body.len <= 8192
		&& writer.bytes <= maximum_journal_bytes - body.len, 'preservation journal bound')!
	if C.fwrite(body.str, usize(1), usize(body.len), writer.file) != usize(body.len) {
		number := i32(C.errno)
		return error_with_code('cannot write preservation journal', int(number))
	}
	if C.fflush(writer.file) != 0 {
		number := i32(C.errno)
		return error_with_code('cannot flush preservation journal', int(number))
	}
	writer.rows++
	writer.bytes += body.len
}

fn reject(mut record Record, mut writer Writer, phase Phase, number i32, reason string) !Record {
	record.phase = phase
	record.number = number
	record.reason = reason
	writer.append(record)!
	return Failure{reason, number, journal_path(record.step)}
}

// The existing failure path may call preservation a second time. A journal is
// sticky: a second call must refuse before moving any previously pending item.
pub fn preserve(root string, step string, arch string) !Record {
	$if !macos { return error('kernel output preservation is qualified for Darwin only') }
	need(arch in ['x86_64', 'aarch64'] && root.len <= 512 && step.len <= 512
		&& root.starts_with('/') && step.starts_with('/')
		&& !root.contains('\x00') && !step.contains('\x00'), 'fixed preservation inputs required')!
	directory(root)!
	destination_parent := directory(step)!
	need(root != step && !step.starts_with(root + '/') && !root.starts_with(step + '/'),
		'preservation source and destination scopes overlap')!
	path := journal_path(step)
	need(!present(path), 'preservation journal already exists; previous state remains authoritative')!
	// libc's exclusive-create mode also refuses a late existing journal. No
	// existing journal is truncated or replaced by this helper.
	file := C.fopen(path.str, c'wx')
	if isnil(file) {
		number := i32(C.errno)
		return Failure{'cannot create fresh preservation journal', number, path}
	}
	mut closed := false
	defer { if !closed { C.fclose(file) } }
	mut writer := Writer{file: file}
	mut record := Record{root: root, step: step, arch: arch, device: destination_parent.dev,
		items: [Item{name: 'obj', source: root + '/kernel/obj', destination: step + '/obj'},
			Item{name: 'bin', source: root + '/kernel/bin', destination: step + '/bin'},
			Item{name: 'cc-runtime-' + arch, source: root + '/kernel/cc-runtime-' + arch,
				destination: step + '/cc-runtime-' + arch}]}
	writer.append(record)!
	source_parent := directory(root + '/kernel') or {
		return reject(mut record, mut writer, .refused, i32(err.code()), err.msg())
	}
	if source_parent.dev != destination_parent.dev {
		return reject(mut record, mut writer, .refused, i32(C.EXDEV), 'source and destination devices differ')
	}
	for i in 0 .. record.items.len {
		record.ordinal = i
		item := record.items[i]
		if present(item.destination) {
			return reject(mut record, mut writer, .refused, i32(C.EEXIST), 'preserved destination already exists: ' + item.name)
		}
		if !present(item.source) { record.items[i].state = .absent; continue }
		value := directory(item.source) or {
			return reject(mut record, mut writer, .refused, i32(err.code()), err.msg())
		}
		if value.dev != source_parent.dev {
			return reject(mut record, mut writer, .refused, i32(C.EXDEV), 'output device differs: ' + item.name)
		}
		record.items[i].before = value
		record.items[i].state = .pending
	}
	record.phase = .ready
	record.ordinal = -1
	writer.append(record)!
	for i in 0 .. record.items.len {
		if record.items[i].state == .absent { continue }
		record.ordinal = i
		item := record.items[i]
		current_source_parent := directory(root + '/kernel') or {
			return reject(mut record, mut writer, .failed, i32(err.code()), err.msg())
		}
		current_destination_parent := directory(step) or {
			return reject(mut record, mut writer, .failed, i32(err.code()), err.msg())
		}
		current := directory(item.source) or {
			return reject(mut record, mut writer, .failed, i32(err.code()), err.msg())
		}
		if !parent_unchanged(source_parent, current_source_parent)
			|| !parent_unchanged(destination_parent, current_destination_parent)
			|| !same_object(item.before, current) || present(item.destination) {
			return reject(mut record, mut writer, .failed, i32(C.EBUSY), 'preservation inputs changed before rename: ' + item.name)
		}
		record.phase = .rename
		record.items[i].attempted = true
		writer.append(record)!
		// This is the only output mutation. Never substitute os.mv: its fallback
		// copies and removes on every rename failure, including same-device errors.
		result := C.rename(item.source.str, item.destination.str)
		number := if result == 0 { i32(0) } else { i32(C.errno) }
		if result != 0 {
			record.items[i].state = .failed
			record.items[i].number = number
			return reject(mut record, mut writer, .failed, number, 'rename refused; all remaining outputs retained: ' + item.name)
		}
		after := directory(item.destination) or {
			record.items[i].state = .failed
			return reject(mut record, mut writer, .failed, i32(err.code()), 'renamed output inspection failed: ' + item.name)
		}
		record.items[i].after = after
		if present(item.source) || !same_object(item.before, after) {
			record.items[i].state = .failed
			return reject(mut record, mut writer, .failed, i32(C.EIO), 'renamed output identity differs: ' + item.name)
		}
		record.items[i].state = .moved
		writer.append(record)!
	}
	record.phase = .complete
	record.ordinal = -1
	writer.append(record)!
	result := C.fclose(file)
	number := if result == 0 { i32(0) } else { i32(C.errno) }
	closed = true
	if result != 0 {
		return Failure{'cannot close completed preservation journal', number, path}
	}
	return record
}

pub fn read_journal(step string) ![]Record {
	path := journal_path(step)
	info := os.lstat(path)!
	need(info.mode & 0o170000 == 0o100000 && info.nlink == 1
		&& info.size > 0 && info.size <= maximum_journal_bytes, 'bounded ordinary preservation journal required')!
	mut records := []Record{}
	for line in os.read_file(path)!.split_into_lines() {
		need(line != '' && records.len < 12, 'preservation journal row bound')!
		record := json2.decode[Record](line)!
		need(record.format == 'kernel-output-rename-v1' && record.step == step && record.items.len == 3,
			'preservation journal schema differs')!
		records << record
	}
	need(records.len > 0, 'preservation journal is empty')!
	return records
}
