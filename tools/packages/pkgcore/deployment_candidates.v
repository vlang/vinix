// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Match all pins in one catalog pass. Scratch and returned array storage scale
// with the lock, rather than allocating a full catalog-sized filter per pin.
// Returned manifests and publisher strings continue to borrow the catalog.
fn locked_deployment_candidates(catalog Catalog, document DeploymentLock) ![]Installed {
	if document.locked.len > 4096 {
		return error('locked deployment matching exceeds its input limits')
	}
	mut positions := map[string]int{}
	mut counts := []u8{len: document.locked.len}
	defer { unsafe { positions.free(); counts.free() } }
	mut candidates := []Installed{len: document.locked.len}
	mut accepted := false
	defer { if !accepted { unsafe { (&array(&candidates)).free() } } }
	for index, pin in document.locked {
		if pin.id in positions { return error('duplicate locked deployment package: ' + pin.id) }
		positions[pin.id] = index
	}
	if document.locked.len > 0 {
		for candidate in catalog.packages {
			if position := positions[candidate.package.id] {
				pin := document.locked[position]
				if candidate.package.version != pin.version || candidate.package.architecture != pin.architecture
					|| candidate.repository != pin.repository || candidate.public_key != pin.public_key { continue }
				if counts[position] == 0 { candidates[position] = candidate }
				// Saturate at ambiguity; hostile duplicate counts cannot wrap.
				if counts[position] < 2 { counts[position]++ }
			}
		}
	}
	for index, pin in document.locked {
		if counts[index] == 0 {
			return error('${pin.id}: locked ${pin.version}/${pin.architecture} publisher is absent from the authenticated catalog; restore the approved repository or regenerate the deployment lock')
		}
		if counts[index] != 1 {
			return error('${pin.id}: locked ${pin.version}/${pin.architecture} publisher is ambiguous in the authenticated catalog; restore unambiguous publisher metadata')
		}
		candidate := candidates[index]
		if candidate.sequence < pin.minimum_sequence {
			return error('${pin.id}: locked publisher sequence or package metadata changed; review a new deployment lock')
		}
		digest := package_metadata_digest(candidate.package)!
		defer { unsafe { digest.free() } }
		if digest != pin.metadata_sha256 {
			return error('${pin.id}: locked publisher sequence or package metadata changed; review a new deployment lock')
		}
	}
	accepted = true
	return candidates
}
