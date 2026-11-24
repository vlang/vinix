// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub const media_import_result_prefix = 'VINIX-PACKAGE-MEDIA-RESULT '
pub const media_import_result_limit = 512

pub struct MediaImportResult {
pub:
	format int = 1
	receipt_sha256 string
	deployment_sha256 string
}

pub fn (mut result MediaImportResult) close() {
	unsafe { result.receipt_sha256.free(); result.deployment_sha256.free() }
	result = MediaImportResult{}
}

const media_import_keys = ['format', 'receipt_sha256', 'deployment_sha256']

pub fn decode_media_import_result(text string) !MediaImportResult {
	if text.len > media_import_result_limit { return error('media import result exceeds its size limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut result := &MediaImportResult{}
	defer { unsafe { free(result) } }
	mut accepted := false
	defer { if !accepted { result.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(media_import_keys, seen)!
		seen |= u16(1) << field
		unsafe {
			match field {
				0 { r.expect(`1`)! }
				1 { *result = MediaImportResult{ ...result, receipt_sha256: r.quoted(64)! } }
				2 { *result = MediaImportResult{ ...result, deployment_sha256: r.quoted(64)! } }
				else {}
			}
		}
	}
	r.spaces()
	if seen != 7 || r.position != text.len || !digest(result.receipt_sha256) || !digest(result.deployment_sha256) {
		return error('invalid media import result')
	}
	accepted = true
	return *result
}
