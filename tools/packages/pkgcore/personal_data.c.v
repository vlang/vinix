// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

fn personal_data_inventory(home string, uid u32, state State) !pkgprotocol.PersonalDataStatus {
	directory := personal_data_parent(home, uid)!
	if directory < 0 { return pkgprotocol.PersonalDataStatus{ format: 1 } }
	defer { C.close(directory) }
	parent := purge_directory_info(directory, uid, true)!
	duplicate := C.dup(directory)
	if duplicate < 0 { return error('cannot retain personal data directory') }
	stream := C.fdopendir(duplicate)
	if stream == unsafe { nil } { C.close(duplicate); return error('cannot enumerate personal data directory') }
	defer { C.closedir(stream) }
	mut rows := []pkgprotocol.PersonalData{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut retained := false
	defer {
		if !retained {
			mut discarded := pkgprotocol.PersonalDataStatus{ rows: rows }
			discarded.close()
		}
	}
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read personal data directory') }
			break
		}
		name := unsafe { &entry.d_name[0] }
		if unsafe { C.strcmp(name, c'.') == 0 || C.strcmp(name, c'..') == 0 } { continue }
		count++
		if count > 4096 { return error('personal data directory exceeds the entry limit (4096)') }
		id := unsafe { tos3(name) }
		if !identifier(id) { continue }
		mut info := C.stat{}
		if C.fstatat(directory, name, &info, C.AT_SYMLINK_NOFOLLOW) != 0 {
			if C.errno == C.ENOENT { continue }
			return error('cannot inspect personal data entry')
		}
		diagnostic := if u32(info.st_mode) & 0o170000 != 0o040000 {
			'Application data must be an ordinary directory; links and special files cannot be purged.'
		} else if info.st_uid != uid || u32(info.st_mode) & 0o022 != 0 {
			'Application data must be owned by this account and not writable by other accounts.'
		} else if info.st_dev != parent.st_dev {
			'Application data is on another filesystem and cannot be purged.'
		} else { '' }
		row := pkgprotocol.PersonalData{ id: id.clone(), installed: state.packages.any(it.package.id == id), diagnostic: diagnostic.clone() }
		// Transfer owned fields, avoiding a typed push's deep string clone.
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	rows.sort(a.id < b.id)
	retained = true
	return pkgprotocol.PersonalDataStatus{ format: 1, rows: rows }
}

pub fn (service Service) personal_data() !pkgprotocol.PersonalDataStatus {
	if service.root != '' || os.geteuid() == 0 || C.getegid() == 0 {
		return error('data-list requires an ordinary user session without an alternate installation root')
	}
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	state := read_state(directory, config.architecture)!
	defer { if state.generation > 0 { close_decoded_state(state) } }
	return personal_data_inventory(os.home_dir(), u32(os.geteuid()), state)
}
