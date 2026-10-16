// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

struct Search {
	config Config
	candidates []Installed
mut:
	steps int
	diagnostic string
}

struct CandidateChain {
	first int
	last int
}

struct SearchDecision {
	constraint int
	pending_length int
	selected_length int
	next_candidate int
}

fn (mut s Search) tick() ! {
	if s.steps >= 100000 { return error('dependency resolution exceeded its search limit; narrow the requested versions') }
	s.steps++
}

fn (mut s Search) explain(text string) {
	next := text.clone()
	unsafe { s.diagnostic.free() }
	s.diagnostic = next
}

// Only an exhausted choice publishes a policy refusal. A rejected alternative
// followed by a usable candidate must not become a later requirement's cause.
// Backtracking past the final alternative preserves the deeper branch failure.
fn (mut s Search) choose(dependency Dependency, start int, links []int, retry bool) !(int, bool) {
	mut index := start
	mut refusal := ''
	defer { unsafe { refusal.free() } }
	for index >= 0 {
		s.tick()!
		p := s.candidates[index].package
		if p.architecture in [s.config.architecture, 'all'] && dependency.accepts(p) {
			check_policy(p, s.config.policy) or {
				message := err.msg()
				unsafe { refusal.free(); err.free() }; refusal = message
				index = links[index]; continue
			}
			return index, false
		}
		index = links[index]
	}
	if refusal != '' { s.explain(refusal); return -1, true }
	if !retry {
		text := 'no trusted ${s.config.architecture} candidate satisfies ${dependency.id} (${dependency.minimum} .. ${dependency.before})'
		s.explain(text); unsafe { text.free() }
		return -1, true
	}
	return -1, false
}

fn search_diagnostic_append(mut bytes []u8, text string) {
	// Validated IDs/ranges and the bounded reason fit within this envelope.
	mut end := if text.len > 4096 - bytes.len { 4096 - bytes.len } else { text.len }
	for end > 0 && end < text.len && text[end] & 0xc0 == 0x80 { end-- }
	for i in 0 .. end { bytes << text[i] }
}

fn (mut s Search) trace_requirement(cursor int, pending []Dependency, parents []int, fixed_root string) {
	if cursor < 0 && fixed_root == '' { return }
	mut chain := [14]int{}
	mut count := 0
	mut depth := 0
	mut root := -1
	mut at := cursor
	for at >= 0 && at < pending.len && at < parents.len {
		if count < chain.len { chain[count] = at; count++ }
		root = at; depth++; at = parents[at]
	}
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut reason_end := if s.diagnostic.len > 1024 { 1024 } else { s.diagnostic.len }
	for reason_end > 0 && reason_end < s.diagnostic.len && s.diagnostic[reason_end] & 0xc0 == 0x80 { reason_end-- }
	search_diagnostic_append(mut bytes, unsafe { tos(s.diagnostic.str, reason_end) })
	if reason_end < s.diagnostic.len { search_diagnostic_append(mut bytes, ' ... (reason truncated)') }
	search_diagnostic_append(mut bytes, '\nDependency path: ')
	if fixed_root != '' {
		search_diagnostic_append(mut bytes, fixed_root)
		if count > 0 { search_diagnostic_append(mut bytes, ' -> ') }
	}
	if depth > chain.len {
		search_diagnostic_append(mut bytes, pending[root].id)
		search_diagnostic_append(mut bytes, if depth > chain.len + 1 { ' -> ... -> ' } else { ' -> ' })
	}
	for i := count - 1; i >= 0; i-- {
		search_diagnostic_append(mut bytes, pending[chain[i]].id)
		if i > 0 { search_diagnostic_append(mut bytes, ' -> ') }
	}
	if cursor >= 0 && cursor < pending.len {
		requirement := pending[cursor]
		search_diagnostic_append(mut bytes, '\nRequirement: ')
		search_diagnostic_append(mut bytes, requirement.id)
		if requirement.minimum != '' { search_diagnostic_append(mut bytes, ' >= '); search_diagnostic_append(mut bytes, requirement.minimum) }
		if requirement.before != '' { search_diagnostic_append(mut bytes, ' < '); search_diagnostic_append(mut bytes, requirement.before) }
	}
	next := bytes.bytestr()
	unsafe { s.diagnostic.free() }; s.diagnostic = next
}

fn (mut s Search) runtimes_ready(selected []int, assigned map[string]int, pending []Dependency, parents []int, fixed_root string) bool {
	for index in selected {
		p := s.candidates[index].package
		if p.runtime == '' { continue }
		runtime_index := assigned[p.runtime] or { -1 }
		if runtime_index < 0 || s.candidates[runtime_index].package.kind != 'runtime'
			|| !s.candidates[runtime_index].package.files.any(it.path == p.entrypoint && it.executable) {
			text := '${p.id}: isolated runtime ${p.runtime} does not provide ${p.entrypoint}'
			s.explain(text); unsafe { text.free() }
			mut constraint := -1
			for i, dependency in pending { if dependency.id == p.id { constraint = i; break } }
			s.trace_requirement(constraint, pending, parents, fixed_root)
			return false
		}
	}
	return true
}

