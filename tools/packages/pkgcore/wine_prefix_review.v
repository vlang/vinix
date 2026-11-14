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
}

pub fn (mut owner WinePrefixReview) close() {
	owner.review.close()
	owner.admission.close()
	owner = WinePrefixReview{}
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
	mut owner := WinePrefixReview{}
	mut accepted := false
	defer { if !accepted { owner.close() } }
	owner.admission = service.wine_admission(id)!
	owner.review = owner.admission.capture_prefix(data)!
	accepted = true
	return owner
}
