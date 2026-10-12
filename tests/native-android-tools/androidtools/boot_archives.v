// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import os
import tarstream

pub struct JarInfo {
pub:
	classes []string
	callsites u64
}

pub fn jar_info(path string) !JarInfo {
	archive := ah.open_archive(path)!
	mut classes := map[string]bool{}
	mut callsites := u64(0)
	for name in archive.names() {
		if !name.ends_with('.dex') { continue }
		info := ah.dex_info(archive.read(name)!)!
		for class in info.classes {
			if class in classes { return error('duplicate classes across bootclasspath DEX files: ' + path) }
			classes[class] = true
		}
		callsites += info.callsites
	}
	if classes.len == 0 { return error('bootclasspath JAR has no DEX classes: ' + path) }
	mut names := classes.keys()
	names.sort()
	return JarInfo{names, callsites}
}

pub fn extract_member(archive string, name string, output string) ! {
	mut reader := tarstream.open_concatenated(archive)!
	defer { reader.close() }
	for {
		entry := reader.next() or { if err is tarstream.End { break }; return err }
		if entry.name != name { continue }
		if !entry.regular() { return error('bootclasspath input is not a regular file: ' + name) }
		mut file := os.create(output)!
		defer { file.close() }
		mut buffer := []u8{len: 1024 * 1024}
		for {
			count := reader.read(mut buffer)!
			if count == 0 { break }
			mut offset := 0
			for offset < count {
				written := file.write(buffer[offset..count])!
				if written == 0 { return error('bootclasspath extraction write stopped') }
				offset += written
			}
		}
		return
	}
	return error('bootclasspath input is missing ' + name)
}

pub fn class_subset(raw string, requested []string, output string) ! {
	archive := ah.open_archive(raw)!
	available := archive.names()
	mut names := requested.clone()
	names.sort()
	// Match the original early creation of the target before missing-class
// admission. It remains a well-formed empty ZIP if admission fails.
	mut writer := ah.archive_writer(output)!
	defer { writer.close() or {} }
	for name in names { if name !in available { return error('pinned bootclasspath class input is missing ' + name) } }
	for name in names { writer.add(ah.ArchiveItem{name: name, data: archive.read(name)!})! }
	writer.close()!
}

pub fn package_boot_jar(original string, directory string, output string) ! {
	archive := ah.open_archive(original)!
	mut payload := map[string][]u8{}
	for name in archive.names() { if !name.ends_with('.dex') { payload[name] = archive.read(name)! } }
	mut names := []string{}
	for name in os.ls(directory)! { if name.ends_with('.dex') && os.is_file(directory + '/' + name) { names << name } }
	names.sort()
	for name in names { payload[name] = os.read_bytes(directory + '/' + name)! }
	if 'classes.dex' !in payload { return error('D8 did not produce classes.dex') }
	mut ordered := payload.keys()
	ordered.sort()
	mut items := []ah.ArchiveItem{}
	for name in ordered { items << ah.ArchiveItem{name: name, data: payload[name]!} }
	ah.write_archive(output, items)!
}
