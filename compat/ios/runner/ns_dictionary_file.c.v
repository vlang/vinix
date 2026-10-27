// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

fn dictionary_from_file(cls u64, path_object u64) u64 {
	if path_object == 0 { return 0 }
	path := string_text(path_object)
	if !os.is_file(path) || os.file_size(path) > 16777216 { return 0 }
	bytes := os.read_bytes(path) or { return 0 }
	defer { unsafe { bytes.free() } }
	value := plist.parse(bytes) or { return 0 }
	defer { value.free() }
	if value.kind != .dictionary { return 0 }
	// Foundation's mutable factory makes every nested container mutable.
	// Its immutable factory uses mutable XML containers and mutable binary
	// arrays; binary dictionaries and empty XML dictionaries stay immutable.
	mode := if cls == ios_runtime.names['NSMutableDictionary'] { PlistObjectMode.mutable_containers }
		else if bytes.len >= 8 && bytes[0] == `b` && bytes[1] == `p` { PlistObjectMode.binary_file }
		else { PlistObjectMode.xml_file }
	return objc_autorelease(plist_owned_object_mode(value, mode))
}
