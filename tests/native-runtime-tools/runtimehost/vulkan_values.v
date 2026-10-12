// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidrun
import buildcore
import gamehost
import json2
import os
import crypto.sha256

pub fn load_mesa_inputs(root string) !map[string]json2.Any {
	file := root + '/build-support/dota2/mesa/inputs.json'
	raw := os.read_file(file)!
	buildcore.validate_mesa(policy_value(androidrun.load_json(raw)!), file)!
	return json2.decode[json2.Any](raw)!.as_map()
}

pub fn load_glibc_pin(root string) !map[string]json2.Any {
	file := root + '/build-support/dota2/glibc-package.json'
	raw := os.read_file(file)!
	buildcore.validate_glibc(policy_value(androidrun.load_json(raw)!), file)!
	return json2.decode[json2.Any](raw)!.as_map()
}

fn decoded_policy(value json2.Any) !buildcore.Value {
	return policy_value(androidrun.load_json(json2.encode(value))!)
}

pub fn glibc_valid(root string, pin json2.Any, alias_policy string) !bool {
	raw := os.read_file(root + '/.vinix-dota2-glibc-package.json') or { return false }
	marker := androidrun.load_json(raw) or { return false }
	policy := decoded_policy(pin) or { return false }
	return buildcore.glibc_valid(root, policy_value(marker), policy, alias_policy, [
		'ld-linux-x86-64.so.2',
		'libc.so.6',
		'libm.so.6',
		'libresolv.so.2',
		'libpthread.so.0',
		'libdl.so.2',
	])
}

pub fn validate_glibc(value json2.Any) ! {
	buildcore.validate_glibc(decoded_policy(value)!, 'glibc-package.json')!
}

fn driver_valid(root string, expected json2.Any, venus bool) bool {
	marker_name := if venus { '.vinix-dota2-venus.json' } else { '.vinix-dota2-lavapipe.json' }
	raw := os.read_file(root + '/' + marker_name) or { return false }
	marker := androidrun.load_json(raw) or { return false }
	inputs := decoded_policy(expected) or { return false }
	library := 'usr/lib/x86_64-linux-gnu/' + if venus {
		'libvulkan_virtio.so'
	} else {
		'libvulkan_lvp.so'
	}
	icd := if venus { 'usr/share/vulkan/icd.d/virtio_icd.x86_64.json' } else { '' }
	return buildcore.driver_valid(root, policy_value(marker), inputs, library, icd)
}

pub fn venus_patches(root string) ![]string {
	return [root + '/build-support/venus/vinix.patch',
		root + '/build-support/dota2/venus/x86-relax.patch',
		root + '/build-support/dota2/venus/promoted-dynamic-state.patch']
}

fn base_identity(base string) !string {
	mut records := ''
	for directory in ['lib/x86_64-linux-gnu', 'usr/lib/x86_64-linux-gnu', 'usr/lib/gcc/x86_64-linux-gnu'] {
		mut names := gamehost.files(base + '/' + directory)!
		names.sort()
		for path in names {
			relative := path[base.trim_right('/').len + 1..]
			if os.is_link(path) {
				records += relative + ' -> ' + os.readlink(path)! + '\n'
			} else if os.is_file(path) {
				records += relative + ' ' + os.file_size(path).str() + '\n'
			}
		}
	}
	return sha256.hexhash(records)
}
