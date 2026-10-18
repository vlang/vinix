// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgprotocol

fn (a &SoftwareApp) review_space_sufficient() bool {
	if !a.review_snapshot.space_sufficient() { return false }
	// The UI owns the envelope and its review separately after decoding.
	if a.mirror_pending == '' { return true }
	mirror := pkgprotocol.MirrorReview{...a.mirror_snapshot, review: a.review_snapshot}
	return mirror.cache_space_sufficient()
}

fn software_space_problem(label string, budget pkgprotocol.DiskBudget) string {
	if budget.fits() { return '' }
	if budget.overflow { return label + ': required space plus reserve exceeds the supported byte counter. Review the operation again.' }
	bytes := budget.shortfall.str()
	defer { unsafe { bytes.free() } }
	ending := if budget.shortfall == 1 { ' additional byte is needed to preserve the reserved space.' }
		else { ' additional bytes are needed to preserve the reserved space.' }
	return label + ': at least ' + bytes + ending
}

fn (a &SoftwareApp) review_space_values(mut values []string) {
	if !a.review_snapshot.space_sufficient() {
		label := if a.mirror_pending == '' { 'Package storage' }
			else if a.mirror_snapshot.shared_disk { 'Export destination and cache' } else { 'Export destination' }
		values << software_space_problem(label, pkgprotocol.disk_budget(a.review_snapshot.disk_available,
			a.review_snapshot.disk_needed, a.review_snapshot.disk_reserve))
	}
	if a.mirror_pending != '' && !a.mirror_snapshot.shared_disk && a.mirror_snapshot.cache_needed > 0 {
		problem := software_space_problem('Package cache', pkgprotocol.disk_budget(a.mirror_snapshot.cache_available,
			a.mirror_snapshot.cache_needed, a.review_snapshot.disk_reserve))
		if problem != '' { values << problem }
	}
	if !a.review_space_sufficient() {
		values << 'Free space on the named filesystem, cancel this review, then review again. Confirmation is unavailable for this space estimate.'.clone()
	}
	values << 'Space estimates describe the review. The package service checks available space again before making changes.'.clone()
}

fn (a &SoftwareApp) review_space_problem() string {
	if a.review_space_sufficient() { return '' }
	mut values := []string{cap: 4}
	defer { software_policy_free_lines(mut values) }
	a.review_space_values(mut values)
	return values.join('\n')
}
