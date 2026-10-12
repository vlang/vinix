// SPDX-License-Identifier: GPL-2.0-or-later
module runtimefixtures

import crypto.sha256
import encoding.hex
import gamehost
import json2
import os
import runtimehost
import sourcecommand
import tarcore

const family = ['ld-linux-x86-64.so.2', 'libc.so.6', 'libm.so.6', 'libresolv.so.2', 'libpthread.so.0',
	'libdl.so.2']

struct Fixture {
	repo   string
	base   string
	steam  string
	source string
	build  string
	root   string
	cache  string
mut:
	pin              map[string]json2.Any
	clones           int
	lavapipe_bases   []string
	venus_bases      []string
	changed_digest   string
	alias_policy     string
	wrong_mesa       bool
	corrupt_download bool
}

fn path(value string) json2.Any {
	return json2.Any({
		'path_hex': json2.Any(value.bytes().hex())
	})
}

fn decode(value json2.Any) !string {
	return hex.decode(value.as_map()['path_hex']!.str())!.bytestr()
}

fn write(file string, content string) ! {
	gamehost.mkdir(gamehost.parent(file))!
	os.write_file(file, content)!
}

fn package(f Fixture, name string, files map[string]string, links map[string]string) ![]u8 {
	archive := f.base + '/' + name + '.tar.gz'
	mut writer := tarcore.create_gzip(archive)!
	for filename, contents in files {
		writer.add(tarcore.Member{ name: './' + filename, mode: 0o755, size: u64(contents.len) }, contents.bytes())!
	}
	for filename, target in links {
		writer.add(tarcore.Member{ name: './' + filename, kind: `2`, mode: 0o777, linkname: target }, []u8{})!
	}
	writer.finish()!
	writer.close_checked()!
	bytes := os.read_bytes(archive)!
	name_field := 'data.tar.gz/'
	header := name_field + ' '.repeat(16 - name_field.len) + '0           0     0     100644  ' + bytes.len.str() + ' '.repeat(10 - bytes.len.str().len) + '`\n'
	assert header.len == 60
	mut result := '!<arch>\n'.bytes()
	result << header.bytes()
	result << bytes
	if bytes.len & 1 != 0 { result << `\n` }
	return result
}

fn setup(repo string, base string) !Fixture {
	steam := base + '/steam'
	source := steam + '/staging/usr/libexec/vinix-steam/root'
	build := base + '/build'
	cache := build + '/downloads'
	mut f := Fixture{ repo: repo, base: base, steam: steam, source: source, build: build, cache: cache, root: build + '/staging/usr/libexec/vinix-dota2/root', pin: runtimehost.load_glibc_pin(repo)! }
	gamehost.mkdir(cache)!
	write(source + '/lib64/' + family[0], 'old loader')!
	for name in family[1..] { write(source + '/lib/x86_64-linux-gnu/' + name, 'old ' + name)! }
	for name, contents in {
		'libLLVM-15.so.1':          'keep LLVM'
		'libfreetype.so.6':         'keep FreeType'
		'libvinix-steam-robust.so': 'keep robust shim'
	} {
		write(source + '/usr/lib/x86_64-linux-gnu/' + name, contents)!
	}
	mut files := map[string]string{}
	for name in family { files['usr/lib/x86_64-linux-gnu/' + name] = 'new ' + name }
	files['usr/lib/x86_64-linux-gnu/gconv/test.so'] = 'new gconv'
	files['usr/share/doc/libc6/copyright'] = 'package copyright'
	bytes := package(f, 'glibc', files, {
		'usr/lib64/' + family[0]: '../lib/x86_64-linux-gnu/' + family[0]
	})!
	f.pin['sha256'] = json2.Any(sha256.sum(bytes).hex())
	f.pin['size'] = json2.Any(bytes.len)
	os.write_file_array(cache + '/' + f.pin['filename']!.str().all_after_last('/'), bytes)!
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
	mut context := runtimehost.VulkanContext{ tools: gamehost.Tools{ root: repo } }
	defer { context.close() }
	version := context.call('lavapipe_inputs', {})!.as_map()['debian_version']!.str()
	mut rows := []string{}
	for name, contents in packages {
		filename := name + '_1_amd64.deb'
		data := package(f, name, contents, {})!
		os.write_file_array(cache + '/' + filename, data)!
		selected_version := if name == 'mesa-vulkan-drivers' { version } else { '1' }
		rows << 'Package: ${name}\nVersion: ${selected_version}\nArchitecture: amd64\nFilename: pool/${filename}\nSize: ${data.len}\nSHA256: ${sha256.sum(data).hex()}\n'
	}
	write(steam + '/downloads/bookworm_amd64_Packages', rows.join('\n'))!
	write(steam + '/amd64-packages', 'libc6\told\tamd64\told.deb\n')!
	write(steam + '/i386-packages', 'libc6\told\ti386\told.deb\n')!
	return f
}

