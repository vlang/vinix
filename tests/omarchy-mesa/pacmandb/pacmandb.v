// SPDX-License-Identifier: GPL-2.0-or-later
// Read pacman sync databases and resolve a dependency closure the way pacman
// chooses packages: something already chosen that satisfies the dependency,
// then a package of that name, then a provider, each in repository order.
module pacmandb

import os

pub struct Package {
pub:
	repo     string
	name     string
	version  string
	filename string
	sha256   string
	csize    u64
	isize    u64
	depends  []string
	provides []string
}

pub struct Db {
pub mut:
	repos    []string
	packages map[string][]Package // by repository
}

// parse_desc reads one `desc` file of a sync database.
pub fn parse_desc(repo string, text string) !Package {
	mut fields := map[string][]string{}
	mut key := ''
	for line in text.split_into_lines() {
		if line.starts_with('%') && line.ends_with('%') && line.len > 2 {
			key = line[1..line.len - 1]
			fields[key] = []string{}
		} else if line != '' && key != '' {
			fields[key] << line
		}
	}
	for required in ['NAME', 'VERSION', 'FILENAME', 'SHA256SUM', 'CSIZE'] {
		if fields[required].len != 1 {
			return error('${repo}: desc without a single ${required}')
		}
	}
	return Package{
		repo:     repo
		name:     fields['NAME'][0]
		version:  fields['VERSION'][0]
		filename: fields['FILENAME'][0]
		sha256:   fields['SHA256SUM'][0]
		csize:    fields['CSIZE'][0].u64()
		isize:    if fields['ISIZE'].len == 1 { fields['ISIZE'][0].u64() } else { 0 }
		depends:  fields['DEPENDS'].clone()
		provides: fields['PROVIDES'].clone()
	}
}

// load reads an extracted database: one directory per package, each with
// `desc`. Older databases, Arch Linux ARM's among them, keep %DEPENDS% and
// %PROVIDES% in a separate `depends` file.
pub fn (mut db Db) load(repo string, dir string) ! {
	mut list := []Package{}
	for entry in os.ls(dir)!.sorted() {
		desc := os.join_path(dir, entry, 'desc')
		if !os.is_file(desc) {
			continue
		}
		mut text := os.read_file(desc)!
		depends := os.join_path(dir, entry, 'depends')
		if os.is_file(depends) {
			text += '\n' + os.read_file(depends)!
		}
		list << parse_desc(repo, text)!
	}
	if list.len == 0 {
		return error('${repo}: no packages in ${dir}')
	}
	db.repos << repo
	db.packages[repo] = list
}

pub struct Dep {
pub:
	name    string
	op      string
	version string
}

pub fn parse_dep(text string) Dep {
	for op in ['>=', '<=', '=', '<', '>'] {
		if index := text.index(op) {
			return Dep{text[..index], op, text[index + op.len..]}
		}
	}
	return Dep{text, '', ''}
}

fn satisfies_version(have string, dep Dep) bool {
	if dep.op == '' {
		return true
	}
	if have == '' {
		return false
	}
	c := vercmp(have, dep.version)
	return match dep.op {
		'=' { c == 0 }
		'>=' { c >= 0 }
		'<=' { c <= 0 }
		'>' { c > 0 }
		'<' { c < 0 }
		else { false }
	}
}

// satisfies follows alpm: the package's own name and version, then each
// provision; an unversioned provision satisfies only an unversioned dependency.
pub fn (p Package) satisfies(dep Dep) bool {
	if p.name == dep.name && satisfies_version(p.version, dep) {
		return true
	}
	for provision in p.provides {
		given := parse_dep(provision)
		if given.name == dep.name && satisfies_version(given.version, dep) {
			return true
		}
	}
	return false
}

