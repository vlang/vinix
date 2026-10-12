// SPDX-License-Identifier: GPL-2.0-or-later
module validationhost

import androidhost as ah
import boothost
import cachecli
import gamehost
import hosttest
import os
import plist

#include <stdlib.h>

fn C.mkdtemp(&char) &char

pub struct DownloadPin {
pub:
	name       string
	url        string
	hash       string
	size       u64
	user_agent string = 'Vinix-PSP-test'
	timeout    int    = 60
}

fn private_directory(base string) !string {
	mut pattern := (base.trim_right('/') + '/.vinix-download.XXXXXX\x00').bytes()
	if C.mkdtemp(pattern.data) == unsafe { nil } { return os.error_posix() }
	return pattern.bytestr().all_before('\x00')
}

pub fn valid_file(path string, pin DownloadPin) bool {
	if !os.is_file(path) || os.file_size(path) != pin.size { return false }
	hash := gamehost.digest(path) or { return false }
	return hash == pin.hash
}

pub fn pinned_download(tools gamehost.Tools, output string, pin DownloadPin, repair bool) !string {
	target := output + '/' + pin.name
	if os.exists(target) {
		if valid_file(target, pin) { return target }
		if !repair { return error('cached package checksum mismatch: ' + target) }
	}
	gamehost.mkdir(output)!
	directory := private_directory(output)!
	defer { gamehost.remove(directory) or {} }
	temporary := directory + '/' + pin.name
	tools.run(['curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout',
		pin.timeout.str(), '--speed-limit', '1', '--speed-time', pin.timeout.str(), '--max-filesize',
		pin.size.str(), '--user-agent', pin.user_agent, '--output', temporary, pin.url])!
	if !valid_file(temporary, pin) {
		return error('downloaded package does not match its pinned size/hash: ' + pin.name)
	}
	if C.rename(temporary.str, target.str) != 0 { return os.error_posix() }
	return target
}

fn safe_member(name string) !string {
	if name.starts_with('/') || name.contains('\\') || '..' in name.split('/') {
		return error('unsupported package member: ' + name)
	}
	return name.split('/').filter(it !in ['', '.']).join('/')
}

fn no_links(path string) ! {
	mut current := path
	for {
		if os.is_link(current) { return error('symlink in extraction destination: ' + path) }
		previous := gamehost.parent(current)
		if previous == current || current == '.' { break }
		current = previous
	}
}

pub fn extract_zip(archive ah.Archive, output string, limit u64, member_limit u64, count int, expanded u64, expected []string) ! {
	entries := archive.entries()
	mut seen := map[string]bool{}
	mut total := u64(0)
	if (count >= 0 && entries.len != count) || (count < 0 && entries.len > 10000) {
		return error('unexpected package entry count')
	}
	for entry in entries {
		if entry.name in seen { return error('duplicate package path: ' + entry.name) }
		seen[entry.name] = true
		if entry.size > member_limit || entry.size > limit - total {
			return error('package contents exceed limit')
		}
		total += entry.size
		name := safe_member(entry.name)!
		if entry.mode & 0o170000 !in [u32(0), 0o040000, 0o100000] {
			return error('unsupported package member mode: ' + entry.name)
		}
		no_links(output + '/' + name)!
	}
	if expanded != 0 && total != expanded { return error('unexpected package expanded size') }
	if expected.len > 0 && (expected.len != seen.len || expected.any(it !in seen)) {
		return error('unexpected package archive contents')
	}
	// Validate all paths before mutating the output, as the original ZipFile
	// consumer did. Existing ordinary files and directories may be refreshed.
	for entry in entries {
		name := safe_member(entry.name)!
		destination := output + '/' + name
		if entry.name.ends_with('/') {
			gamehost.mkdir(destination)!
			continue
		}
		gamehost.mkdir(gamehost.parent(destination))!
		os.write_file_array(destination, archive.read(entry.name)!)!
	}
}

pub fn verify_pbp(path string, image bool) ! {
	mut file := os.open(path)!
	defer { file.close() }
	header := file.read_bytes(40)
	if header.len < 4 || header[..4] != [u8(0), `P`, `B`, `P`] {
		return error('unexpected PSP PBP header')
	}
	if image {
		if header.len < 40 || header[..8] != [u8(0), `P`, `B`, `P`, 1, 0, 1, 0] {
			return error('unexpected PSP demo PBP header')
		}
		offset := u32(header[36]) | (u32(header[37]) << 8) | (u32(header[38]) << 16) | (u32(header[39]) << 24)
		if file.read_bytes_at(8, u64(offset)).bytestr() != 'NPUMDIMG' {
			return error('PSP demo is missing its original NPUMDIMG data')
		}
	}
}

