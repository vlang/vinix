// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import encoding.utf8

// Successful durable publication of historical installed metadata. This receipt
// grants no repository trust and does not include payloads or personal data.
pub struct DeploymentSnapshotSaved {
pub:
	format int = 1
	generation u64
	architecture string
	destination string // exact caller argument, absolute or relative
	sha256 string // saved bytes, including the terminating LF
	roots u64
	packages u64
}

pub fn (saved &DeploymentSnapshotSaved) validate() ! {
	if !saved.fields_valid() || (saved.generation == 0 && saved.packages != 0) {
		return error('invalid saved deployment snapshot receipt')
	}
}

fn (saved &DeploymentSnapshotSaved) fields_valid() bool {
	return !(saved.format != 1 || saved.architecture !in ['aarch64', 'x86_64']! || !digest(saved.sha256)
		|| saved.destination == '' || !printable(saved.destination, 4096) || !utf8.validate_str(saved.destination)
		|| saved.roots > saved.packages || saved.packages > 4096
		|| ((saved.roots == 0) != (saved.packages == 0)))
}

pub fn (mut saved DeploymentSnapshotSaved) close() {
	unsafe { saved.architecture.free(); saved.destination.free(); saved.sha256.free() }
	saved = DeploymentSnapshotSaved{}
}

// Successful publication of a nonempty deployment lock from offline media.
pub struct DeploymentMediaSaved {
pub:
	format int = 1
	architecture string
	destination string
	sha256 string
	roots u64
	packages u64
}

pub fn (mut saved DeploymentMediaSaved) close() {
	unsafe { saved.architecture.free(); saved.destination.free(); saved.sha256.free() }
	saved = DeploymentMediaSaved{}
}

const deployment_saved_keys = ['format', 'generation', 'architecture', 'destination', 'sha256', 'roots', 'packages']

pub fn decode_deployment_saved(text string) !DeploymentSnapshotSaved {
	return decode_saved_deployment_receipt(text, false)
}

pub fn decode_deployment_media_saved(text string) !DeploymentMediaSaved {
	saved := decode_saved_deployment_receipt(text, true)!
	return DeploymentMediaSaved{ architecture: saved.architecture, destination: saved.destination,
		sha256: saved.sha256, roots: saved.roots, packages: saved.packages }
}

fn decode_saved_deployment_receipt(text string, media bool) !DeploymentSnapshotSaved {
	if text.len > 32 * 1024 { return error('saved deployment receipt exceeds its bound') }
	mut r := &MetadataReader{ text: text }; defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut saved := &DeploymentSnapshotSaved{}
	defer { unsafe { free(saved) } }
	mut accepted := false
	defer { if !accepted { saved.close() } }
	mut seen := u16(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(deployment_saved_keys, seen)!; seen |= u16(1) << field
		unsafe {
			match field {
				0 { r.expect(`1`)! }
				1 { *saved = DeploymentSnapshotSaved{ ...saved, generation: r.unsigned(~u64(0))! } }
				2 { *saved = DeploymentSnapshotSaved{ ...saved, architecture: r.quoted(16)! } }
				3 { *saved = DeploymentSnapshotSaved{ ...saved, destination: r.quoted(4096)! } }
				4 { *saved = DeploymentSnapshotSaved{ ...saved, sha256: r.quoted(64)! } }
				5 { *saved = DeploymentSnapshotSaved{ ...saved, roots: r.unsigned(4096)! } }
				6 { *saved = DeploymentSnapshotSaved{ ...saved, packages: r.unsigned(4096)! } }
				else {}
			}
		}
	}
	r.spaces()
	// Media receipts have no installed generation (field 1).
	expected := if media { u16(125) } else { u16(127) }
	if seen != expected || r.position != text.len { return error('unexpected or incomplete saved deployment receipt') }
	if media {
		if !saved.fields_valid() || saved.roots == 0 { return error('invalid saved deployment media receipt') }
	} else {
		saved.validate()!
	}
	accepted = true
	return *saved
}
