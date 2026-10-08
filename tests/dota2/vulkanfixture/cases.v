// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanfixture

import crypto.sha256
import encoding.hex
import json2
import qemubuild

fn case_stage(extra []string) ! {
	if extra.len == 0 { unit('run_stage', [])! } else { unit('run_stage', [words(extra)])! }
}

fn clone_scope(count string) ! {
	patch := with_patch('clone_tree', wrap('clone_tree'))!.as_map()
	clone_scope_body(patch['entered']!, count) or {
		failure := err
		if exit_context(patch['owner']!, failure)! { return }
		return failure
	}
	exit_context(patch['owner']!, none)!
}

fn clone_scope_body(mock json2.Any, count string) ! {
	case_stage([]string{})!
	method(mock, count, [])!
}

fn digest_scope(target string, character string, expect_clone bool, stamp string, old json2.Any) ! {
	original_digest := attribute(global('_stage')!, 'file_sha256')!
	descriptor := callback('changed_digest', json2.Any({
		'target':    json2.Any(target)
		'character': json2.Any(character)
		'fallback':  original_digest
	}), 'identity')
	patch := with_patch('file_sha256', descriptor)!.as_map()
	digest_body(expect_clone, stamp, old) or {
		failure := err
		if !exit_context(patch['owner']!, failure)! { return failure }
		return
	}
	exit_context(patch['owner']!, none)!
}

fn digest_body(expect_clone bool, stamp string, old json2.Any) ! {
	if expect_clone {
		patch := with_patch('clone_tree', wrap('clone_tree'))!.as_map()
		digest_assert(patch['entered']!, stamp, old) or {
			failure := err
			if !exit_context(patch['owner']!, failure)! { return failure }
			return
		}
		exit_context(patch['owner']!, none)!
	} else {
		case_stage([]string{})!
		unit('assertNotEqual', [read_text(stamp)!, old])!
	}
}

fn digest_assert(mock json2.Any, stamp string, old json2.Any) ! {
	case_stage([]string{})!
	method(mock, 'assert_called_once', [])!
	unit('assertNotEqual', [read_text(stamp)!, old])!
}

fn expect_stage(name string, args []json2.Any, message string) ! {
	public('_expect', [json2.Any(name), json2.Any(args), json2.Any('SystemExit'), json2.Any(message)])!
}

fn resolver(c Context, name string) !json2.Any {
	return public('_import', [json2.Any(name), path(c.repo + '/build-support/debian-root.py')])!
}

fn same_source(c Context) ! { equal(stage('package_files', [path(c.source)])!, c.before)! }