pub fn fetch_psp(tools gamehost.Tools, output string, kind string) !string {
	if kind == 'cube' {
		pin := DownloadPin{ name: output.all_after_last('/'), url: 'https://raw.githubusercontent.com/hrydgard/pspautotests/f93c29855718a587360976e793f5b41a88ef7e68/demos/cube.pbp', hash: '4018ec0da8a88a1600380661bcd4461c09c4c69bc45139ec626a754f0eec3fc0', size: 50600, user_agent: 'Vinix-iOS-probe', timeout: 30 }
		binary := pinned_download(tools, gamehost.parent(output), pin, true)!
		verify_pbp(binary, false)!
		println('Verified upstream PSP cube: ${binary} (${pin.hash})')
		return binary
	}
	pin := match kind {
		'ppsspp' {
			DownloadPin{ name: 'PPSSPP-iOS-v1.20.4.ipa', url: 'https://github.com/hrydgard/ppsspp/releases/download/v1.20.4/PPSSPP-iOS-v1.20.4.ipa', hash: '822c7042311ff47710c9148c8edb5aab649cf85ce6ba96b9e8190feb91f45a51', size: 31124277, user_agent: 'Vinix-iOS-probe' }
		}
		'gow' {
			DownloadPin{ name: 'demo.zip', url: 'https://data.playdreamcreate.com/god-of-war-chains-of-olympus_US.zip', hash: '6c1e4cffecf389e5dbcc995564e3d311afcfd9beaa493e6feace642aa57785ea', size: 169451774 }
		}
		'nzp' {
			DownloadPin{ name: 'nzportable-psp.zip', url: 'https://github.com/nzp-team/nzportable/releases/download/nightly/nzportable-psp.zip', hash: '2983183a7d7d6471e8ebf2c5c95290ddd558a1c44d46b9ba6a68e9987f02e89f', size: 64412845 }
		}
		else { return error('unknown PSP download: ' + kind) }
	}
	package := pinned_download(tools, output, pin, false)!
	archive := ah.open_archive(package)!
	unpacked := output + '/unpacked'
	if kind == 'gow' {
		member := 'PSP/GAME/UCUS98713/EBOOT.PBP'
		extract_zip(archive, unpacked, 169451184, 169451184, 4, 169451184, ['PSP/', 'PSP/GAME/',
			'PSP/GAME/UCUS98713/', member])!
		binary := unpacked + '/' + member
		if !valid_file(binary, DownloadPin{ size: 169451184, hash: '7d147100be1127d87351042a22526cc64c3229e9b0a9fb984bcd5e0aa20a1523' }) {
			return error('unpacked PSP executable does not match the pinned demo')
		}
		verify_pbp(binary, true)!
		println('Verified God of War PSP demo UCUS98713: ${package} (${pin.hash})\nUnmodified PSP executable: ${binary} (7d147100be1127d87351042a22526cc64c3229e9b0a9fb984bcd5e0aa20a1523)')
		return gamehost.parent(binary)
	}
	if kind == 'nzp' {
		extract_zip(archive, unpacked, 98449920, 98449920, 1310, 98449920, [])!
		game := unpacked + '/nzportable'
		binary := game + '/EBOOT.PBP'
		if !valid_file(binary, DownloadPin{ size: 1539962, hash: '4b916c0b1d9f1607604623240b31c7291fcb9ec1585836d0a2eb3fcbd0e16d57' }) || boothost.unicode_strip(os.read_file(game + '/nzp/version.txt')!) != '2.0.0-indev+20260924124055' {
			return error('unpacked PSP game does not match the pinned build')
		}
		println('Verified NZ:P 2.0.0-indev+20260924124055: ${package} (${pin.hash})\nUnmodified PSP executable: ${binary} (4b916c0b1d9f1607604623240b31c7291fcb9ec1585836d0a2eb3fcbd0e16d57)')
		return game
	}
	extract_zip(archive, unpacked, 1024 * 1024 * 1024, 512 * 1024 * 1024, -1, 0, [])!
	bundle := unpacked + '/Payload/PPSSPP.app'
	info := plist.parse(os.read_bytes(bundle + '/Info.plist')!)!.fields
	if info['CFBundleIdentifier'].text != 'org.ppsspp.ppsspp' || info['CFBundleExecutable'].text != 'PPSSPP' || info['CFBundleShortVersionString'].text != '1.20.4' || gamehost.digest(bundle + '/PPSSPP')! != '7c9456c3cdee44dc48eefde5454bffa7e0965a32aa32858a181a06fbffeacf6c' {
		return error('unpacked app does not match the pinned iOS binary')
	}
	println('Verified PPSSPP 1.20.4 iOS IPA: ${package}\nUnmodified upstream executable: ${bundle}/PPSSPP')
	return bundle
}

pub fn download_cli(root string, kind string, argv []string) !int {
	args := cachecli.arguments(argv, ['--output'], [], [], 0, 0, 'Fetch the unchanged pinned PSP test package.\nUsage: download [--output PATH]') or { return error_with_code(err.msg(), 2) }
	default_path := match kind {
		'ppsspp' { 'ppsspp' }
		'cube' { 'ppsspp/cube.pbp' }
		'gow' { 'god-of-war' }
		else { 'nzportable' }
	}
	output := hosttest.module_resolve(args.value('--output', root + '/build/ios/' + default_path))!
	fetch_psp(gamehost.Tools{ root: root }, output, kind)!
	return 0
}
