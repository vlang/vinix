// SPDX-License-Identifier: MIT
module vmhost

import androidhost as ah
import crypto.md5
import encoding.utf8
import gamehost
import hosttest
import json2
import os

pub const roblox_packages = {
	'RobloxApp.zip':                     ''
	'WebView2.zip':                      ''
	'shaders.zip':                       'shaders'
	'ssl.zip':                           'ssl'
	'content-avatar.zip':                'content/avatar'
	'content-configs.zip':               'content/configs'
	'content-fonts.zip':                 'content/fonts'
	'content-models.zip':                'content/models'
	'content-sky.zip':                   'content/sky'
	'content-sounds.zip':                'content/sounds'
	'content-textures2.zip':             'content/textures'
	'content-textures3.zip':             'PlatformContent/pc/textures'
	'content-terrain.zip':               'PlatformContent/pc/terrain'
	'content-platform-fonts.zip':        'PlatformContent/pc/fonts'
	'content-platform-dictionaries.zip': 'PlatformContent/pc/shared_compression_dictionaries'
	'extracontent-places.zip':           'ExtraContent/places'
	'extracontent-luapackages.zip':      'ExtraContent/LuaPackages'
	'extracontent-translations.zip':     'ExtraContent/translations'
	'extracontent-models.zip':           'ExtraContent/models'
	'extracontent-textures.zip':         'ExtraContent/textures'
}
pub const roblox_settings = '<?xml version="1.0" encoding="UTF-8"?>\n<Settings>\n\t<ContentFolder>content</ContentFolder>\n\t<BaseUrl>http://www.roblox.com</BaseUrl>\n</Settings>\n'
pub const roblox_skipped = ['WebView2RuntimeInstaller.zip', 'RobloxPlayerInstaller.exe']
pub const roblox_unused = ['root/.wine-word2013-x86_64', 'root/.wine-office2010-x86_64',
	'root/word2013-media', 'root/office2010-media', 'root/.wine-x86_32', 'usr/libexec/vinix-i386']

pub fn roblox_md5(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := md5.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

pub fn roblox_download(tools gamehost.Tools, url string, target string) ! {
	partial := target + '.partial'
	// Keep the interrupted partial and publish only a successful response.
	tools.run(['curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout',
		'120', '--speed-limit', '1', '--speed-time', '120', '--output', partial, url])!
	if C.rename(partial.str, target.str) != 0 { return os.error_posix() }
}

pub fn roblox_version_valid(version string) bool {
	if !version.starts_with('version-') || version.len == 8 { return false }
	hosttest.module_decode_utf8(version) or { return false }
	return version[8..].runes().all(utf8.is_letter(it) || utf8.is_number(it))
}

pub struct RobloxDeployment {
pub:
	version   string
	downloads string
}

pub fn roblox_fetch(tools gamehost.Tools, work string, requested string) !RobloxDeployment {
	mut version := requested
	if version == '' {
		response := tools.output(['curl', '--fail', '--location', '--silent', '--show-error',
			'--connect-timeout', '60', '--speed-limit', '1', '--speed-time', '60',
			'https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer'])!
		version = json2.decode[map[string]json2.Any](response)!['clientVersionUpload']!.str()
	}
	if !roblox_version_valid(version) { return error('Not a Roblox deployment name: ' + version) }
	downloads := work + '/downloads/' + version
	gamehost.mkdir(downloads)!
	manifest := downloads + '/rbxPkgManifest.txt'
	if !os.exists(manifest) {
		roblox_download(tools, 'https://setup.rbxcdn.com/' + version + '-rbxPkgManifest.txt', manifest)!
	}
	text := os.read_file(manifest)!
	hosttest.module_decode_utf8(text)!
	lines := roblox_fields(text)
	if lines.len == 0 || lines[0] != 'v0' || (lines.len - 1) % 4 != 0 {
		return error('Unknown package manifest format in ' + manifest)
	}
	for index := 1; index < lines.len; index += 4 {
		name := lines[index]
		if name in roblox_skipped { continue }
		if name !in roblox_packages {
			return error('Deployment ' + version + ' has a package this test cannot place: ' + name)
		}
		package := downloads + '/' + name
		if !os.exists(package) {
			println('Downloading ' + name)
			flush_stdout()
			roblox_download(tools, 'https://setup.rbxcdn.com/' + version + '-' + name, package)!
		}
		if roblox_md5(package)! != lines[index + 1] {
			os.rm(package)!
			return error(name + ' does not match its manifest checksum; run again to refetch it')
		}
	}
	return RobloxDeployment{version, downloads}
}

fn roblox_fields(text string) []string {
	mut words := []string{}
	mut word := ''
	for ch in text.runes() {
		if ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f,
			0x205f, 0x3000] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a) {
			if word != '' {
				words << word
				word = ''
			}
		} else {
			word += ch.str()
		}
	}
	if word != '' { words << word }
	return words
}

pub fn roblox_member(directory string, filename string) !string {
	// The original discards empty components (including a leading slash),
	// normalizes backslashes and dot components, then refuses parent components.
	parts := filename.replace('\\', '/').split('/').filter(it != '' && it != '.')
	if '..' in parts { return error('entry outside its directory: ' + filename) }
	return ([directory, ...parts].filter(it != '')).join('/')
}

pub fn roblox_stage_archive(package string, directory string, client string) ! {
	archive := ah.open_archive(package)!
	for index, entry in archive.entries() {
		filename := entry.name
		relative := roblox_member(directory, filename) or { return error(os.file_name(package) + ' has an ' + err.msg()) }
		target := client + '/' + relative
		if filename.ends_with('/') || filename.ends_with('\\') {
			gamehost.mkdir(target)!
			continue
		}
		gamehost.mkdir(gamehost.parent(target))!
		// The archive entry is read by index, retaining duplicate-name ordering.
		os.write_file_array(target, archive.read_index(index)!)!
	}
}

pub fn roblox_stage(downloads string, client string) ! {
	if os.exists(client + '/.staged') { return }
	gamehost.remove(client)!
	for name, directory in roblox_packages {
		package := downloads + '/' + name
		if os.exists(package) { roblox_stage_archive(package, directory, client)! }
	}
	os.write_file(client + '/AppSettings.xml', roblox_settings)!
	os.write_file(client + '/.staged', '')!
}

pub fn roblox_copy_layer(source string, target string, skip []string) ! {
	copy_layer_at(source, target, skip, source)!
}

fn copy_layer_at(source string, target string, skip []string, base string) ! {
	gamehost.mkdir(target)!
	for name in os.ls(source)! {
		from := source + '/' + name
		to := target + '/' + name
		if from[base.len + 1..] in skip { continue }
		if os.is_link(from) {
			gamehost.copy_file(from, to)!
		} else if os.is_dir(from) {
			copy_layer_at(from, to, skip, base)!
		} else {
			gamehost.copy_file(from, to)!
		}
	}
}
