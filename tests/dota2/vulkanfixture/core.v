// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanfixture

import crypto.sha256
import encoding.hex
import json2
import qemubuild

struct Context {
	base   string
	steam  string
	source string
	build  string
	cache  string
	root   string
	repo   string
	python string
	pin    map[string]json2.Any
	before json2.Any
}

fn context(repo string, python string) !Context {
	return Context{decoded(member('base')!)!, decoded(member('steam')!)!, decoded(member('source')!)!, decoded(member('build')!)!, decoded(member('cache')!)!, decoded(member('root')!)!, repo, python, member('pin')!.as_map(), member('before')!}
}

pub fn write(filename string, contents string) ! {
	qemubuild.mkdir(filename.all_before_last('/'), true, true)!
	qemubuild.write(filename, contents)!
}

fn unit_write(filename string, contents string) ! {
	unit('write', [path(filename), data(contents)])!
}

fn set_path(name string, filename string) ! { set_member(name, path(filename))! }

fn json_dump(value json2.Any) !string {
	return request({
		'kind':      json2.Any('json_dumps')
		'arguments': json2.Any([value])
	})!.str()
}

fn json_load(filename string) !json2.Any {
	return request({
		'kind':     json2.Any('json_loads')
		'data_hex': json2.Any(qemubuild.read_text(filename)!.bytes().hex())
	})!
}

fn read_bytes(filename string) !json2.Any { return data(qemubuild.read(filename)!) }

fn read_text(filename string) !json2.Any { return json2.Any(qemubuild.read_text(filename)!) }

fn libraries() ![]string { return constant('GLIBC_LIBRARIES')!.as_array().map(it.str()) }

fn canonical(c Context, name string) string { return c.root + '/usr/lib/x86_64-linux-gnu/' + name }

fn staged(c Context, name string) !string { return c.root + '/' + constant(name)!.str() }

fn payload(files map[string]string, links map[string]string) !string {
	stream := method(global('io')!, 'BytesIO', [])!
	archive := request({
		'kind':      json2.Any('method')
		'target':    global('tarfile')!
		'name':      json2.Any('open')
		'arguments': json2.Any([]json2.Any{})
		'keywords':  json2.Any({
			'fileobj': stream
			'mode':    json2.Any('w:gz')
		})
	})!
	manager := public('_wrap', [archive])!
	entered := method(manager, '__enter__', [])!
	mut retired := false
	add_members(entered, files, links) or {
		failure := err
		retired = true
		if !exit_context(manager, failure)! { return failure }
	}
	if !retired { exit_context(manager, none)! }
	contents := method(stream, 'getvalue', [])!
	return method(contents, 'hex', [])!.str()
}

fn add_members(archive json2.Any, files map[string]string, links map[string]string) ! {
	for name, contents in files {
		item := method(global('tarfile')!, 'TarInfo', [json2.Any('./' + name)])!
		method(item, '__setattr__', [json2.Any('size'), json2.Any(contents.len / 2)])!
		method(item, '__setattr__', [json2.Any('mode'), json2.Any(0o755)])!
		bytes := method(global('bytes')!, 'fromhex', [json2.Any(contents)])!
		stream := method(global('io')!, 'BytesIO', [bytes])!
		method(archive, 'addfile', [item, stream])!
	}
	for name, target in links {
		item := method(global('tarfile')!, 'TarInfo', [json2.Any('./' + name)])!
		method(item, '__setattr__', [json2.Any('type'), attribute(global('tarfile')!, 'SYMTYPE')!])!
		method(item, '__setattr__', [json2.Any('linkname'), json2.Any(target)])!
		method(item, '__setattr__', [json2.Any('mode'), json2.Any(0o777)])!
		method(archive, 'addfile', [item])!
	}
}

fn pad(value string, width int) string {
	return value + ' '.repeat(if value.len < width { width - value.len } else { 0 })
}

pub fn deb_bytes(files map[string]string, links map[string]string) !string {
	encoded := payload(files, links)!
	header := pad('data.tar.gz/', 16) + pad('0', 12) + pad('0', 6) + pad('0', 6) + pad('100644', 8) + pad((encoded.len / 2).str(), 10) + '`\n'
	return '!<arch>\n'.bytes().hex() + header.bytes().hex() + encoded + if encoded.len / 2 % 2 == 1 {
		'0a'
	} else {
		''
	}
}

fn fixture_deb(files map[string]string, links map[string]string) !string {
	mut input := map[string]json2.Any{}
	for name, contents in files {
		input[name] = json2.Any({
			'bytes_hex': json2.Any(contents)
		})
	}
	mut aliases := map[string]json2.Any{}
	for name, target in links { aliases[name] = json2.Any(target) }
	mut bundle := [json2.Any(input)]
	if aliases.len > 0 { bundle << json2.Any(aliases) }
	result := public('_deb_bytes', bundle)!
	return method(result, 'hex', [])!.str()
}

