// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

#include <signal.h>
#include <unistd.h>
fn C.getpgid(int) int
fn C.kill(int, int) int

fn build_scope(process_root string, cwd string, root string, source string) bool {
	return root.starts_with('/var/tmp/vinix-art-alpine-') && source.starts_with('/work/art-build-')
		&& !source.contains('/../') && process_root == root && cwd == root + source
}

fn process_start(stat string) ?string {
	end := stat.last_index(')') or { return none }
	fields := stat[end + 1..].fields()
	if fields.len < 20 { return none }
	return fields[19]
}

// Called outside the chroot after a host guard failure. Workers and their
// process-group leader must have this builder root and exact build cwd.
fn stop_build(root_arg string, source string) ! {
	root := os.real_path(root_arg)
	if !os.is_dir('/proc') || !build_scope(root, root + source, root, source)
		|| !os.is_file(root + '/etc/alpine-release') { return error('isolated builder scope required') }
	mut groups := map[int]bool{}
	entries := os.ls('/proc')!
	for entry in entries {
		if entry == '' || !entry.bytes().all(it.is_digit()) { continue }
		pid := entry.int()
		if pid <= 1 { continue }
		base := '/proc/' + entry
		comm := os.read_file(base + '/comm') or { continue }
		if comm.trim_space() !in ['make', 'cc1', 'cc1plus', 'gcc', 'g++', 'as', 'ld',
			'collect2', 'sh', 'sleep', 'vinix-art-sourc', 'vinix-art-mterp'] { continue }
		before := os.read_file(base + '/stat') or { continue }
		started := process_start(before) or { continue }
		if !build_scope(os.real_path(base + '/root'), os.real_path(base + '/cwd'), root, source) { continue }
		end := before.last_index(')') or { continue }
		fields := before[end + 1..].fields()
		group := fields[2].int()
		if group <= 1 || group in groups || C.getpgid(group) != group { continue }
		leader := '/proc/' + group.str()
		if !build_scope(os.real_path(leader + '/root'), os.real_path(leader + '/cwd'), root, source) { continue }
		after := os.read_file(base + '/stat') or { continue }
		if process_start(after) or { continue } != started || C.getpgid(pid) != group { continue }
		if C.kill(-group, C.SIGKILL) != 0 { return error('failed to stop owned compiler group') }
		groups[group] = true
	}
	println('ART-BUILDER-STOP groups=${groups.len}')
}

struct Response {
mut:
	status int
	length i64 = -1
	etag string
	range string
}

fn response(headers string) Response {
	mut result := Response{}
	lines := headers.split_into_lines()
	for raw in lines {
		line := raw.trim_space()
		if line.starts_with('HTTP/') {
			fields := line.fields()
			result = Response{status: if fields.len > 1 { fields[1].int() } else { 0 }}
		} else if line.to_lower().starts_with('content-length:') {
			result.length = line.all_after(':').trim_space().i64()
		} else if line.to_lower().starts_with('etag:') {
			result.etag = line.all_after(':').trim_space()
		} else if line.to_lower().starts_with('content-range:') {
			result.range = line.all_after(':').trim_space()
		}
	}
	return result
}

fn curl_args(direct bool) []string {
	mut args := ['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
		'--connect-timeout', '10', '--max-time', '120']
	if direct { args << ['--noproxy', 'dl-cdn.alpinelinux.org'] }
	return args
}

