// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgprotocol

// Counts include dependencies. Unknown installed facts never count as empty.
fn (a &SoftwareApp) review_permission_counts() [3]int {
	mut counts := [3]int{}
	if a.review_snapshot.operation == 'mirror' { return counts }
	for row in a.review_snapshot.rows {
		if row.installed_version != '' && !row.installed_permissions_known { counts[2]++; continue }
		if row.action != 'remove' {
			for permission in row.permissions { if permission !in row.installed_permissions { counts[0]++ } }
		}
		for permission in row.installed_permissions {
			if row.action == 'remove' || permission !in row.permissions { counts[1]++ }
		}
	}
	return counts
}

fn (a &SoftwareApp) review_permission_summary(mut values []string) {
	if a.review_snapshot.operation == 'mirror' { return }
	counts := a.review_permission_counts()
	software_details_count(mut values, 'Known added permission declarations: ', u64(counts[0]))
	software_details_count(mut values, 'Known removed permission declarations: ', u64(counts[1]))
	software_details_count(mut values, 'Packages with unavailable prior declarations: ', u64(counts[2]))
	values << 'Inspect Permissions for each reviewed package, including dependencies. Declarations do not override current organization policy or runtime isolation.'.clone()
}

fn (a &SoftwareApp) review_permission_notice() string {
	mut values := []string{cap: 4}
	defer { software_policy_free_lines(mut values) }
	a.review_permission_summary(mut values)
	return values.join('\n')
}

fn software_review_permission_values(row pkgprotocol.ReviewPackage, mut values []string) {
	values << 'Reviewed permission declarations describe version ' + row.version
	if row.action == 'export' {
		values << 'Export copies the declared package. It does not change installed permission declarations.'.clone()
		return
	}
	if row.installed_version == '' { values << 'Previous declarations: Not installed'.clone() }
	else if !row.installed_permissions_known {
		values << 'Previous declarations: Unavailable from this service; changes cannot be compared.'.clone()
		return
	} else {
		values << 'Previous declarations describe installed version ' + row.installed_version
		if row.installed_permissions.len == 0 { values << 'Previous permissions: None declared'.clone() }
		for permission in row.installed_permissions { values << 'Previous permission: ' + permission }
	}
	mut changed := false
	if row.action != 'remove' {
		for permission in row.permissions {
			if permission !in row.installed_permissions { values << 'Added permission declaration: ' + permission; changed = true }
			else { values << 'Unchanged permission declaration: ' + permission }
		}
	}
	for permission in row.installed_permissions {
		if row.action == 'remove' || permission !in row.permissions {
			values << 'Removed permission declaration: ' + permission; changed = true
		}
	}
	if !changed { values << 'No permission declaration changes for this package.'.clone() }
	if row.action == 'remove' { values << 'Uninstall removes this package and its declarations. Other reviewed packages have their own declarations.'.clone() }
	values << 'Current organization policy and runtime isolation still govern access.'.clone()
}
