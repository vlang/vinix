import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix/build/str-x86-20261022-2/packages-https-runtime/rootfs'
const base = '/Users/alex/code/vinix/build-amd64-desktop/initramfs-root/lib/ld-musl-x86_64.so.1'

fn command(args string) string {
	r := os.execute(args)
	assert r.exit_code == 0, r.output
	return r.output
}

fn versions(path string) string {
	return command('/usr/bin/strings ' + os.quoted_path(path)).split_into_lines().filter(it.starts_with('1.2.') || it.contains('musl libc')).join('; ')
}

fn main() {
	mut pending := [root + '/usr/bin/curl', root + '/lib/ld-musl-x86_64.so.1']
	mut seen := map[string]bool{}
	mut symbols := map[string]bool{}
	mut undefined := map[string][]string{}
	mut rows := []string{}
	for pending.len > 0 {
		path := pending[0]
		pending.delete(0)
		if seen[path] { continue }
		seen[path] = true
		kind := command('/usr/bin/file ' + os.quoted_path(path))
		assert kind.contains('x86-64'), kind
		data := os.read_bytes(path) or { panic(err) }
		mut needed := []string{}
		for line in command('/opt/homebrew/bin/x86_64-linux-musl-readelf -d ' + os.quoted_path(path)).split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			mut dep := ''
			for dir in ['/lib/', '/usr/lib/'] {
				candidate := root + dir + name
				if os.exists(candidate) { dep = candidate; break }
			}
			assert dep != '', 'Missing ${name} required by ${path}'
			needed << name
			pending << dep
		}
		for line in command('/opt/homebrew/bin/x86_64-linux-musl-readelf --dyn-syms --wide ' + os.quoted_path(path)).split_into_lines() {
			fields := line.fields()
			if fields.len < 8 || !fields[0].ends_with(':') { continue }
			if fields[4] !in ['GLOBAL', 'WEAK'] { continue }
			name := fields[7].all_before('@')
			if fields[6] == 'UND' {
				if fields[4] == 'GLOBAL' { undefined[name] << path }
			} else {
				symbols[name] = true
			}
		}
		rows << '${sha256.sum(data).hex()} ${path} needed=${needed.join(",")}'
	}
	mut missing := []string{}
	for name, owners in undefined {
		if !symbols[name] { missing << '${name}: ${owners.join(",")}' }
	}
	missing.sort()
	rows.sort()
	println('Independent read-only x86 curl closure review')
	println('Base musl: ${versions(base)}; sha256=${sha256.sum(os.read_bytes(base) or { panic(err) }).hex()}')
	println('Closure musl: ${versions(root + "/lib/ld-musl-x86_64.so.1")}')
	for row in rows { println(row) }
	println('Unresolved strong dynamic symbols: ${missing.len}')
	for row in missing { println(row) }
	assert missing.len == 0
	println('PASS recursive DT_NEEDED closure, x86-64 ELF, all strong dynamic symbols resolved (${seen.len} files). Guest execution remains unqualified.')
}