fn download(url string, target string, direct bool) ! {
	mut head := curl_args(direct)
	head << ['--head', url]
	metadata := os.exec(head)
	if metadata.exit_code != 0 { return error('package metadata fetch failed') }
	info := response(metadata.output)
	if info.status != 200 || info.length <= 0 || info.length > 256 * 1024 * 1024 {
		return error('bounded package Content-Length required')
	}
	if info.length <= 4 * 1024 * 1024 || info.etag == '' || info.etag.starts_with('W/') {
		mut args := curl_args(direct)
		args << ['--output', target, url]
		if os.system_args(args) != 0 || os.file_size(target) != u64(info.length) {
			return error('package download or length check failed')
		}
		return
	}
	// Large public APKs use bounded parallel ranges, bound to one strong ETag.
	// No partial file is eligible for the cache or the final manifest.
	parts := target + '.parts'
	os.mkdir(parts)!
	mut command := ['/usr/bin/curl', '--parallel', '--parallel-max', '6']
	mut count := 0
	for start := i64(0); start < info.length; start += 4 * 1024 * 1024 {
		end := if start + 4 * 1024 * 1024 < info.length { start + 4 * 1024 * 1024 - 1 } else { info.length - 1 }
		if count > 0 { command << '--next' }
		command << curl_args(direct)[1..]
		command << ['--header', 'If-Match: ' + info.etag, '--range', '${start}-${end}',
			'--dump-header', parts + '/${count}.headers', '--output', parts + '/${count}.data', url]
		count++
	}
	if os.system_args(command) != 0 { return error('parallel package transfer failed') }
	for i in 0 .. count {
		start := i64(i) * 4 * 1024 * 1024
		end := if start + 4 * 1024 * 1024 < info.length { start + 4 * 1024 * 1024 - 1 } else { info.length - 1 }
		actual := response(os.read_file(parts + '/${i}.headers')!)
		if actual.status != 206 || actual.etag != info.etag
			|| actual.range != 'bytes ${start}-${end}/${info.length}'
			|| os.file_size(parts + '/${i}.data') != u64(end - start + 1) {
			return error('package range response differs')
		}
	}
	mut file := os.create(target)!
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for i in 0 .. count {
		mut part := os.open(parts + '/${i}.data')!
		for {
			n := part.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if file.write(buffer[..n])! != n { return error('short assembled package write') }
		}
		part.close()
	}
	file.close()
	if os.file_size(target) != u64(info.length) { return error('assembled package length differs') }
	// Successful transport scratch is disposable; failed transfer evidence stays.
	os.rmdir_all(parts)!
}

