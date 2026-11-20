// SPDX-License-Identifier: GPL-2.0-or-later
// Find strings appended to an array that the same function then frees.
// V copies only a string's header (pointer and length) on `arr << s`, as Go
// does, so freeing `s` afterwards leaves the array holding freed bytes.
// Names are matched textually, so a hit may be a non-string or a path that
// returns first; each needs reading. README.md lists the reviewed ones.
//
//   v run tests/push-ownership/check.v kernel tools desktop build-support
module main

import os

struct Hit {
	file  string
	push  int
	free  int
	name  string
	array string
}

fn functions(lines []string) [][]int {
	// [start, end) line ranges of top-level fns; a fn ends at the next one.
	mut starts := []int{}
	for i, line in lines {
		if line.starts_with('fn ') || line.starts_with('pub fn ') {
			starts << i
		}
	}
	mut ranges := [][]int{}
	for k, s in starts {
		e := if k + 1 < starts.len { starts[k + 1] } else { lines.len }
		ranges << [s, e]
	}
	return ranges
}

fn scan(path string) []Hit {
	text := os.read_file(path) or { return [] }
	lines := text.split_into_lines()
	mut hits := []Hit{}
	for r in functions(lines) {
		for i in r[0] .. r[1] {
			line := lines[i].trim_space().all_before('//').trim_space()
			if !line.contains(' << ') {
				continue
			}
			array := line.all_before(' << ').all_after_last('{').trim_space()
			mut tail := line.all_after(' << ').trim_space()
			mut end := 0
			for end < tail.len && (tail[end].is_letter() || tail[end].is_digit() || tail[end] == `_`) {
				end++
			}
			// Only a bare name: `a << s`, `a << s }`, `a << s; ...`; not `s.f` or `s.clone()`.
			name := tail[..end]
			rest := tail[end..].trim_space()
			if name == '' || !(name[0].is_letter() || name[0] == `_`) || !(rest == '' || rest.starts_with('}') || rest.starts_with(';')) {
				continue
			}
			if name in ['true', 'false', 'none', 'it'] {
				continue
			}
			freed := '${name}.free()'
			for j in r[0] .. r[1] {
				if j == i {
					continue
				}
				other := lines[j].all_before('//')
				if other.contains(freed) && !other.contains('.${freed}') {
					hits << Hit{path, i + 1, j + 1, name, array}
					break
				}
			}
		}
	}
	return hits
}

fn main() {
	for dir in os.args[1..] {
		mut files := os.walk_ext(dir, '.v').filter(!it.ends_with('_test.v') && !it.contains('/results/') && !it.contains('/obj/'))
		files.sort()
		for f in files {
			for h in scan(f) {
				println('${h.file}:${h.push}: ${h.array} << ${h.name}  (freed at ${h.free})')
			}
			for line in borrowed_pushes(f) {
				println(line)
			}
			for line in literal_pushes(f) {
				println(line)
			}
			for line in insert_and_literal_uses(f) {
				println(line)
			}
		}
	}
}

// Rule 2: an array whose elements the function frees one by one
// (`for x in arr { x.free() }`) must own every element, so a push of a bare
// name or field (`arr << s`, `arr << p.id`) is a borrowed string it will free.
fn owned_arrays(lines []string, r []int) []string {
	mut arrays := []string{}
	for i in r[0] .. r[1] {
		line := lines[i].all_before('//')
		if !line.contains('for ') || !line.contains(' in ') {
			continue
		}
		v := line.all_after('for ').all_before(' in ').trim_space().all_after_last(',').trim_space()
		arr := line.all_after(' in ').all_before('{').trim_space()
		if v == '' || arr == '' || arr.contains(' ') {
			continue
		}
		body := line.all_after('{') + (if i + 1 < r[1] { lines[i + 1] } else { '' })
		if body.contains('${v}.free()') {
			arrays << arr
		}
	}
	// `arr.free()` on a []string frees every element as well as the buffer.
	for i in r[0] .. r[1] {
		line := lines[i].all_before('//')
		if !line.contains(' := []string{') {
			continue
		}
		name := line.all_before(' := ').trim_space().all_after('mut ').trim_space()
		for j in r[0] .. r[1] {
			other := lines[j].all_before('//')
			if other.contains('${name}.free()') && !other.contains('.${name}.free()')
				&& !other.contains('&${name})') && name !in arrays {
				arrays << name
			}
		}
	}
	return arrays
}

