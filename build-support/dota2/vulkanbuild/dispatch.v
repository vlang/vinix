// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import encoding.hex
import json2
import os
import qemubuild

pub fn dispatch(row map[string]json2.Any) !json2.Any {
	repo := hex.decode(text(row, 'repo_hex'))!.bytestr()
	python := hex.decode(text(row, 'python_hex'))!.bytestr()
	args := field(row, 'arguments').as_map()
	match text(row, 'operation') {
		'constant' { return exported_constant(repo, text(args, 'name'))! }
		'policy_sources' {
			mut sources := [repo + '/build-support/dota2/_vulkan_native.py',
				repo + '/build-support/dota2/vulkan_query.v',
				repo + '/build-support/dota2/vulkan_sdk_library.v',
				repo + '/build-support/build-v-host-library.sh']
			for directory in ['build-support/dota2/vulkanbuild', 'build-support/dota2/qemubuild',
				'build-support/cachekey', 'tests/qemu-core/fixturehost',
				'build-support/cpythonhost', 'build-support/android/androidhost'] {
				mut names := os.ls(repo + '/' + directory)!
				names = names.filter(it.ends_with('.v') || it.ends_with('.h'))
				names.sort()
				for name in names {
					if directory == 'build-support/cpythonhost' && name.contains('_d_')
						&& !name.ends_with('_d_cpython_host.c.v') && !name.ends_with('_d_cpython_vulkan.c.v') { continue }
					sources << repo + '/' + directory + '/' + name
				}
			}
			return words(sources)
		}
		'file_sha256' { return json2.Any(qemubuild.digest(path(args['path']!)!)!) }
		'clone_tree' {
			clone_tree(path(args['source']!)!, path(args['destination']!)!, text(row, 'platform'))!
		}
		'compatibility_inputs' {
			return compatibility_inputs(repo, text(args, 'module'), text(args, 'header'), args['extra']!)!
		}
		'early_client_inputs' {
			return public('compatibility_inputs', [json2.Any('earlycore'),
				json2.Any('early-client-abi.h')])!
		}
		'mmap32_inputs' {
			return public('compatibility_inputs', [json2.Any('mmapcore'), json2.Any('mmap32-abi.h'),
				json2.Any([paths(repo + '/build-support/dota2/mmap32.exports')])])!
		}
		'build_mmap32', 'build_early_client' {
			build_compat(repo, python, path(args['destination']!)!, path(args['artifacts']!)!, text(row, 'operation') == 'build_early_client')!
		}
		'package_files' { return package_files(path(args['root']!)!)! }
		'stage_glibc_package' {
			stage_glibc_package(args['resolver']!, args['pin']!.as_map(), path(args['cache']!)!, path(args['root']!)!)!
		}
		'lavapipe_inputs' { return lavapipe_inputs()! }
		'venus_inputs' { return venus_inputs()! }
		'stage_lavapipe' {
			stage_lavapipe(args['selected']!.as_array(), path(args['root']!)!, path(args['work']!)!, args['expected']!.as_map())!
		}
		'stage_venus' {
			stage_venus(path(args['root']!)!, path(args['work']!)!, text(args, 'guest_root'), args['expected']!.as_map())!
		}
		'main' {
			mut metadata := row.clone()
			metadata['builder'] = json2.Any(hex.decode(text(row, 'builder_hex'))!.bytestr())
			stage(metadata, args['options']!.as_map(), repo)!
		}
		else {
			return StageError{'RuntimeError', 'Unknown Vulkan operation: ' + text(row, 'operation')}
		}
	}
	return json2.Null{}
}