pub fn (db &Db) find(dep Dep, chosen []Package) !Package {
	for p in chosen {
		if p.satisfies(dep) {
			return p
		}
	}
	for repo in db.repos {
		for p in db.packages[repo] {
			if p.name == dep.name && p.satisfies(dep) {
				return p
			}
		}
	}
	for repo in db.repos {
		for p in db.packages[repo] {
			if p.satisfies(dep) {
				return p
			}
		}
	}
	return error('nothing satisfies ${dep.name}${dep.op}${dep.version}')
}

// closure chooses the roots first, then their dependencies breadth first.
pub fn (db &Db) closure(roots []string) ![]Package {
	mut chosen := []Package{}
	mut queue := []string{}
	for root in roots {
		p := db.find(parse_dep(root), chosen)!
		if !chosen.any(it.name == p.name) {
			chosen << p
			queue << p.name
		}
	}
	mut index := 0
	for index < queue.len {
		name := queue[index]
		index++
		owner := chosen.filter(it.name == name)[0]
		for text in owner.depends {
			dep := parse_dep(text)
			p := db.find(dep, chosen) or { return error('${owner.name}: ${err.msg()}') }
			if !chosen.any(it.name == p.name) {
				chosen << p
				queue << p.name
			}
		}
	}
	return chosen
}

// rpmvercmp is libalpm's segment comparison.
pub fn rpmvercmp(a string, b string) int {
	if a == b {
		return 0
	}
	mut one := 0
	mut two := 0
	mut ptr1 := 0
	mut ptr2 := 0
	for one < a.len && two < b.len {
		for one < a.len && !a[one].is_alnum() {
			one++
		}
		for two < b.len && !b[two].is_alnum() {
			two++
		}
		if one >= a.len || two >= b.len {
			break
		}
		if one - ptr1 != two - ptr2 {
			return if one - ptr1 < two - ptr2 { -1 } else { 1 }
		}
		ptr1 = one
		ptr2 = two
		isnum := a[ptr1].is_digit()
		if isnum {
			for ptr1 < a.len && a[ptr1].is_digit() {
				ptr1++
			}
			for ptr2 < b.len && b[ptr2].is_digit() {
				ptr2++
			}
		} else {
			for ptr1 < a.len && a[ptr1].is_letter() {
				ptr1++
			}
			for ptr2 < b.len && b[ptr2].is_letter() {
				ptr2++
			}
		}
		if two == ptr2 {
			return if isnum { 1 } else { -1 }
		}
		mut s1 := a[one..ptr1]
		mut s2 := b[two..ptr2]
		if isnum {
			s1 = s1.trim_left('0')
			s2 = s2.trim_left('0')
			if s1.len != s2.len {
				return if s1.len > s2.len { 1 } else { -1 }
			}
		}
		if s1 != s2 {
			return if s1 < s2 { -1 } else { 1 }
		}
		one = ptr1
		two = ptr2
	}
	if one >= a.len && two >= b.len {
		return 0
	}
	if (one >= a.len && !b[two].is_letter()) || (one < a.len && a[one].is_letter()) {
		return -1
	}
	return 1
}

struct Evr {
	epoch   string
	version string
	release string
	has_rel bool
}

fn parse_evr(evr string) Evr {
	mut s := 0
	for s < evr.len && evr[s].is_digit() {
		s++
	}
	mut epoch := '0'
	mut rest := evr
	if s < evr.len && evr[s] == `:` {
		epoch = if s == 0 { '0' } else { evr[..s] }
		rest = evr[s + 1..]
	}
	if index := rest.last_index('-') {
		return Evr{epoch, rest[..index], rest[index + 1..], true}
	}
	return Evr{epoch, rest, '', false}
}

// vercmp is alpm_pkg_vercmp: epoch, then version, then release if both have one.
pub fn vercmp(a string, b string) int {
	if a == b {
		return 0
	}
	x := parse_evr(a)
	y := parse_evr(b)
	mut c := rpmvercmp(x.epoch, y.epoch)
	if c == 0 {
		c = rpmvercmp(x.version, y.version)
		if c == 0 && x.has_rel && y.has_rel {
			c = rpmvercmp(x.release, y.release)
		}
	}
	return c
}