fn package_name(url string) !string {
	if !url.starts_with('https://dl-cdn.alpinelinux.org/alpine/')
		|| !url.contains('/aarch64/') || !url.ends_with('.apk')
		|| url.contains_any('?#\\\r\n\t ') || url.contains('/../') {
		return error('expected official ARM64 Alpine package URL')
	}
	name := url.all_after_last('/')
	if name.len < 5 || !name.bytes().all(it.is_alnum() || it in [`-`, `_`, `.`, `+`, `~`]) {
		return error('invalid package filename')
	}
	return name
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn cached_file(caches string, name string, url string) !string {
	roots := caches.split(':')
	for root in roots {
		path := root + '/' + name
		if !os.is_file(path) || os.is_link(path) { continue }
		manifest := root + '/packages.json'
		if os.exists(manifest) {
			if os.file_size(manifest) > 1024 * 1024 || os.is_link(manifest) { return error('invalid retained package manifest') }
			records := json2.decode[[]map[string]string](os.read_file(manifest)!)!
			mut matched := false
			for record in records {
				if record['name'] == name {
					if matched || record['url'] != url || record['sha256'] != hash(path)! {
						return error('retained package differs from its completed record')
					}
					matched = true
				}
			}
			if !matched { continue }
		}
		return os.real_path(path)
	}
	return ''
}

fn fetch(list string, cache string, output string, direct bool) ! {
	lines := os.read_file(list)!.split_into_lines()
	if lines.len == 0 || lines.len > 512 { return error('bounded nonempty package list required') }
	mut names := map[string]string{}
	for line in lines {
		name := package_name(line)!
		if name in names { return error('duplicate package filename') }
		names[name] = line
	}
	os.mkdir(output)!
	mut records := []map[string]string{}
	for line in lines {
		name := package_name(line)!
		target := output + '/' + name
		cached := cached_file(cache, name, line)!
		mut origin := line
		if cached != '' {
			before := hash(cached)!
			os.cp(cached, target)!
			if hash(target)! != before || hash(cached)! != before { return error('cached package changed during copy') }
			origin = os.real_path(cached)
		} else { download(line, target, direct)! }
		records << {'name': name, 'url': line, 'origin': origin, 'sha256': hash(target)!,
			'route': if origin != line { 'cache' } else if direct { 'direct' } else { 'environment' }}
		os.write_file(output + '/packages.json', json2.encode(records, prettify: true) + '\n')!
		println('ART-BUILDER-PACKAGE ' + name)
	}
	println('ART-BUILDER-FETCH-PASS packages=' + records.len.str() + '; APK signature verification remains required at install')
}

fn install_args(list string, cache string) ![]string {
	if cache.contains(':') || !os.is_file(cache + '/packages.json')
		|| os.file_size(list) > 1024 * 1024 {
		return error('one completed package cache and bounded plan required')
	}
	lines := os.read_file(list)!.split_into_lines()
	if lines.len == 0 || lines.len > 512 { return error('bounded nonempty install plan required') }
	mut seen := map[string]bool{}
	mut args := ['/sbin/apk', 'add', '--no-network']
	for url in lines {
		name := package_name(url)!
		if name in seen || name.starts_with('python') || name.starts_with('pypy') {
			return error('duplicate or unsupported interpreter package in build plan')
		}
		seen[name] = true
		path := cached_file(cache, name, url)!
		if path == '' { return error('install package lacks a completed cache record: ' + name) }
		args << path
	}
	return args
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--stop-build' {
		stop_build(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == '--apk-install' {
		if !os.is_file('/etc/alpine-release') || !os.is_file('/sbin/apk') {
			eprintln('install mode requires the isolated ARM64 Alpine builder'); exit(1)
		}
		uname := os.find_abs_path_of_executable('uname') or { eprintln(err); exit(1) }
		platform := os.exec([uname, '-sm'])
		if platform.exit_code != 0 || platform.output.trim_space() != 'Linux aarch64' {
			eprintln('install mode requires native ARM64 Linux'); exit(1)
		}
		args := install_args(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		// APK still authenticates every archive against the builder's trusted keys.
		// The plan is resolved separately by APK; no network fallback is allowed.
		exit(os.system_args(args))
	}
	if os.args.len == 3 && os.args[1] == '--self-test' {
		parsed := response('HTTP/1.1 200 Connection established\r\nContent-Length: 0\r\n\r\nHTTP/2 206\r\nContent-Length: 20\r\nETag: "abc"\r\nContent-Range: bytes 0-19/40\r\n\r\n')
		assert parsed.status == 206 && parsed.length == 20 && parsed.etag == '"abc"' && parsed.range == 'bytes 0-19/40'
		assert package_name('https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/g++-15.2.0-r9.apk')! == 'g++-15.2.0-r9.apk'
		for bad in ['http://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/x.apk',
			'https://example.com/alpine/aarch64/x.apk',
			'https://dl-cdn.alpinelinux.org/alpine/aarch64/../x.apk',
			'https://dl-cdn.alpinelinux.org/alpine/aarch64/x.apk?x=1',
			'https://dl-cdn.alpinelinux.org/alpine/aarch64/x.apk\n'] {
			if _ := package_name(bad) { panic('invalid package URL accepted') }
		}
		root := os.abs_path(os.args[2])
		os.mkdir(root)!
		assert build_scope('/var/tmp/vinix-art-alpine-test', '/var/tmp/vinix-art-alpine-test/work/art-build-test',
			'/var/tmp/vinix-art-alpine-test', '/work/art-build-test')
		assert !build_scope('/', '/work/art-build-test', '/var/tmp/vinix-art-alpine-test', '/work/art-build-test')
		assert !build_scope('/var/tmp/vinix-art-alpine-test', '/unrelated', '/var/tmp/vinix-art-alpine-test', '/work/art-build-test')
		assert !build_scope('/', '/work/art-build-test', '/', '/work/art-build-test')
		os.write_file(root + '/Makefile', '.PHONY: showcommands\nshowcommands:\n' +
			'out/host/linux-x86/control-wait:\n\t/bin/sleep 60\n')!
		url := 'https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/test-1.apk'
		os.write_file(root + '/test-1.apk', 'complete test bytes')!
		os.write_file(root + '/partial-1.apk', 'incomplete bytes')!
		os.write_file(root + '/packages.json', json2.encode([{'name': 'test-1.apk', 'url': url,
			'sha256': hash(root + '/test-1.apk')!}]))!
		assert cached_file(root, 'test-1.apk', url)! == root + '/test-1.apk'
		assert cached_file(root, 'partial-1.apk', url)! == ''
		plan := root + '/plan.urls'
		os.write_file(plan, url + '\n')!
		assert install_args(plan, root)! == ['/sbin/apk', 'add', '--no-network', root + '/test-1.apk']
		for invalid in ['', url + '\n' + url,
			'https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/partial-1.apk',
			'https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/python3-1.apk'] {
			os.write_file(plan, invalid)!
			if _ := install_args(plan, root) { panic('invalid native install plan accepted') }
		}
		os.write_file(plan, url + '\n')!
		os.write_file(root + '/test-1.apk', 'tampered bytes')!
		if _ := cached_file(root, 'test-1.apk', url) { panic('tampered completed package accepted') }
		if _ := install_args(plan, root) { panic('tampered install input accepted') }
		println('ART-BUILDER-FETCH-URL-PASS')
		return
	}
	direct := os.args.len == 5 && os.args[1] == '--direct'
	args := if direct { os.args[2..] } else { os.args[1..] }
	if args.len != 3 { eprintln('usage: art-builder-fetch [--direct] URL_LIST CACHE[:CACHE...] FRESH_OUTPUT | --self-test FRESH_OUTPUT | --apk-install URL_LIST CACHE'); exit(2) }
	fetch(args[0], args[1], args[2], direct) or { eprintln(err); exit(1) }
}