fn vulkan_fixture_command(argv []string, _ bool, _ voidptr) !sourcecommand.Output {
	if argv[0] == 'sh' {
		assert argv[1..4] == ['-c', '. "$1/build-support/find-v.sh"; "$V" -version', 'find-v']
		return sourcecommand.Output{ stdout: 'fixture V compiler\n' }
	}
	if argv[0].ends_with('/compile-v-compat') {
		assert argv[1] in ['early', 'mmap32'] && argv[3..] == ['--bare']
		write(argv[2], 'generated V artifact')!
	} else if argv[0] == 'clang' {
		write(argv[argv.index('-o') + 1], 'compiled private shim')!
	} else if argv[0] == '/bin/cp' {
		assert argv[1] == '-cRp'
		gamehost.copy_tree(argv[2], argv[3], false)!
	} else {
		return error('fixture must never fetch the network: ' + argv.str())
	}
	return sourcecommand.Output{}
}

fn primitive(row map[string]json2.Any, pointer voidptr) !runtimehost.PrimitiveReplacement {
	mut f := unsafe { &Fixture(pointer) }
	name := (row['name'] or { json2.Any('') }).str()
	kind := row['kind']!.str()
	args := (row['arguments'] or { json2.Any([]json2.Any{}) }).as_array()
	if kind == 'method' && name == 'download' && f.corrupt_download {
		return runtimehost.PrimitiveReplacement{ handled: true, value: path(f.cache + '/' + f.pin['filename']!.str().all_after_last('/')) }
	}
	if kind == 'global' && name == 'GLIBC_ALIAS_POLICY' && f.alias_policy != '' {
		return runtimehost.PrimitiveReplacement{ handled: true, value: json2.Any(f.alias_policy) }
	}
	if kind == 'public' {
		if name == 'load_glibc_pin' {
			return runtimehost.PrimitiveReplacement{ handled: true, value: json2.Any(f.pin) }
		}
		if name == 'clone_tree' { f.clones++ }
		if name == 'file_sha256' && decode(args[0])! == f.changed_digest {
			return runtimehost.PrimitiveReplacement{ handled: true, value: json2.Any('a'.repeat(64)) }
		}
		if name == 'lavapipe_inputs' && f.wrong_mesa {
			// Obtain the ordinary inputs without recursively invoking this hook.
			mut plain := runtimehost.VulkanContext{ tools: gamehost.Tools{ root: f.repo, command_hook: vulkan_fixture_command } }
			defer { plain.close() }
			mut inputs := plain.call('lavapipe_inputs', {})!.as_map()
			inputs['debian_version'] = json2.Any('22.3.6-1+deb12u3')
			return runtimehost.PrimitiveReplacement{ handled: true, value: json2.Any(inputs) }
		}
	}
	return runtimehost.PrimitiveReplacement{}
}

fn driver(venus bool, base string, work string, pointer voidptr) ![]string {
	mut f := unsafe { &Fixture(pointer) }
	libc := os.read_file(base + '/lib/x86_64-linux-gnu/libc.so.6')!
	assert work == f.build + '/' + if venus { 'venus' } else { 'mesa' }
	if venus {
		f.venus_bases << libc
		library := f.base + '/venus/libvulkan_virtio.so'
		manifest := f.base + '/venus/virtio_icd.json'
		write(library, 'x86-64 Venus')!
		write(manifest, '{"file_format_version":"1.0.0","ICD":{"library_path":"/usr/lib/x86_64-linux-gnu/libvulkan_virtio.so","api_version":"1.3.305"}}')!
		return [library, manifest]
	}
	f.lavapipe_bases << libc
	library := f.base + '/lavapipe/libvulkan_lvp.so'
	write(library, 'patched Lavapipe')!
	return [library]
}

