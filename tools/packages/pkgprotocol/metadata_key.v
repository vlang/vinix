// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Decode one independently owned JSON object key. All SDK metadata fields fit
// within 32 UTF-8 bytes; even completely escaped spellings have bounded input.
pub fn decode_metadata_key(text string) !string {
	if text.len > 194 { return error('package metadata JSON key exceeds its bound') }
	mut reader := &MetadataReader{text: text}
	defer { unsafe { free(reader) } }
	key := reader.quoted(32)!
	reader.spaces()
	if reader.position != text.len {
		unsafe { key.free() }
		return error('trailing data after package metadata JSON key')
	}
	return key
}