pub fn setup(repo string, python string) ! {
	temporary := method(global('tempfile')!, 'TemporaryDirectory', [])!
	set_member('temporary', temporary)!
	unit('addCleanup', [attribute(temporary, 'cleanup')!])!
	base := attribute(temporary, 'name')!.str()
	steam := base + '/steam'
	source := steam + '/staging/usr/libexec/vinix-steam/root'
	set_path('base', base)!
	set_path('steam', steam)!
	set_path('source', source)!
	qemubuild.mkdir(source, true, false)!
	build := base + '/build'
	cache := build + '/downloads'
	root := build + '/staging/usr/libexec/vinix-dota2/root'
	set_path('build', build)!
	set_path('cache', cache)!
	qemubuild.mkdir(cache, true, false)!
	set_path('root', root)!
	unit_write(source + '/lib64/ld-linux-x86-64.so.2', 'old loader')!
	names := libraries()!
	for name in names[1..] { unit_write(source + '/lib/x86_64-linux-gnu/' + name, 'old ' + name)! }
	for name, contents in {
		'libLLVM-15.so.1':          'keep LLVM'
		'libfreetype.so.6':         'keep FreeType'
		'libvinix-steam-robust.so': 'keep robust shim'
	} {
		unit_write(source + '/usr/lib/x86_64-linux-gnu/' + name, contents)!
	}
	mut pin := stage('load_glibc_pin', [])!.as_map()
	set_member('pin', json2.Any(pin))!
	mut family := map[string]string{}
	for name in names { family['usr/lib/x86_64-linux-gnu/' + name] = ('new ' + name).bytes().hex() }
	family['usr/lib/x86_64-linux-gnu/gconv/test.so'] = 'new gconv'.bytes().hex()
	family['usr/share/doc/libc6/copyright'] = 'package copyright'.bytes().hex()
	contents := hex.decode(fixture_deb(family, {
		'usr/lib64/ld-linux-x86-64.so.2': '../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'
	})!)!.bytestr()
	pin['sha256'] = json2.Any(sha256.sum(contents.bytes()).hex())
	pin['size'] = json2.Any(contents.len)
	set_member('pin', json2.Any(pin))!
	qemubuild.write(cache + '/' + qemubuild.basename(pin['filename']!.str()), contents)!
	packages := {
		'libvulkan1':          {
			'usr/lib/x86_64-linux-gnu/libvulkan.so.1': 'old Vulkan loader'
		}
		'mesa-vulkan-drivers': {
			'usr/lib/x86_64-linux-gnu/libvulkan_lvp.so':  'keep Mesa'
			'usr/share/vulkan/icd.d/lvp_icd.x86_64.json': '{"ICD":{"library_path":"old"}}'
		}
		'vulkan-tools':        {
			'usr/bin/vulkaninfo': 'vulkaninfo'
			'usr/bin/vkcube':     'vkcube'
		}
		'libpipewire-0.3-0':   map[string]string{}
		'libopenal1':          map[string]string{}
		'libnm0':              map[string]string{}
		'ca-certificates':     {
			'usr/share/ca-certificates/mozilla/public.crt': 'PUBLIC CERTIFICATE\n'
		}
	}
	mesa_version := stage('lavapipe_inputs', [])!.as_map()['debian_version']!.str()
	set_member('mesa_version', json2.Any(mesa_version))!
	mut records := []string{}
	for name, files in packages {
		filename := name + '_1_amd64.deb'
		mut encoded := map[string]string{}
		for file, bytes in files { encoded[file] = bytes.bytes().hex() }
		archive_data := hex.decode(fixture_deb(encoded, map[string]string{})!)!.bytestr()
		qemubuild.write(cache + '/' + filename, archive_data)!
		version := if name == 'mesa-vulkan-drivers' { mesa_version } else { '1' }
		records << 'Package: ' + name + '\nVersion: ' + version + '\nArchitecture: amd64\nFilename: pool/' + filename + '\nSize: ' + archive_data.len.str() + '\nSHA256: ' + sha256.sum(archive_data.bytes()).hex() + '\n'
	}
	unit_write(steam + '/downloads/bookworm_amd64_Packages', records.join('\n'))!
	unit_write(steam + '/amd64-packages', 'libc6\told\tamd64\told.deb\n')!
	unit_write(steam + '/i386-packages', 'libc6\told\ti386\told.deb\n')!
	set_member('before', stage('package_files', [path(source)])!)!
}
