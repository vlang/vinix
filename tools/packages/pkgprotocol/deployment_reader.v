// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

const deployment_document_keys = ['format', 'architecture', 'packages', 'locked']
const deployment_pin_keys = ['id', 'version', 'architecture', 'repository', 'public_key', 'minimum_sequence', 'metadata_sha256']

fn (mut r MetadataReader) deployment_pin() !DeploymentPin {
	r.expect(`{`)!
	mut pin := DeploymentPin{}
	mut accepted := false
	defer { if !accepted { close_deployment_pin(pin) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(deployment_pin_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { pin = DeploymentPin{ ...pin, id: r.quoted(128)! } }
			1 { pin = DeploymentPin{ ...pin, version: r.quoted(29)! } }
			2 { pin = DeploymentPin{ ...pin, architecture: r.quoted(16)! } }
			3 { pin = DeploymentPin{ ...pin, repository: r.quoted(128)! } }
			4 { pin = DeploymentPin{ ...pin, public_key: r.quoted(64)! } }
			5 { pin = DeploymentPin{ ...pin, minimum_sequence: r.unsigned(~u64(0))! } }
			6 { pin = DeploymentPin{ ...pin, metadata_sha256: r.quoted(64)! } }
			else {}
		}
	}
	if seen != 127 { return error('missing locked deployment package field') }
	accepted = true
	return pin
}

fn (mut r MetadataReader) deployment_pins() ![]DeploymentPin {
	r.expect(`[` )!
	mut pins := []DeploymentPin{cap: 16}
	unsafe { pins.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { mut discarded := DeploymentDocument{ locked: pins }; discarded.close() } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if pins.len == 4096 { return error('deployment exceeds its supported package limits') }
		pin := r.deployment_pin()!
		pointer := unsafe { &pin }
		unsafe { pins.push_many(pointer, 1) }
	}
	accepted = true
	return pins
}

// One nonrecursive parse, with owned strings, bounded noslices arrays and
// rejection cleanup, including errors halfway through a string or pin record.
// Keys may be reordered or Unicode escaped. All fields are explicit; format 1
// forbids locked, whereas format 2 requires it even for an empty deployment.
pub fn decode_deployment_document(text string) !DeploymentDocument {
	if text.len > 8 * 1024 * 1024 { return error('deployment exceeds metadata limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut document := DeploymentDocument{}
	mut accepted := false
	defer { if !accepted { document.close() } }
	mut seen := u16(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(deployment_document_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { document = DeploymentDocument{ ...document, format: int(reader.unsigned(2)!) } }
			1 { document = DeploymentDocument{ ...document, architecture: reader.quoted(16)! } }
			2 { document = DeploymentDocument{ ...document, packages: reader.strings(128, 4096)! } }
			3 { document = DeploymentDocument{ ...document, locked: reader.deployment_pins()! } }
			else {}
		}
	}
	reader.spaces()
	if document.format !in [1, 2]! { return error('unsupported deployment format') }
	if seen != (if document.format == 1 { u16(7) } else { u16(15) }) || reader.position != text.len {
		return error('incomplete, incompatible or trailing deployment document')
	}
	accepted = true
	return document
}
