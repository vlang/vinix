// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.wineadapter

// One owner; do not copy or close concurrently. Retains both the generation
// lease and prefix coordination. The report is borrowed until close.
pub struct WinePrefixReview {
pub mut:
	review wineadapter.IdleBindingReview
mut:
	admission WineAdmission
	root string
	application string
}

pub fn (mut owner WinePrefixReview) close() {
	owner.review.close()
	owner.admission.close()
	unsafe { owner.root.free(); owner.application.free() }
	owner = WinePrefixReview{}
}

// Refresh trust/policy and require the admitted generation to remain active.
// Hold the package reader lock while checking payloads and prefix continuity.
// This is admission at the time of the call, not authority for a later write.
pub fn (owner &WinePrefixReview) recheck() ! {
	if owner.admission.prepared.lease < 0 || !identifier(owner.application) {
		return error('Wine prefix review is closed or lacks service admission')
	}
	service := Service{root: owner.root}
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if directory != owner.admission.prepared.directory { return error('Wine prefix review package store differs') }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	if current.generation != owner.admission.generation { return error('Wine prefix review active generation changed') }
	current_metadata := encode_generation_state(current)!
	defer { unsafe { current_metadata.free() } }
	retained_metadata := encode_generation_state(owner.admission.prepared.state)!
	defer { unsafe { retained_metadata.free() } }
	if current_metadata != retained_metadata { return error('Wine prefix review active generation metadata changed') }
	verify_launch_payloads(config, directory, owner.admission.prepared.state, owner.application)!
	owner.review.recheck()!
}

// Keep package transactions excluded throughout fresh admission and exclusive
// additions. Retargeting is refused; partial progress resumes via fresh review.
pub fn (mut owner WinePrefixReview) complete_additions() ! {
	if owner.admission.prepared.lease < 0 { return error('Wine prefix review is closed') }
	guard := acquire_reader(owner.admission.prepared.directory)!
	defer { guard.release() }
	owner.recheck()!
	owner.review.complete_additions()!
	owner.recheck()!
}

pub fn (mut owner WinePrefixReview) migrate_bindings() ! {
	if owner.admission.prepared.lease < 0 { return error('Wine prefix review is closed') }
	guard := acquire_reader(owner.admission.prepared.directory)!
	defer { guard.release() }
	owner.recheck()!
	owner.review.migrate_bindings()!
	owner.recheck()!
}

fn wine_builtin_expectations(runtime Package) ![]wineadapter.BuiltinExpectation {
	prefix := 'root/usr/lib/wine/x86_64-windows/'
	mut expected := []wineadapter.BuiltinExpectation{cap: runtime.files.len}
	mut accepted := false
	defer { if !accepted { free_wine_expectations(mut expected) } }
	for file in runtime.files {
		if !file.path.starts_with(prefix) { continue }
		name := file.path[prefix.len..]
		if name == '' || name.contains('/') || name == '.' || name == '..' {
			unsafe { name.free() }
			return error('Wine builtin manifest inventory must be flat')
		}
		expected << wineadapter.BuiltinExpectation{name: name, sha256: file.sha256.clone(), bytes: file.bytes}
		if expected.len > 900 { return error('Wine builtin manifest inventory exceeds 900 entries') }
	}
	if expected.len == 0 { return error('Wine runtime manifest has no Windows builtins') }
	accepted = true
	return expected
}

fn free_wine_expectations(mut expected []wineadapter.BuiltinExpectation) {
	unsafe {
		for entry in expected { entry.name.free(); entry.sha256.free() }
		(&array(&expected)).free()
	}
}

fn (admission &WineAdmission) capture_prefix(data string) !wineadapter.IdleBindingReview {
	if admission.prepared.lease < 0 || admission.generation == 0 || !identifier(admission.runtime.id) {
		return error('Wine prefix review requires live runtime admission')
	}
	mut expected := wine_builtin_expectations(admission.runtime)!
	defer { free_wine_expectations(mut expected) }
	number := admission.generation.str()
	builtins := admission.prepared.directory + '/generations/' + number + '/apps/' + admission.runtime.id + '/root/usr/lib/wine/x86_64-windows'
	defer { unsafe { number.free(); builtins.free() } }
	mut review := wineadapter.capture_idle_binding_review(data, builtins, admission.prepared.directory)!
	review.require_builtin_inventory(admission.runtime.id, admission.generation, expected) or { review.close(); return err }
	return review
}

// Admission uses current launch verification. Review never changes builtin
// links. Future application must recheck at use and provide crash recovery.
pub fn (service Service) wine_prefix_review(id string, data string) !WinePrefixReview {
	mut value := WinePrefixReview{root: service.root.clone(), application: id.clone()}
	// Capture helpers borrow field addresses synchronously. Return the owner
	// by value while keeping its temporary shell on the stack.
	mut owner := unsafe { &value }
	mut accepted := false
	defer { if !accepted { owner.close() } }
	owner.admission = service.wine_admission(id)!
	owner.review = owner.admission.capture_prefix(data)!
	owner.recheck()!
	accepted = true
	return *owner
}
