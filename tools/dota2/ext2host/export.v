// SPDX-License-Identifier: GPL-2.0-or-later
module ext2host

import json2
import os
import sync
import time

pub struct Export {
pub:
	size     i64
	files    []SourceFile
	regions  [][]i64
	metadata int
mut:
	open_files map[int]int
	order      []int
	closed     bool
	mutex      &sync.Mutex = sync.new_mutex()
	observed   bool
	started    i64
	requests   i64
	read_bytes i64
	errors     i64
	failures   []ReadFailure
}

pub struct ReadFailure {
pub:
	elapsed_seconds f64
	offset          i64
	length          int
	error_number    int @[json: 'errno']
	message         string
}

pub struct ReadReport {
pub:
	requests    i64
	bytes       i64
	error_count i64
	failures    []ReadFailure
}

pub fn (mut e Export) observe_reads() {
	e.mutex.lock()
	defer { e.mutex.unlock() }
	e.observed = true
	e.started = time.ticks()
}

pub fn (mut e Export) read_report() ReadReport {
	e.mutex.lock()
	defer { e.mutex.unlock() }
	return ReadReport{e.requests, e.read_bytes, e.errors, e.failures.clone()}
}

pub fn open_export(state string) !&Export {
	contents := os.read_file(state + '/manifest.json')!
	fields := json2.decode[json2.Any](contents)!.as_map()
	for name in ['version', 'size', 'files', 'regions'] {
		if name !in fields { return error('Incomplete export manifest') }
	}
	manifest := json2.decode[Manifest](contents)!
	if manifest.version != 1 { return error('Unsupported export manifest') }
	// Validate untrusted persisted indexing before any request can slice it.
	if manifest.size < 0 { return error('Invalid export capacity') }
	mut end := i64(0)
	for region in manifest.regions {
		if region.len != 4 || region[0] < end || region[1] <= 0 || region[0] > manifest.size
			|| region[1] > manifest.size - region[0] || region[2] < 0 || region[2] >= manifest.files.len
			|| region[3] < 0 || region[3] > 0x7fffffffffffffff - region[1] {
			return error('Invalid export region')
		}
		end = region[0] + region[1]
	}
	for file in manifest.files {
		if file.path.contains('\x00') || file.identity.len != 5 || file.identity[2] < 0 {
			return error('Invalid source identity')
		}
	}
	fd := C.open((state + '/metadata.ext2').str, C.O_RDONLY | C.O_CLOEXEC, 0)
	if fd < 0 { return io_error('Cannot open export metadata') }
	return &Export{ size: manifest.size, files: manifest.files, regions: manifest.regions, metadata: fd }
}

pub fn (mut e Export) close() {
	e.mutex.lock()
	defer { e.mutex.unlock() }
	if e.closed { return }
	e.closed = true
	for _, fd in e.open_files { C.close(fd) }
	e.open_files.clear()
	e.order.clear()
	C.close(e.metadata)
}

fn (mut e Export) source_locked(index int, offset i64, count int) ![]u8 {
	entry := e.files[index]
	mut fd := e.open_files[index] or { -1 }
	if fd < 0 {
		fd = C.open(entry.path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if fd < 0 { return io_error('Cannot open export source: ' + entry.path) }
		e.open_files[index] = fd
	} else {
		e.order = e.order.filter(it != index)
	}
	e.order << index
	for e.order.len > 64 {
		oldest := e.order[0]
		C.close(e.open_files[oldest])
		e.open_files.delete(oldest)
		e.order.delete(0)
	}
	if !same_source(inspect_fd(fd)!, entry.identity) {
		return error_with_code('Source changed; rebuild the export: ' + entry.path, int(C.EIO))
	}
	wanted := if offset >= entry.identity[2] {
		0
	} else if i64(count) < entry.identity[2] - offset {
		count
	} else {
		int(entry.identity[2] - offset)
	}
	data := read_at(fd, offset, wanted)!
	if data.len != wanted || !same_source(inspect_fd(fd)!, entry.identity) {
		return error_with_code('Source changed while reading: ' + entry.path, int(C.EIO))
	}
	mut result := data.clone()
	result << []u8{len: count - wanted}
	return result
}

pub fn (mut e Export) read(offset i64, count int) ![]u8 {
	e.mutex.lock()
	defer { e.mutex.unlock() }
	if e.observed { e.requests++ }
	data := e.read_locked(offset, count) or {
		if e.observed {
			e.errors++
			if e.failures.len < 32 {
				row := ReadFailure{f64(time.ticks() - e.started) / 1000, offset, count, err.code(), err.msg()}
				e.failures << row
				println('DOTA2-EXPORT-READ-ERROR: ' + json2.encode(row))
				flush_stdout()
			}
		}
		return err
	}
	if e.observed { e.read_bytes += data.len }
	return data
}

fn (mut e Export) read_locked(offset i64, count int) ![]u8 {
	if e.closed { return error_with_code('Export is closed', int(C.EIO)) }
	if offset < 0 || count < 0 || count > max_request || offset > e.size || i64(count) > e.size - offset {
		return error_with_code('Invalid disk read range', int(C.EINVAL))
	}
	mut output := []u8{cap: count}
	mut position := offset
	end := offset + count
	for position < end {
		mut low := 0
		mut high := e.regions.len
		for low < high {
			middle := (low + high) / 2
			if e.regions[middle][0] <= position { low = middle + 1 } else { high = middle }
		}
		index := low - 1
		if index >= 0 && position < e.regions[index][0] + e.regions[index][1] {
			region := e.regions[index]
			length := int(if end - position < region[0] + region[1] - position {
				end - position
			} else {
				region[0] + region[1] - position
			})
			output << e.source_locked(int(region[2]), region[3] + position - region[0], length)!
			position += length
		} else {
			boundary := if low < e.regions.len { e.regions[low][0] } else { e.size }
			length := int(if end - position < boundary - position {
				end - position
			} else {
				boundary - position
			})
			data := read_at(e.metadata, position, length)!
			if data.len != length { return error_with_code('Short metadata read', int(C.EIO)) }
			output << data
			position += length
		}
	}
	return output
}