// Consume a FIFO worklist, expanding each chosen identity once. Decisions save
// lengths/cursors, so backtracking retires only later assignments and appended
// requirements. No recursion or copied branch graphs are needed for cycles,
// dense shared dependencies or constraints discovered after a selection.
fn (mut s Search) solve(initial []Dependency) ![]Installed {
	return s.solve_fixed(initial, [])
}

// Publisher checks pin an advertised root, including its exact architecture,
// instead of allowing a working alternative to hide a broken release variant.
fn (mut s Search) solve_fixed(initial []Dependency, fixed []int) ![]Installed {
	mut groups := map[string]CandidateChain{}
	mut links := []int{len: s.candidates.len, init: -1}
	mut assigned := map[string]int{}
	mut pending := []Dependency{cap: initial.len + 128}
	mut parents := []int{len: initial.len, cap: initial.len + 128, init: -1}
	mut selected := []int{cap: 128}
	mut decisions := []SearchDecision{cap: 128}
	unsafe { pending.flags |= .noslices; parents.flags |= .noslices; selected.flags |= .noslices; decisions.flags |= .noslices }
	defer {
		unsafe {
			groups.free(); assigned.free(); links.free()
			(&array(&pending)).free(); parents.free(); selected.free(); (&array(&decisions)).free()
		}
	}
	for index, candidate in s.candidates {
		id := candidate.package.id
		if id in groups {
			group := groups[id]
			links[group.last] = index
			groups[id] = CandidateChain{first: group.first, last: index}
		} else { groups[id] = CandidateChain{first: index, last: index} }
	}
	for index in fixed {
		if index < 0 || index >= s.candidates.len || s.candidates[index].package.id in assigned {
			return error('invalid fixed dependency selection')
		}
		assigned[s.candidates[index].package.id] = index
		selected << index
	}
	fixed_root := if fixed.len == 1 { s.candidates[fixed[0]].package.id } else { '' }
	unsafe { pending.push_many(initial.data, initial.len) }
	mut cursor := 0
	for {
		s.tick()!
		mut choice := -1
		mut diagnosed := false
		mut decision := SearchDecision{}
		if cursor == pending.len {
			if s.runtimes_ready(selected, assigned, pending, parents, fixed_root) {
				mut result := []Installed{cap: selected.len}
				for index in selected {
					candidate := s.candidates[index]
					pointer := unsafe { &candidate }
					unsafe { result.push_many(pointer, 1) }
				}
				return result
			}
		} else {
			dependency := pending[cursor]
			if dependency.id in assigned {
				if dependency.accepts(s.candidates[assigned[dependency.id]].package) { cursor++; continue }
				version := s.candidates[assigned[dependency.id]].package.version
				text := 'conflicting version requirements for ${dependency.id}: selected ${version}'
				s.explain(text); unsafe { text.free() }
				s.trace_requirement(cursor, pending, parents, fixed_root)
			} else {
				group := groups[dependency.id] or { CandidateChain{first: -1} }
				choice, diagnosed = s.choose(dependency, group.first, links, false)!
				if diagnosed { s.trace_requirement(cursor, pending, parents, fixed_root) }
				decision = SearchDecision{constraint: cursor, pending_length: pending.len, selected_length: selected.len}
			}
		}
		if choice < 0 {
			for decisions.len > 0 {
				decision = decisions.pop()
				for index in decision.selected_length .. selected.len { assigned.delete(s.candidates[selected[index]].package.id) }
				selected.trim(decision.selected_length)
				pending.trim(decision.pending_length)
				parents.trim(decision.pending_length)
				cursor = decision.constraint
				choice, diagnosed = s.choose(pending[cursor], decision.next_candidate, links, true)!
				if diagnosed { s.trace_requirement(cursor, pending, parents, fixed_root) }
				if choice >= 0 { break }
			}
			if choice < 0 { return error(s.diagnostic.clone()) }
		}
		if selected.len == 4096 { return error('resolved package closure exceeds its 4096-package limit') }
		package := s.candidates[choice].package
		if package.dependencies.len > 128 { return error('package exceeds its dependency limit') }
		assigned[package.id] = choice
		selected << choice
		next := SearchDecision{ ...decision, next_candidate: links[choice] }
		pointer := unsafe { &next }
		unsafe { decisions.push_many(pointer, 1); pending.push_many(package.dependencies.data, package.dependencies.len) }
		for _ in package.dependencies { parents << cursor }
		cursor++
	}
	return error('dependency resolution ended without a closure')
}
