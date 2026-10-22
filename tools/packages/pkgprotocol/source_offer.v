// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// This record admits evidence for a local runtime experiment. It deliberately
// has no redistributable/complete state: corresponding-source qualification is
// a separate publisher boundary, not a boolean supplied by the caller.
pub struct LocalSourceArtifact {
pub:
	path string
	kind string
	sha256 string
	url string
}

pub struct LocalSourceOffer {
pub:
	format int
	status string
	source_closure_complete bool
	runtime string
	version string
	architecture string
	reason string
	artifacts []LocalSourceArtifact
}

fn close_local_source_artifact(artifact LocalSourceArtifact) {
	unsafe { artifact.path.free(); artifact.kind.free(); artifact.sha256.free(); artifact.url.free() }
}

// Independently decoded records own their fields. close is repeatable.
pub fn (mut offer LocalSourceOffer) close() {
	unsafe {
		offer.status.free(); offer.runtime.free(); offer.version.free()
		offer.architecture.free(); offer.reason.free()
		for artifact in offer.artifacts { close_local_source_artifact(artifact) }
		(&array(&offer.artifacts)).free()
	}
	offer = LocalSourceOffer{}
}

const local_source_offer_keys = ['format', 'status', 'source_closure_complete', 'runtime', 'version', 'architecture', 'reason', 'artifacts']
const local_source_artifact_keys = ['path', 'kind', 'sha256', 'url']

fn (mut r MetadataReader) local_source_artifact() !LocalSourceArtifact {
	r.expect(`{`)!
	mut artifact := LocalSourceArtifact{}
	mut accepted := false
	defer { if !accepted { close_local_source_artifact(artifact) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(local_source_artifact_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { artifact = LocalSourceArtifact{...artifact, path: r.quoted(128)!} }
			1 { artifact = LocalSourceArtifact{...artifact, kind: r.quoted(16)!} }
			2 { artifact = LocalSourceArtifact{...artifact, sha256: r.quoted(64)!} }
			3 { artifact = LocalSourceArtifact{...artifact, url: r.quoted(2048)!} }
			else {}
		}
	}
	if seen != 15 { return error('incomplete local source artifact') }
	if artifact.path == '' || artifact.path.starts_with('.') { return error('invalid local source artifact path') }
	for byte in artifact.path {
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`]!) {
			return error('local source artifacts must use plain file names')
		}
	}
	if artifact.path == 'source-offer.json' || artifact.kind !in ['notice', 'license', 'source', 'recipe', 'patch']! {
		return error('invalid local source artifact kind or reserved path')
	}
	if artifact.sha256.len != 64 { return error('invalid local source artifact digest') }
	for byte in artifact.sha256 {
		if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return error('invalid local source artifact digest') }
	}
	if artifact.url == 'local:publisher' {
		if artifact.kind !in ['notice', 'license']! { return error('source artifacts require HTTPS provenance') }
	} else {
		if !artifact.url.starts_with('https://') || artifact.url.len <= 8 { return error('source artifacts require HTTPS provenance') }
		for byte in artifact.url { if byte <= 32 || byte == 127 || byte == `\\` { return error('invalid source artifact URL') } }
	}
	accepted = true
	return artifact
}

fn (mut r MetadataReader) local_source_artifacts() ![]LocalSourceArtifact {
	r.expect(`[` )!
	mut artifacts := []LocalSourceArtifact{cap: 16}
	unsafe { artifacts.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { mut discarded := LocalSourceOffer{artifacts: artifacts}; discarded.close() } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if artifacts.len == 256 { return error('too many local source artifacts') }
		artifact := r.local_source_artifact()!
		mut duplicate := false
		for previous in artifacts { if previous.path == artifact.path { duplicate = true; break } }
		if duplicate { close_local_source_artifact(artifact); return error('duplicate local source artifact path') }
		unsafe { artifacts.push_many(&artifact, 1) }
	}
	if artifacts.len == 0 { return error('local source offer has no evidence artifacts') }
	accepted = true
	return artifacts
}

pub fn decode_local_source_offer(text string) !LocalSourceOffer {
	if text.len > 256 * 1024 { return error('local source offer exceeds metadata bound') }
	mut r := &MetadataReader{text: text}
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut offer := LocalSourceOffer{}
	mut accepted := false
	defer { if !accepted { offer.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(local_source_offer_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { offer = LocalSourceOffer{...offer, format: int(r.unsigned(1)!)} }
			1 { offer = LocalSourceOffer{...offer, status: r.quoted(32)!} }
			2 { offer = LocalSourceOffer{...offer, source_closure_complete: r.boolean()!} }
			3 { offer = LocalSourceOffer{...offer, runtime: r.quoted(128)!} }
			4 { offer = LocalSourceOffer{...offer, version: r.quoted(64)!} }
			5 { offer = LocalSourceOffer{...offer, architecture: r.quoted(16)!} }
			6 { offer = LocalSourceOffer{...offer, reason: r.quoted(4096)!} }
			7 { offer = LocalSourceOffer{...offer, artifacts: r.local_source_artifacts()!} }
			else {}
		}
	}
	r.spaces()
	if seen != 255 || r.position != text.len { return error('incomplete or trailing local source offer') }
	if offer.format != 1 || offer.status != 'local-qualification-only' || offer.source_closure_complete {
		return error('local source evidence cannot authorize redistribution or claim complete source closure')
	}
	if offer.runtime == '' || offer.version == '' || offer.reason == '' || offer.reason.contains('\x00')
		|| offer.architecture !in ['aarch64', 'x86_64']! { return error('invalid local source offer identity or scope') }
	for value in [offer.runtime, offer.version]! {
		for byte in value {
			if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
				|| (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`, `+`]!) {
				return error('invalid local source offer identity')
			}
		}
	}
	accepted = true
	return offer
}
