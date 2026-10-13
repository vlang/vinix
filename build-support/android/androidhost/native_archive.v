// SPDX-License-Identifier: GPL-2.0-or-later
module androidhost

import os

// Native producers share the qualified ZIP parser and zlib encoder with
// the APK probes. Duplicate names retain ZipFile's last-name lookup rule.
pub struct Archive {
	archive ProbeZip
}

pub struct ArchiveItem {
pub:
	name string
	data []u8
	mode u32 = 0o644
}

// Native package fetchers validate the complete central-directory policy
// before opening any output file. Compression and CRC checks stay shared.
pub struct ArchiveEntry {
pub:
 name string
 size u64
 mode u32
}

pub fn (archive Archive) entries() []ArchiveEntry {
 return archive.archive.entries.map(ArchiveEntry{name:it.name,size:it.size,mode:elf_u32(it.central,38) >> 16})
}

pub struct ArchiveWriter {
mut:
	stream os.File
	output []u8
	central []u8
	published int
	count int
	closed bool
}

pub fn archive_writer(path string) !ArchiveWriter { return ArchiveWriter{stream: os.create(path)!} }

pub fn (mut writer ArchiveWriter) add(item ArchiveItem) ! {
	if writer.closed { return error('archive writer is closed') }
	entry := add_probe_entry(mut writer.output, ProbePayload{item.name, item.data, item.mode})!
	writer.central << entry
	write_probe_bytes(mut writer.stream, writer.output[writer.published..])!
	writer.published = writer.output.len
	writer.count++
}

pub fn (mut writer ArchiveWriter) close() ! {
	if writer.closed { return }
	writer.closed = true
	defer { writer.stream.close() }
	finish_probe_zip(mut writer.output, writer.central, writer.count, []u8{})!
	write_probe_bytes(mut writer.stream, writer.output[writer.published..])!
}

pub fn open_archive(path string) !Archive { return Archive{read_probe_zip(path)!} }

pub fn (archive Archive) names() []string { return archive.archive.entries.map(it.name) }

pub fn (archive Archive) read(name string) ![]u8 { return archive.archive.read_name(name)! }

// ZIP consumers that open an individual central-directory record must retain
// its identity even when later records have the same filename.
pub fn (archive Archive) read_index(index int) ![]u8 { return archive.archive.read_index(index)! }

pub fn write_archive(path string, items []ArchiveItem) ! {
	mut writer := archive_writer(path)!
	defer { writer.close() or {} }
	for item in items {
		writer.add(item) or {
			writer.close()!
			return err
		}
	}
	writer.close()!
}