fn stage(mut context runtimehost.VulkanContext, mut f Fixture, extra []string) ! {
	f.lavapipe_bases.clear()
	f.venus_bases.clear()
	f.clones = 0
	before := context.call('package_files', {
		'root': path(f.source)
	})!
	options := {
		'steam_build':     path(f.steam)
		'build':           path(f.build)
		'root':            json2.Any(json2.Null{})
		'release':         json2.Any('bookworm')
		'mirror':          json2.Any('https://fixture.invalid')
		'guest_root':      json2.Any('/usr/libexec/vinix-dota2/root')
		'refresh':         json2.Any(false)
		'keep_steam_libc': json2.Any('--keep-steam-libc' in extra)
		'debian_lavapipe': json2.Any('--debian-lavapipe' in extra)
		'no_venus':        json2.Any('--no-venus' in extra)
	}
	context.call('main', {
		'options': json2.Any(options)
	})!
	assert runtimehost.native_dumps(context.call('package_files', {
		'root': path(f.source)
	})!, true, false)! == runtimehost.native_dumps(before, true, false)!
}

fn glibc_valid(f Fixture) !bool {
	return runtimehost.glibc_valid(f.root, json2.Any(f.pin), if f.alias_policy != '' {
		f.alias_policy
	} else {
		'bookworm-lib-to-usrmerged-libc-relative-v1'
	})!
}

