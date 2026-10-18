// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SoftwareDependencyEdge {
	dependent int
	next int
}

// Return one borrowed requested-package ID that requires target, directly or
// transitively. Reverse edges make selection linear in the installed graph;
// cycles and shared runtimes visit each package at most once. The lexical
// witness is independent of the service's row and dependency ordering.
fn software_required_by(rows []SoftwareRow, target string) string {
	if rows.len > 4096 { return '' }
	mut positions := map[string]int{}
	mut edge_count := 0
	defer { unsafe { positions.free() } }
	for index, row in rows {
		if row.installed_version == '' { continue }
		if row.installed_dependencies.len > 128 { return '' }
		positions[row.id] = index
		if row.installed_dependencies_known { edge_count += row.installed_dependencies.len }
	}
	start := positions[target] or { return '' }
	mut heads := []int{len: rows.len, init: -1}
	mut edges := []SoftwareDependencyEdge{cap: edge_count}
	mut seen := []bool{len: rows.len}
	mut pending := []int{cap: rows.len}
	defer { unsafe { heads.free(); (&array(&edges)).free(); seen.free(); pending.free() } }
	for index, row in rows {
		if row.installed_version == '' || !row.installed_dependencies_known { continue }
		for dependency in row.installed_dependencies {
			position := positions[dependency.id] or { continue }
			edges << SoftwareDependencyEdge{dependent: index, next: heads[position]}
			heads[position] = edges.len - 1
		}
	}
	pending << start; seen[start] = true
	mut next := 0
	for next < pending.len {
		position := pending[next]; next++
		mut edge := heads[position]
		for edge >= 0 {
			dependent := edges[edge].dependent
			if !seen[dependent] { seen[dependent] = true; pending << dependent }
			edge = edges[edge].next
		}
	}
	mut witness := ''
	for index, row in rows {
		if index != start && seen[index] && row.requested && (witness == '' || row.id < witness) { witness = row.id }
	}
	return witness
}

fn software_dependency_usage_incomplete(rows []SoftwareRow) bool {
	if rows.len > 4096 { return true }
	mut installed := map[string]bool{}
	defer { unsafe { installed.free() } }
	for row in rows {
		if row.installed_version == '' { continue }
		if !row.installed_dependencies_known || row.installed_dependencies.len > 128 { return true }
		installed[row.id] = true
	}
	for row in rows {
		if row.installed_version == '' { continue }
		for dependency in row.installed_dependencies { if dependency.id !in installed { return true } }
	}
	return false
}

fn (a &SoftwareApp) installed_dependency_values(row SoftwareRow, mut values []string) {
	values << 'Dependency facts describe the installed generation; an update preview does not change them.'.clone()
	if !row.installed_dependencies_known {
		values << 'Installed requirements: Unavailable from this service'.clone()
	} else if row.installed_dependencies.len == 0 {
		values << 'Installed requirements: None declared'.clone()
	} else {
		for dependency in row.installed_dependencies {
			mut installed := ''
			for item in a.rows { if item.id == dependency.id { installed = item.installed_version; break } }
			values << 'Installed requirement: ' + dependency.id
			values << 'Minimum version (inclusive): ' + if dependency.minimum == '' { 'Unbounded' } else { dependency.minimum }
			values << 'Before version (exclusive): ' + if dependency.before == '' { 'Unbounded' } else { dependency.before }
			values << 'Dependency installed version: ' + if installed == '' { 'Unavailable' } else { installed }
		}
	}
	witness := software_required_by(a.rows, row.id)
	if witness != '' {
		values << 'Required by requested package: ' + witness
		values << 'This is one requiring application, possibly through other dependencies.'.clone()
	}
	if software_dependency_usage_incomplete(a.rows) {
		values << 'Dependency usage is incomplete: requirements or installed dependency versions are unavailable.'.clone()
	} else if witness == '' {
		values << 'No other requested package requires this package.'.clone()
	}
	values << 'Remove requested applications through a reviewed uninstall. Unused dependencies are removed with them.'.clone()
}
