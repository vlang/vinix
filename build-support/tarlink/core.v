// SPDX-License-Identifier: GPL-2.0-only
module tarlink

import os
import tarcore
import tarstream

#include <stdio.h>

fn C.rename(&char, &char) int
fn C.snprintf(&char, usize, &char, ...int) int

const prefixes = ['./usr/lib/', './usr/share/', 'usr/lib/', 'usr/share/']

pub fn plan(path string) !map[string]string {
	mut archive := tarstream.open(path)!
	defer { archive.close() }
	mut names := map[string]bool{}
	mut first := map[string]string{}
	mut links := map[string]string{}
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name in names {
			return error('error: ${member.name} appears twice; not linking anything')
		}
		names[member.name] = true
		if !member.regular() || member.size < 4096 || !prefixes.any(member.name.starts_with(it)) {
			continue
		}
		key := '${archive.digest()!}\x00${member.size}\x00${member.mode}\x00${member.uid}\x00${member.gid}'
		if target := first[key] {
			if target.runes().len <= 100 { links[member.name] = target }
		} else {
			first[key] = member.name
		}
	}
	return links
}

pub fn rewrite(src string, dst string, links map[string]string) !i64 {
	mut archive := tarstream.open(src)!
	defer { archive.close() }
	mut out := tarcore.create(dst)!
	defer { out.close() }
	mut saved := i64(0)
	for {
		mut member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if target := links[member.name] {
			saved += member.size
			member.kind = `1`
			member.linkname = target
			member.size = 0
			out.write(tarcore.header(member)!)!
		} else {
			out.write(tarcore.header(member)!)!
			if member.regular() {
				archive.copy_to(mut out)!
				out.padding(member.size)!
			}
		}
	}
	out.finish()!
	return saved
}

struct Content {
	kind  u8
	value string
}

fn contents(path string) !map[string]Content {
	mut archive := tarstream.open(path)!
	defer { archive.close() }
	mut result := map[string]Content{}
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		result[member.name] = if member.regular() {
			Content{`0`, archive.digest()!}
		} else {
			Content{member.kind, member.linkname}
		}
	}
	return result
}

pub fn check(src string, dst string) ! {
	expected := contents(src)!
	mut archive := tarstream.open(dst)!
	defer { archive.close() }
	mut got := map[string]Content{}
	mut content := map[string]string{}
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.regular() {
			content[member.name] = archive.digest()!
			got[member.name] = Content{`0`, content[member.name]}
		} else if member.kind == `1` && expected[member.name].kind == `0` {
			if member.linkname !in content {
				return error('error: ${member.name} links to ${member.linkname}, which comes later')
			}
			got[member.name] = Content{`0`, content[member.linkname]}
		} else {
			got[member.name] = Content{member.kind, member.linkname}
		}
	}
	if got != expected {
		mut missing := expected.keys().filter(it !in got)
		missing << got.keys().filter(it !in expected)
		missing.sort()
		mut changed := expected.keys().filter(it in got && got[it] != expected[it])
		changed.sort()
		return error('error: output differs from input (names ${missing[..int_min(5, missing.len)]}, content ${changed[..int_min(5, changed.len)]})')
	}
}

pub struct Stats {
pub:
	linked int
	saved  i64
}

fn publish(src string, temp string, dst string, links map[string]string) !Stats {
	saved := rewrite(src, temp, links)!
	check(src, temp)!
	// os.rename treats a directory destination as a request to move inside it.
	// Publication must instead use POSIX rename's exact destination semantics.
	if C.rename(temp.str, dst.str) != 0 { return error('cannot replace output archive: ${dst}') }
	return Stats{links.len, saved}
}

pub fn transform(src string, dst string) !Stats {
	links := plan(src)! // Duplicate names fail before touching the destination.
	temp := dst + '.tmp'
	result := publish(src, temp, dst, links) or {
		if os.exists(temp) { os.rm(temp)! }
		return err
	}
	return result
}

pub fn run(args []string) int {
	if args.len != 2 {
		eprintln('Usage: link-duplicate-files IN.tar OUT.tar')
		return 1
	}
	stats := transform(args[0], args[1]) or {
		eprintln(err)
		return 1
	}
	println('linked ${stats.linked} repeated files, ${megabytes(stats.saved)} MB stored once')
	return 0
}

fn megabytes(saved i64) string {
	// Preserve decimal rounding of the original binary float, without V's
	// interpolation formatter rounding halfway values upward first.
	mut buffer := [64]u8{}
	count := unsafe { C.snprintf(&char(&buffer[0]), usize(buffer.len), c'%.1f', f64(saved) / 1e6) }
	return buffer[..count].bytestr()
}
