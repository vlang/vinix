// SPDX-License-Identifier: GPL-2.0-or-later
// Report framework methods that selected app classes call but the Vinix
// framework does not define, following superclasses and interfaces.
module main

import os

struct Class {
mut:
	super      string
	interfaces []string
	methods    map[string]bool
}

struct Resolver {
mut:
	roots []string
	cache map[string]?Class
}

fn parse_class(path string) !Class {
	mut c := Class{}
	for line in os.read_lines(path)! {
		if line.starts_with('.super ') {
			c.super = line[7..].trim_space()
		} else if line.starts_with('.implements ') {
			c.interfaces << line[12..].trim_space()
		} else if line.starts_with('.method ') {
			c.methods[line.all_after_last(' ')] = true
		}
	}
	return c
}

fn (mut r Resolver) class(name string) ?Class {
	if name in r.cache {
		return r.cache[name] or { return none }
	}
	if name == 'Ljava/lang/Object;' {
		mut methods := map[string]bool{}
		for m in ['<init>()V', 'equals(Ljava/lang/Object;)Z', 'hashCode()I', 'toString()Ljava/lang/String;',
			'getClass()Ljava/lang/Class;', 'notify()V', 'notifyAll()V', 'wait()V', 'wait(J)V',
			'wait(JI)V', 'clone()Ljava/lang/Object;', 'finalize()V'] {
			methods[m] = true
		}
		return Class{
			methods: methods
		}
	}
	relative := name.trim_left('L').trim_right(';') + '.smali'
	for root in r.roots {
		path := root + '/' + relative
		if os.is_file(path) {
			c := parse_class(path) or { break }
			r.cache[name] = c
			return c
		}
	}
	r.cache[name] = none
	return none
}

// Returns true when found, false when missing, none when the chain leaves
// the known smali (core Java classes or unscanned app classes).
fn (mut r Resolver) has(name string, method string, depth int) ?bool {
	if depth > 32 {
		return none
	}
	c := r.class(name) or { return none }
	if method in c.methods {
		return true
	}
	mut unknown := false
	if c.super != '' {
		if found := r.has(c.super, method, depth + 1) {
			if found {
				return true
			}
		} else {
			unknown = true
		}
	}
	for i in c.interfaces {
		if found := r.has(i, method, depth + 1) {
			if found {
				return true
			}
		} else {
			unknown = true
		}
	}
	if unknown {
		return none
	}
	return false
}

fn main() {
	if os.args.len < 4 {
		eprintln('usage: framework-api-gaps FRAMEWORK_SMALI APP_SMALI APP_CLASS_FILE...')
		exit(2)
	}
	mut r := Resolver{
		roots: [os.args[2], os.args[1]]
	}
	mut refs := map[string]bool{}
	for file in os.args[3..] {
		for line in os.read_lines(file)! {
			t := line.trim_space()
			if !t.starts_with('invoke-') {
				continue
			}
			target := t.all_after_last(', ')
			if target.contains(';->') {
				refs[target] = true
			}
		}
	}
	mut keys := refs.keys()
	keys.sort()
	for target in keys {
		owner := target.all_before(';->') + ';'
		method := target.all_after(';->')
		if found := r.has(owner, method, 0) {
			if !found {
				println('MISSING ${target}')
			}
		} else if owner.starts_with('Landroid/') {
			if r.class(owner) == none {
				println('MISSING-CLASS ${target}')
			}
		}
	}
}