pub fn vulkan_cases(repo string, work string, selection string) ! {
	// Darwin filesystems reject invalid UTF-8 names. Exercise their serialized
	// filesystem-byte representation independently of the host filesystem.
	raw := json2.Any({
		'filesystem_map': json2.Any([json2.Any([json2.Any('7261772dff'),
			json2.Any({
				'target': json2.Any({
					'filesystem_text': json2.Any('eda080')
				})
			})])])
	})
	assert runtimehost.native_dumps(raw, true, false)! == '{"raw-\\udcff": {"target": "\\udced\\udca0\\udc80"}}'
	names := [
		'full_package_and_legacy_paths_share_one_libc_family',
		'cached_mixed_loader_is_rebuilt_and_restores_alias',
		'changed_libm_and_gconv_invalidate_cached_full_package',
		'wrong_legacy_libc_and_missing_marker_are_not_cache_hits',
		'generation_tracks_alias_policy_package_pin_and_builder',
		'early_v_abi_and_generator_invalidate_cache',
		'mmap_v_abi_and_export_policy_invalidate_cache',
		'baseline_option_keeps_the_steam_libc_without_overlay',
		'patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver',
		'replaced_lavapipe_is_not_a_cache_hit',
		'baseline_option_keeps_debian_lavapipe',
		'other_debian_mesa_version_is_rejected',
		'venus_is_staged_for_the_guest_root_with_bookworm_libc',
		'replaced_venus_is_not_a_cache_hit',
		'option_omits_venus',
		'corrupt_cached_package_fails_before_cloning_payload_into_root',
		'pin_rejects_wrong_architecture',
		'partial_libc_family_fails_before_changing_the_source',
	]
	mut count := 0
	for index, name in names {
		if selection != '' && !name.contains(selection) { continue }
		mut f := setup(repo, work + '/' + index.str())!
		mut context := runtimehost.VulkanContext{ tools: gamehost.Tools{ root: repo, command_hook: vulkan_fixture_command }, primitive_hook: primitive, primitive_context: &f, driver_hook: driver, driver_context: &f }
		stamp := f.root + '/.vinix-dota2-vulkan-generation'
		if name == 'baseline_option_keeps_the_steam_libc_without_overlay' {
			stage(mut context, mut f, ['--keep-steam-libc'])!
			assert os.read_file(f.root + '/lib64/' + family[0])! == 'old loader'
			assert os.read_file(f.root + '/lib/x86_64-linux-gnu/libc.so.6')! == 'old libc.so.6'
			assert !os.exists(f.root + '/.vinix-dota2-glibc-package.json')
		} else if name == 'option_omits_venus' {
			stage(mut context, mut f, ['--no-venus'])!
			assert f.venus_bases.len == 0 && !os.exists(f.root + '/usr/lib/x86_64-linux-gnu/libvulkan_virtio.so') && !os.exists(f.root + '/usr/share/vulkan/icd.d/virtio_icd.x86_64.json')
		} else if name == 'baseline_option_keeps_debian_lavapipe' {
			stage(mut context, mut f, ['--debian-lavapipe'])!
			assert f.lavapipe_bases.len == 0 && os.read_file(f.root + '/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so')! == 'keep Mesa'
			assert !os.exists(f.root + '/.vinix-dota2-lavapipe.json')
			old := os.read_file(stamp)!
			stage(mut context, mut f, [])!
			assert os.read_file(stamp)! != old && os.read_file(f.root + '/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so')! == 'patched Lavapipe'
		} else if name in [
			'corrupt_cached_package_fails_before_cloning_payload_into_root',
			'partial_libc_family_fails_before_changing_the_source',
		] {
			before := runtimehost.native_dumps(context.call('package_files', {
				'root': path(f.source)
			})!, true, false)!
			archive := f.cache + '/' + f.pin['filename']!.str().all_after_last('/')
			if name.starts_with('partial') {
				bytes := package(f, 'partial', {
					'usr/lib/x86_64-linux-gnu/libc.so.6': 'only libc'
				}, {})!
				os.write_file_array(archive, bytes)!
				f.pin['size'] = json2.Any(bytes.len)
				f.pin['sha256'] = json2.Any(sha256.sum(bytes).hex())
			} else {
				os.write_file(archive, 'bad cached archive')!
				f.corrupt_download = true
			}
			mut refused := false
			context.call('stage_glibc_package', {
				'resolver': json2.Any({
					'module': json2.Any('debian')
				})
				'pin':      json2.Any(f.pin)
				'cache':    path(f.cache)
				'root':     path(f.source)
			}) or {
				refused = true
				assert err.msg().contains(if f.corrupt_download {
					'checksum or size mismatch'
				} else {
					'complete usrmerged amd64 family'
				})
			}
			assert refused && runtimehost.native_dumps(context.call('package_files', {
				'root': path(f.source)
			})!, true, false)! == before
			for filename in os.ls(f.cache)! {
				assert !filename.starts_with('.vinix-deb.') && !filename.starts_with('.native-game.')
			}
		} else if name == 'pin_rejects_wrong_architecture' {
			mut wrong := f.pin.clone()
			wrong['architecture'] = json2.Any('i386')
			mut refused := false
			runtimehost.validate_glibc(json2.Any(wrong)) or {
				refused = true
				assert err.msg().contains('pinned amd64 libc6')
			}
			assert refused
		} else if name == 'other_debian_mesa_version_is_rejected' {
			f.wrong_mesa = true
			mut refused := false
			stage(mut context, mut f, []) or {
				refused = true
				assert err.msg().contains('pinned to 22.3.6-1+deb12u3')
			}
			assert refused && !os.exists(f.root)
		} else {
			stage(mut context, mut f, [])!
			assert glibc_valid(f)!
			match name {
				'full_package_and_legacy_paths_share_one_libc_family' {
					for library in family {
						target := f.root + '/usr/lib/x86_64-linux-gnu/' + library
						assert os.read_file(target)! == 'new ' + library
						alias := f.root + '/' + if library == family[0] {
							'lib64/' + library
						} else {
							'lib/x86_64-linux-gnu/' + library
						}
						assert os.is_link(alias) && os.real_path(alias) == os.real_path(target)
					}
					for library, expected in {
						'libLLVM-15.so.1':          'keep LLVM'
						'libvulkan_lvp.so':         'patched Lavapipe'
						'libvinix-steam-robust.so': 'keep robust shim'
					} {
						assert os.read_file(f.root + '/usr/lib/x86_64-linux-gnu/' + library)! == expected
					}
					assert os.read_file(f.root + '/usr/share/doc/libc6/copyright')! == 'package copyright'
				}
				'cached_mixed_loader_is_rebuilt_and_restores_alias',
				'wrong_legacy_libc_and_missing_marker_are_not_cache_hits' {
					stage(mut context, mut f, [])!
					assert f.clones == 0
					alias := f.root + '/' + if name.starts_with('cached') {
						'lib64/' + family[0]
					} else {
						'lib/x86_64-linux-gnu/libc.so.6'
					}
					os.rm(alias)!
					os.write_file(alias, 'old family copied back')!
					assert !glibc_valid(f)!
					stage(mut context, mut f, [])!
					assert f.clones == 1 && glibc_valid(f)!
					if name.starts_with('wrong') {
						os.rm(f.root + '/.vinix-dota2-glibc-package.json')!
						assert !glibc_valid(f)!
					}
				}
				'changed_libm_and_gconv_invalidate_cached_full_package' {
					for relative in ['usr/lib/x86_64-linux-gnu/libm.so.6',
						'usr/lib/x86_64-linux-gnu/gconv/test.so'] {
						os.write_file(f.root + '/' + relative, 'wrong package version')!
						assert !glibc_valid(f)!
						stage(mut context, mut f, [])!
						assert f.clones == 1 && glibc_valid(f)!
					}
				}
				'generation_tracks_alias_policy_package_pin_and_builder' {
					old := os.read_file(stamp)!
					f.alias_policy = 'next-reviewed-policy'
					stage(mut context, mut f, [])!
					assert os.read_file(stamp)! != old
					f.alias_policy = ''
					stage(mut context, mut f, [])!
					assert os.read_file(stamp)! == old
					f.pin['version'] = json2.Any('2.41-next-reviewed-pin')
					stage(mut context, mut f, [])!
					assert os.read_file(stamp)! != old
					marker := json2.decode[json2.Any](os.read_file(f.root + '/.vinix-dota2-glibc-package.json')!)!.as_map()
					assert marker['package']!.as_map()['version']!.str() == '2.41-next-reviewed-pin'
					changed := os.read_file(stamp)!
					f.changed_digest = repo + '/tests/native-runtime-tools/main.v'
					stage(mut context, mut f, [])!
					assert os.read_file(stamp)! != changed
				}
				'early_v_abi_and_generator_invalidate_cache',
				'mmap_v_abi_and_export_policy_invalidate_cache' {
					relatives := if name.starts_with('early') {
						['build-support/dota2/early-client-abi.h',
							'build-support/dota2/compile-v-compat', 'build-support/dota2/compat.v',
							'build-support/compile-v-module', 'build-support/find-v.sh']
					} else {
						['build-support/dota2/mmap32-abi.h', 'build-support/dota2/mmap32.exports']
					}
					for relative in relatives {
						old := os.read_file(stamp)!
						f.changed_digest = repo + '/' + relative
						stage(mut context, mut f, [])!
						assert f.clones == 1 && os.read_file(stamp)! != old
						f.changed_digest = ''
						stage(mut context, mut f, [])!
						assert os.read_file(stamp)! == old
					}
				}
				'patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver',
				'venus_is_staged_for_the_guest_root_with_bookworm_libc' {
					assert f.lavapipe_bases == ['old libc.so.6'] && f.venus_bases == ['old libc.so.6']
					assert os.read_file(f.root + '/usr/lib/x86_64-linux-gnu/libvulkan.so.1')! == 'old Vulkan loader'
					for pair in [['lvp_icd.x86_64.json', 'libvulkan_lvp.so'],
						['virtio_icd.x86_64.json', 'libvulkan_virtio.so']] {
						icd := json2.decode[json2.Any](os.read_file(f.root + '/usr/share/vulkan/icd.d/' + pair[0])!)!.as_map()
						assert icd['ICD']!.as_map()['library_path']!.str() == '/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/' + pair[1]
					}
				}
				'replaced_lavapipe_is_not_a_cache_hit', 'replaced_venus_is_not_a_cache_hit' {
					stage(mut context, mut f, [])!
					assert f.clones == 0 && f.lavapipe_bases.len == 0 && f.venus_bases.len == 0
					filename := f.root + '/usr/lib/x86_64-linux-gnu/' + if name.contains('venus') {
						'libvulkan_virtio.so'
					} else {
						'libvulkan_lvp.so'
					}
					os.write_file(filename, 'other driver')!
					stage(mut context, mut f, [])!
					assert f.clones == 1
					assert os.read_file(filename)! == if name.contains('venus') {
						'x86-64 Venus'
					} else {
						'patched Lavapipe'
					}
				}
				else { return error('unhandled native Vulkan case: ' + name) }
			}
		}
		context.close()
		count++
		eprintln('test_' + name + ': PASS')
	}
	if count == 0 { return error('no native Vulkan fixtures matched') }
	write(work + '/passed', 'PASS ${count}\n')!
}
