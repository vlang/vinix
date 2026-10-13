// SPDX-License-Identifier: GPL-2.0-or-later
// Complete bounded format-1 review schemas; no generic decoder allocations.
module pkgprotocol

const review_package_keys = ['id', 'name', 'description', 'version', 'installed_version', 'architecture', 'kind', 'runtime', 'repository', 'public_key', 'license', 'proprietary', 'firmware', 'permissions', 'requested', 'action']

fn (mut r MetadataReader) parse_review_package() !ReviewPackage {
	r.expect(`{`)!
	mut value := ReviewPackage{}
	mut accepted := false
	defer { if !accepted { close_review_package(value) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(review_package_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { value = ReviewPackage{ ...value, id: r.quoted(128)! } }
			1 { value = ReviewPackage{ ...value, name: r.quoted(256)! } }
			2 { value = ReviewPackage{ ...value, description: r.quoted(4096)! } }
			3 { value = ReviewPackage{ ...value, version: r.quoted(29)! } }
			4 { value = ReviewPackage{ ...value, installed_version: r.quoted(29)! } }
			5 { value = ReviewPackage{ ...value, architecture: r.quoted(16)! } }
			6 { value = ReviewPackage{ ...value, kind: r.quoted(16)! } }
			7 { value = ReviewPackage{ ...value, runtime: r.quoted(128)! } }
			8 { value = ReviewPackage{ ...value, repository: r.quoted(128)! } }
			9 { value = ReviewPackage{ ...value, public_key: r.quoted(64)! } }
			10 { value = ReviewPackage{ ...value, license: r.quoted(256)! } }
			11 { value = ReviewPackage{ ...value, proprietary: r.boolean()! } }
			12 { value = ReviewPackage{ ...value, firmware: r.boolean()! } }
			13 { value = ReviewPackage{ ...value, permissions: r.strings(16, 5)! } }
			14 { value = ReviewPackage{ ...value, requested: r.boolean()! } }
			15 { value = ReviewPackage{ ...value, action: r.quoted(16)! } }
			else {}
		}
	}
	if seen != 65535 { return error('missing review package field') }
	accepted = true
	return value
}

const review_keys = ['format', 'operation', 'names', 'architecture', 'generation', 'target_generation', 'fingerprint', 'requested', 'rows', 'disk_needed', 'disk_available', 'disk_reserve']

fn (mut r MetadataReader) parse_review() !Review {
	r.expect(`{`)!
	mut value := Review{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(review_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = Review{ ...value, format: 1 } }
			1 { value = Review{ ...value, operation: r.quoted(16)! } }
			2 { value = Review{ ...value, names: r.strings(128, 4096)! } }
			3 { value = Review{ ...value, architecture: r.quoted(16)! } }
			4 { value = Review{ ...value, generation: r.unsigned(~u64(0))! } }
			5 { value = Review{ ...value, target_generation: r.unsigned(~u64(0))! } }
			6 { value = Review{ ...value, fingerprint: r.quoted(64)! } }
			7 { value = Review{ ...value, requested: r.strings(128, 4096)! } }
			8 { value = Review{ ...value, rows: r.parse_review_packages()! } }
			9 { value = Review{ ...value, disk_needed: r.unsigned(~u64(0))! } }
			10 { value = Review{ ...value, disk_available: r.unsigned(~u64(0))! } }
			11 { value = Review{ ...value, disk_reserve: r.unsigned(~u64(0))! } }
			else {}
		}
	}
	if seen != 4095 { return error('missing review field') }
	value.validate()!
	accepted = true
	return value
}

pub fn decode_review(text string) !Review {
	if text.len > 8 * 1024 * 1024 { return error('package metadata exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_review()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing package metadata') }
	return value
}

const repository_keys = ['id', 'url', 'public_key']