pub fn run_case(c Context, name string) ! {
	stamp := c.root + '/.vinix-dota2-vulkan-generation'
	match name {
		'test_full_package_and_legacy_paths_share_one_libc_family' {
			case_stage([]string{})!
			true_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
			for library in libraries()! {
				target := canonical(c, library)
				equal(read_bytes(target)!, data('new ' + library))!
				legacy := c.root + '/' + (if library.starts_with('ld-linux') {
					'lib64/'
				} else {
					'lib/x86_64-linux-gnu/'
				}) + library
				true_(qemubuild.is_link(legacy)!)!
				equal(path(qemubuild.resolve(legacy)!), path(qemubuild.resolve(target)!))!
			}
			for library, contents in {
				'libLLVM-15.so.1':          'keep LLVM'
				'libvulkan_lvp.so':         'patched Lavapipe'
				'libvinix-steam-robust.so': 'keep robust shim'
			} {
				equal(read_bytes(canonical(c, library))!, data(contents))!
			}
			equal(read_bytes(c.root + '/usr/share/doc/libc6/copyright')!, data('package copyright'))!
		}
		'test_cached_mixed_loader_is_rebuilt_and_restores_alias' {
			case_stage([]string{})!
			clone_scope('assert_not_called')!
			loader := c.root + '/lib64/ld-linux-x86-64.so.2'
			qemubuild.unlink(loader)!
			qemubuild.write(loader, 'old loader copied back')!
			false_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
			clone_scope('assert_called_once')!
			true_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
		}
		'test_changed_libm_and_gconv_invalidate_cached_full_package' {
			for relative in ['usr/lib/x86_64-linux-gnu/libm.so.6',
				'usr/lib/x86_64-linux-gnu/gconv/test.so'] {
				case_stage([]string{})!
				qemubuild.write(c.root + '/' + relative, 'wrong package version')!
				false_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
			}
			case_stage([]string{})!
			true_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
		}
		'test_wrong_legacy_libc_and_missing_marker_are_not_cache_hits' {
			case_stage([]string{})!
			libc := c.root + '/lib/x86_64-linux-gnu/libc.so.6'
			qemubuild.unlink(libc)!
			qemubuild.write(libc, 'old libc')!
			false_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
			case_stage([]string{})!
			qemubuild.unlink(staged(c, 'GLIBC_MARKER')!)!
			false_(stage('glibc_package_valid', [path(c.root), json2.Any(c.pin)])!.bool())!
		}
		'test_generation_tracks_alias_policy_package_pin_and_builder' {
			case_stage([]string{})!
			old := read_text(stamp)!
			patch := with_patch('GLIBC_ALIAS_POLICY', value(json2.Any('next-reviewed-policy')))!.as_map()
			generation_policy(stamp, old) or {
				failure := err
				if !exit_context(patch['owner']!, failure)! { return failure }
				return
			}
			exit_context(patch['owner']!, none)!
			case_stage([]string{})!
			equal(read_text(stamp)!, old)!
			mut pin := c.pin.clone()
			pin['version'] = json2.Any('2.41-next-reviewed-pin')
			set_member('pin', json2.Any(pin))!
			case_stage([]string{})!
			unit('assertNotEqual', [read_text(stamp)!, old])!
			changed := read_text(stamp)!
			equal(json_load(staged(c, 'GLIBC_MARKER')!)!.as_map()['package']!, member('pin')!)!
			digest_scope(attribute(global('_stage')!, '__file__')!.str(), 'a', false, stamp, changed)!
		}
		'test_early_v_abi_and_generator_invalidate_cache',
		'test_mmap_v_abi_and_export_policy_invalidate_cache' {
			case_stage([]string{})!
			relatives := if name == 'test_early_v_abi_and_generator_invalidate_cache' {
				['build-support/dota2/early-client-abi.h', 'build-support/dota2/compile-v-compat.py',
					'build-support/compile-v-module.py', 'build-support/find-v.sh']
			} else {
				['build-support/dota2/mmap32-abi.h', 'build-support/dota2/mmap32.exports']
			}
			for relative in relatives {
				old := read_text(stamp)!
				digest_scope(c.repo + '/' + relative, if name == 'test_early_v_abi_and_generator_invalidate_cache' {
					'b'
				} else {
					'c'
				}, true, stamp, old)!
				case_stage([]string{})!
				equal(read_text(stamp)!, old)!
			}
		}
		'test_baseline_option_keeps_the_steam_libc_without_overlay' {
			case_stage(['--keep-steam-libc'])!
			equal(read_bytes(c.root + '/lib64/ld-linux-x86-64.so.2')!, data('old loader'))!
			equal(read_bytes(c.root + '/lib/x86_64-linux-gnu/libc.so.6')!, data('old libc.so.6'))!
			false_(qemubuild.exists(staged(c, 'GLIBC_MARKER')!)!)!
		}
		'test_patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver' {
			case_stage([]string{})!
			equal(member('lavapipe_bases')!, json2.Any([data('old libc.so.6')]))!
			true_(stage('lavapipe_valid', [path(c.root), stage('lavapipe_inputs', [])!])!.bool())!
			icd := json_load(c.root + '/usr/share/vulkan/icd.d/lvp_icd.x86_64.json')!.as_map()
			equal(icd['ICD']!.as_map()['library_path']!, json2.Any('/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so'))!
			equal(read_bytes(canonical(c, 'libvulkan.so.1'))!, data('old Vulkan loader'))!
		}
		'test_replaced_lavapipe_is_not_a_cache_hit' {
			case_stage([]string{})!
			case_stage([]string{})!
			equal(member('lavapipe_bases')!, json2.Any([]json2.Any{}))!
			qemubuild.write(staged(c, 'LAVAPIPE_LIBRARY')!, 'keep Mesa')!
			false_(stage('lavapipe_valid', [path(c.root), stage('lavapipe_inputs', [])!])!.bool())!
			case_stage([]string{})!
			equal(read_bytes(staged(c, 'LAVAPIPE_LIBRARY')!)!, data('patched Lavapipe'))!
		}
		'test_baseline_option_keeps_debian_lavapipe' {
			case_stage(['--debian-lavapipe'])!
			equal(member('lavapipe_bases')!, json2.Any([]json2.Any{}))!
			equal(read_bytes(staged(c, 'LAVAPIPE_LIBRARY')!)!, data('keep Mesa'))!
			false_(qemubuild.exists(staged(c, 'LAVAPIPE_MARKER')!)!)!
			old := read_text(stamp)!
			case_stage([]string{})!
			unit('assertNotEqual', [read_text(stamp)!, old])!
			equal(read_bytes(staged(c, 'LAVAPIPE_LIBRARY')!)!, data('patched Lavapipe'))!
		}
		'test_other_debian_mesa_version_is_rejected' {
			mut inputs := stage('lavapipe_inputs', [])!.as_map()
			inputs['debian_version'] = json2.Any('22.3.6-1+deb12u3')
			patch := with_patch('lavapipe_inputs', return_(json2.Any(inputs)))!.as_map()
			expected := public('_wrap', [public('_assert_raises', [
				json2.Any('SystemExit'),
				json2.Any('pinned to 22.3.6-1\\+deb12u3'),
			])!])!
			method(expected, '__enter__', [])!
			reject_mesa(expected) or {
				failure := err
				if !exit_context(patch['owner']!, failure)! { return failure }
				return
			}
			exit_context(patch['owner']!, none)!
			false_(qemubuild.exists(c.root)!)!
		}
		'test_venus_is_staged_for_the_guest_root_with_bookworm_libc' {
			case_stage([]string{})!
			equal(member('venus_bases')!, json2.Any([data('old libc.so.6')]))!
			equal(read_bytes(staged(c, 'VENUS_LIBRARY')!)!, data('x86-64 Venus'))!
			icd := json_load(staged(c, 'VENUS_ICD')!)!.as_map()
			equal(icd['ICD']!.as_map()['library_path']!, json2.Any('/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvulkan_virtio.so'))!
			true_(stage('venus_valid', [path(c.root), stage('venus_inputs', [])!])!.bool())!
		}
		'test_replaced_venus_is_not_a_cache_hit' {
			case_stage([]string{})!
			qemubuild.write(staged(c, 'VENUS_LIBRARY')!, 'other driver')!
			false_(stage('venus_valid', [path(c.root), stage('venus_inputs', [])!])!.bool())!
			case_stage([]string{})!
			equal(read_bytes(staged(c, 'VENUS_LIBRARY')!)!, data('x86-64 Venus'))!
		}
		'test_option_omits_venus' {
			case_stage(['--no-venus'])!
			equal(member('venus_bases')!, json2.Any([]json2.Any{}))!
			false_(qemubuild.exists(staged(c, 'VENUS_LIBRARY')!)!)!
			false_(qemubuild.exists(staged(c, 'VENUS_ICD')!)!)!
		}
		'test_corrupt_cached_package_fails_before_cloning_payload_into_root' {
			r := resolver(c, 'test_debian_root')!
			archive := c.cache + '/' + qemubuild.basename(c.pin['filename']!.str())
			qemubuild.write(archive, 'bad cached archive')!
			owner := public('_wrap', [public('_patch_object', [r, json2.Any('download'), path(archive)])!])!
			method(owner, '__enter__', [])!
			expect_stage('stage_glibc_package', [r, json2.Any(c.pin), path(c.cache), path(c.source)], 'checksum or size mismatch') or {
				failure := err
				if !exit_context(owner, failure)! { return failure }
				return
			}
			exit_context(owner, none)!
			same_source(c)!
		}
		'test_pin_rejects_wrong_architecture' {
			pin := c.base + '/wrong-pin.json'
			mut wrong := c.pin.clone()
			wrong['architecture'] = json2.Any('i386')
			qemubuild.write(pin, json_dump(json2.Any(wrong))!)!
			expect_stage('load_glibc_pin', [path(pin)], 'pinned amd64 libc6')!
		}
		'test_partial_libc_family_fails_before_changing_the_source' {
			r := resolver(c, 'test_debian_root_partial')!
			contents := hex.decode(fixture_deb({
				'usr/lib/x86_64-linux-gnu/libc.so.6': 'only libc'.bytes().hex()
			}, map[string]string{})!)!.bytestr()
			archive := c.cache + '/' + qemubuild.basename(c.pin['filename']!.str())
			qemubuild.write(archive, contents)!
			mut pin := c.pin.clone()
			pin['size'] = json2.Any(contents.len)
			pin['sha256'] = json2.Any(sha256.sum(contents.bytes()).hex())
			expect_stage('stage_glibc_package', [r, json2.Any(pin), path(c.cache), path(c.source)], 'complete usrmerged amd64 family')!
			same_source(c)!
		}
		else { return error('Unknown Vulkan staging fixture: ' + name) }
	}
}

fn reject_mesa(expected json2.Any) ! {
	case_stage([]string{}) or {
		failure := err
		if exit_context(expected, failure)! { return }
		return failure
	}
	exit_context(expected, none)!
}

fn generation_policy(stamp string, old json2.Any) ! {
	case_stage([]string{})!
	unit('assertNotEqual', [read_text(stamp)!, old])!
}
