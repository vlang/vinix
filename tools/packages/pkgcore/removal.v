// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Borrowed identities from a validated installed state. The diagnostic names
// one retained requested package, even through shared dependencies or cycles.
struct RemovalBlocker {
	id string
	root string
}

struct RemovalVisit {
	package int
	root int
}

fn removal_blocker(state State, names []string, target string) ?RemovalBlocker {
	if state.packages.len > 4096 || state.requested.len > 4096 || names.len > 4096 { return none }
	mut positions := map[string]int{}
	mut removed := map[string]bool{}
	mut seen := []bool{len: state.packages.len}
	mut roots := []string{cap: state.requested.len}
	mut pending := []RemovalVisit{cap: state.packages.len}
	unsafe { roots.flags |= .noslices; pending.flags |= .noslices }
	defer { unsafe {
		positions.free(); removed.free(); seen.free()
		(&array(&roots)).free(); (&array(&pending)).free()
	} }
	for index, installed in state.packages { positions[installed.package.id] = index }
	for id in names { removed[id] = true }
	for id in state.requested {
		if id in removed { continue }
		pointer := unsafe { &id }
		unsafe { roots.push_many(pointer, 1) }
	}
	roots.sort()
	for id in roots {
		index := positions[id] or { continue }
		if seen[index] { continue }
		seen[index] = true
		pending << RemovalVisit{package: index, root: index}
	}
	mut next := 0
	for next < pending.len {
		visit := pending[next]
		next++
		p := state.packages[visit.package].package
		if p.id in removed && (target == '' || p.id == target) {
			return RemovalBlocker{id: p.id, root: state.packages[visit.root].package.id}
		}
		for dependency in p.dependencies {
			index := positions[dependency.id] or { continue }
			if seen[index] { continue }
			seen[index] = true
			pending << RemovalVisit{package: index, root: visit.root}
		}
	}
	return none
}