fn (mut r MetadataReader) parse_repository() !Repository {
	r.expect(`{`)!
	mut value := Repository{}
	mut accepted := false
	defer { if !accepted { close_repository(value) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(repository_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { value = Repository{ ...value, id: r.quoted(128)! } }
			1 { value = Repository{ ...value, url: r.quoted(4096)! } }
			2 { value = Repository{ ...value, public_key: r.quoted(64)! } }
			else {}
		}
	}
	if seen != 7 { return error('missing repository field') }
	accepted = true
	return value
}

const repository_floor_keys = ['id', 'public_key', 'sequence', 'index_sha256']

fn (mut r MetadataReader) parse_repository_floor() !RepositoryFloor {
	r.expect(`{`)!
	mut value := RepositoryFloor{}
	mut accepted := false
	defer { if !accepted { close_repository_floor(value) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(repository_floor_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { value = RepositoryFloor{ ...value, id: r.quoted(128)! } }
			1 { value = RepositoryFloor{ ...value, public_key: r.quoted(64)! } }
			2 { value = RepositoryFloor{ ...value, sequence: r.unsigned(~u64(0))! } }
			3 { value = RepositoryFloor{ ...value, index_sha256: r.quoted(64)! } }
			else {}
		}
	}
	if seen != 15 { return error('missing repository floor field') }
	accepted = true
	return value
}

const repository_status_keys = ['format', 'architecture', 'repositories', 'history']

fn (mut r MetadataReader) parse_repository_status() !RepositoryStatus {
	r.expect(`{`)!
	mut value := RepositoryStatus{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(repository_status_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = RepositoryStatus{ ...value, format: 1 } }
			1 { value = RepositoryStatus{ ...value, architecture: r.quoted(16)! } }
			2 { value = RepositoryStatus{ ...value, repositories: r.parse_repositories()! } }
			3 { value = RepositoryStatus{ ...value, history: r.parse_repository_floors()! } }
			else {}
		}
	}
	if seen != 15 { return error('missing repository status field') }
	value.validate()!
	accepted = true
	return value
}

pub fn decode_repositories(text string) !RepositoryStatus {
	if text.len > 8 * 1024 * 1024 { return error('package metadata exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_repository_status()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing package metadata') }
	return value
}

const repository_review_keys = ['format', 'operation', 'architecture', 'id', 'url', 'public_key', 'previous_url', 'previous_public_key', 'fingerprint', 'index_sha256', 'sequence', 'expires', 'package_count', 'remembered_sequence']

fn (mut r MetadataReader) parse_repository_review() !RepositoryReview {
	r.expect(`{`)!
	mut value := RepositoryReview{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(repository_review_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = RepositoryReview{ ...value, format: 1 } }
			1 { value = RepositoryReview{ ...value, operation: r.quoted(16)! } }
			2 { value = RepositoryReview{ ...value, architecture: r.quoted(16)! } }
			3 { value = RepositoryReview{ ...value, id: r.quoted(128)! } }
			4 { value = RepositoryReview{ ...value, url: r.quoted(4096)! } }
			5 { value = RepositoryReview{ ...value, public_key: r.quoted(64)! } }
			6 { value = RepositoryReview{ ...value, previous_url: r.quoted(4096)! } }
			7 { value = RepositoryReview{ ...value, previous_public_key: r.quoted(64)! } }
			8 { value = RepositoryReview{ ...value, fingerprint: r.quoted(64)! } }
			9 { value = RepositoryReview{ ...value, index_sha256: r.quoted(64)! } }
			10 { value = RepositoryReview{ ...value, sequence: r.unsigned(~u64(0))! } }
			11 { value = RepositoryReview{ ...value, expires: i64(r.unsigned(u64(0x7fffffffffffffff))!) } }
			12 { value = RepositoryReview{ ...value, package_count: int(r.unsigned(u64(4096))!) } }
			13 { value = RepositoryReview{ ...value, remembered_sequence: r.unsigned(~u64(0))! } }
			else {}
		}
	}
	if seen != 16383 { return error('missing repository review field') }
	value.validate()!
	accepted = true
	return value
}

pub fn decode_repository_review(text string) !RepositoryReview {
	if text.len > 8 * 1024 * 1024 { return error('package metadata exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_repository_review()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing package metadata') }
	return value
}

const mirror_review_keys = ['format', 'input_destination', 'destination', 'review', 'cache_needed', 'cache_available', 'shared_disk']

fn (mut r MetadataReader) parse_mirror_review() !MirrorReview {
	r.expect(`{`)!
	mut value := MirrorReview{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(mirror_review_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = MirrorReview{ ...value, format: 1 } }
			1 { value = MirrorReview{ ...value, input_destination: r.quoted(4096)! } }
			2 { value = MirrorReview{ ...value, destination: r.quoted(4096)! } }
			3 { value = MirrorReview{ ...value, review: r.parse_review()! } }
			4 { value = MirrorReview{ ...value, cache_needed: r.unsigned(~u64(0))! } }
			5 { value = MirrorReview{ ...value, cache_available: r.unsigned(~u64(0))! } }
			6 { value = MirrorReview{ ...value, shared_disk: r.boolean()! } }
			else {}
		}
	}
	if seen != 127 { return error('missing mirror review field') }
	value.validate()!
	accepted = true
	return value
}

pub fn decode_mirror_review(text string) !MirrorReview {
	if text.len > 8 * 1024 * 1024 { return error('package metadata exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_mirror_review()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing package metadata') }
	return value
}

const deployment_mirror_review_keys = ['format', 'deployment', 'deployment_sha256', 'mirror']

fn (mut r MetadataReader) parse_deployment_mirror_review() !DeploymentMirrorReview {
	r.expect(`{`)!
	mut value := DeploymentMirrorReview{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(deployment_mirror_review_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = DeploymentMirrorReview{ ...value, format: 1 } }
			1 { value = DeploymentMirrorReview{ ...value, deployment: r.quoted(4096)! } }
			2 { value = DeploymentMirrorReview{ ...value, deployment_sha256: r.quoted(64)! } }
			3 { value = DeploymentMirrorReview{ ...value, mirror: r.parse_mirror_review()! } }
			else {}
		}
	}
	if seen != 15 { return error('missing deployment mirror review field') }
	value.validate()!
	accepted = true
	return value
}

pub fn decode_deployment_mirror_review(text string) !DeploymentMirrorReview {
	if text.len > 8 * 1024 * 1024 { return error('package metadata exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_deployment_mirror_review()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing package metadata') }
	return value
}

fn (mut r MetadataReader) parse_review_packages() ![]ReviewPackage {
	r.expect(`[`)!
	mut values := []ReviewPackage{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { close_review_package(value) }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 8192 { return error('package metadata array exceeds entry limit') }
		value := r.parse_review_package()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r MetadataReader) parse_repositories() ![]Repository {
	r.expect(`[`)!
	mut values := []Repository{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { close_repository(value) }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('package metadata array exceeds entry limit') }
		value := r.parse_repository()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r MetadataReader) parse_repository_floors() ![]RepositoryFloor {
	r.expect(`[`)!
	mut values := []RepositoryFloor{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { close_repository_floor(value) }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('package metadata array exceeds entry limit') }
		value := r.parse_repository_floor()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}