fn borrowed_pushes(path string) []string {
	text := os.read_file(path) or { return [] }
	lines := text.split_into_lines()
	mut found := []string{}
	for r in functions(lines) {
		arrays := owned_arrays(lines, r)
		if arrays.len == 0 {
			continue
		}
		for i in r[0] .. r[1] {
			line := lines[i].all_before('//')
			for arr in arrays {
				marker := '${arr} << '
				if !line.contains(marker) {
					continue
				}
				value := line.all_after(marker).all_before('}').all_before(';').trim_space()
				if value == '' || value.contains('(') || value.contains('[') || value.contains("'")
					|| value.contains('+') {
					continue
				}
				found << '${path}:${i + 1}: ${arr} << ${value}  (elements freed in this function)'
			}
		}
	}
	return found
}

// Rule 3: a struct literal appended with a bare name as a field value
// (`arr << Item{name: s}`) shares `s`; freeing `s` later leaves the element
// pointing at freed bytes.
fn literal_pushes(path string) []string {
	text := os.read_file(path) or { return [] }
	lines := text.split_into_lines()
	mut found := []string{}
	for r in functions(lines) {
		for i in r[0] .. r[1] {
			line := lines[i].all_before('//')
			if !line.contains(' << ') {
				continue
			}
			value := line.all_after(' << ')
			if !value.contains('{') || !value.contains(':') {
				continue
			}
			for part in value.all_after('{').split(',') {
				if !part.contains(':') {
					continue
				}
				v := part.all_after(':').trim_space().trim_right('}').trim_space()
				if v == '' || !v.bytes().all(it.is_letter() || it.is_digit() || it == `_`)
					|| !(v[0].is_letter() || v[0] == `_`) || v in ['true', 'false', 'none'] {
					continue
				}
				for j in i + 1 .. r[1] {
					other := lines[j].all_before('//')
					if other.contains('${v}.free()') && !other.contains('.${v}.free()') {
						found << '${path}:${i + 1}: struct literal field ${v}  (freed at ${j + 1})'
						break
					}
				}
			}
		}
	}
	return found
}

// Rule 4: V1 also cloned a string passed to `arr.insert(i, s)` or written in
// an array literal (`[a, s]`); V copies only the header there too. A name
// used either way and freed later in the function is a candidate.
fn insert_and_literal_uses(path string) []string {
	text := os.read_file(path) or { return [] }
	lines := text.split_into_lines()
	mut found := []string{}
	for r in functions(lines) {
		for i in r[0] .. r[1] {
			line := lines[i].all_before('//')
			mut names := []string{}
			if line.contains('.insert(') {
				arg := line.all_after('.insert(').all_before(')').all_after(',').trim_space()
				names << arg
			}
			if line.contains(':= [') || line.contains('= [') {
				inner := line.all_after('[').all_before(']')
				if !inner.contains('(') && !inner.contains("'") {
					for part in inner.split(',') {
						names << part.trim_space()
					}
				}
			}
			for name in names {
				if name == '' || !name.bytes().all(it.is_letter() || it.is_digit() || it == `_`)
					|| !(name[0].is_letter() || name[0] == `_`) || name in ['true', 'false', 'none'] {
					continue
				}
				for j in i + 1 .. r[1] {
					other := lines[j].all_before('//')
					if other.contains('${name}.free()') && !other.contains('.${name}.free()') {
						found << '${path}:${i + 1}: ${name} inserted or in an array literal  (freed at ${j + 1})'
						break
					}
				}
			}
		}
	}
	return found
}
