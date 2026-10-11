// SPDX-License-Identifier: GPL-2.0-or-later
module minecraftnative

import crypto.sha1
import os

pub struct Source {
pub:
	manifest  string = manifest_url
	maven     string = maven_url
	assets    string = assets_url
	fixture   bool
	responses map[string][]u8
}

pub struct Download {
pub:
	path string
	url  string
	sha1 string
}

pub fn digest(data []u8) string { return sha1.sum(data).hex() }

pub fn sha1_of(path string) !string {
	mut stream := os.open(path)!
	defer { stream.close() }
	if C.fcntl(stream.fd, C.F_SETFD, C.FD_CLOEXEC) != 0 {
		return error('Cannot protect digest descriptor')
	}
	mut hash := sha1.new()
	mut buffer := []u8{len: 1 << 20}
	defer { unsafe { buffer.free() } }
	for {
		command_checkpoint()!
		n := stream.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn (source Source) transfer(url string, path string, retries int) ! {
	if source.fixture {
		data := source.responses[url] or { return error('No fixture response for ' + url) }
		os.write_file_array(path, data)!
		return
	}
	mut last := 'None'
	for attempt in 0 .. retries {
		command_checkpoint()!
		command(['curl', '-fsSL', '--max-time', '120', '-A', 'vinix-minecraft-builder/1', '--output',
			path, '--', url], path + '.curl-' + attempt.str()) or {
			if interrupt_status() != 0 { return err }
			last = err.msg()
			continue
		}
		return
	}
	return error('failed to download ' + url + ': ' + last)
}

pub fn (source Source) fetch(url string) ![]u8 {
	if source.fixture {
		return source.responses[url] or { return error('No fixture response for ' + url) }
	}
	work := temporary(os.temp_dir(), 'vinix-minecraft-fetch-')!
	defer { retire(work) }
	source.transfer(url, work + '/payload', 4)!
	return os.read_bytes(work + '/payload')!
}

pub fn (source Source) download_to(url string, destination string, expected ?string) !bool {
	command_checkpoint()!
	if os.exists(destination) {
		if hash := expected {
			if sha1_of(destination)! == hash { return false }
		} else {
			return false
		}
	}
	// Parallel downloads can create the same parent concurrently.
	ensure_directory(os.dir(destination))!
	work := temporary(os.dir(destination), '.minecraft-download-')!
	defer { retire(work) }
	path := work + '/payload'
	source.transfer(url, path, 4)!
	if hash := expected {
		actual := sha1_of(path)!
		if actual != hash {
			return error('checksum mismatch for ' + url + ': expected ' + hash + ', got ' + actual)
		}
	}
	command_checkpoint()!
	os.mv(path, destination)!
	return true
}

struct TransferResult {
	count   int
	failure string
}

fn worker(source Source, entries []Download, root string) TransferResult {
	mut transferred := 0
	for entry in entries {
		path := safe_relative(entry.path) or { return TransferResult{transferred, err.msg()} }
		changed := source.download_to(entry.url, os.join_path(root, path), entry.sha1) or { return TransferResult{transferred, err.msg()} }
		if changed { transferred++ }
	}
	return TransferResult{transferred, ''}
}

pub fn (source Source) download_all(entries []Download, root string, label string, jobs int) ! {
	if jobs <= 0 || jobs > 64 { return error('jobs must be between 1 and 64') }
	println('  ' + label + ': ' + entries.len.str() + ' files')
	mut seen := map[string]bool{}
	mut groups := [][]Download{len: jobs}
	for i, entry in entries {
		safe_relative(entry.path)!
		if entry.path in seen { return error('Duplicate download destination: ' + entry.path) }
		seen[entry.path] = true
		groups[i % jobs] << entry
	}
	mut workers := []thread TransferResult{}
	for group in groups { workers << spawn worker(source, group, root) }
	mut count := 0
	mut failure := ''
	// Join every worker before propagating any error or interrupt.
	for result in workers.wait() {
		count += result.count
		if failure == '' { failure = result.failure }
	}
	if failure != '' { return error(failure) }
	println('  ' + label + ': ' + count.str() + ' downloaded, ' + (entries.len - count).str() + ' cached')
}
