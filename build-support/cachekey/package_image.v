// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import crypto.sha256
import tools.packages.imageinputs

const package_image_variables = [imageinputs.configuration, imageinputs.repositories, imageinputs.applications]!
const package_image_labels = ['image package configuration', 'image package repository', 'image application requirements']!

fn package_image_paths(architecture string, env map[string]string) ![]string {
	mut paths := []string{cap: package_image_variables.len}
	for index, variable in package_image_variables {
		path := imageinputs.environment_path(env, variable, architecture)
		if path.contains('\x00') { return error('embedded null byte in ${package_image_labels[index]} path') }
		// Preserve the leaf so a symlink cannot reuse the key of a reviewed file
		// or directory. The repository reader strips trailing slashes before admission.
		if path == '' { continue }
		leaf := if variable == imageinputs.repositories { path.trim_right('/') } else { path }
		paths << if leaf == '' { '/' } else { leaf }
	}
	return paths
}

pub fn package_image_key(architecture string, env map[string]string) !string {
	if architecture !in ['aarch64', 'x86_64']! { return error('unsupported image package architecture') }
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-package-image-key-v1')
	add_field(mut digest, architecture)
	for variable in package_image_variables {
		add_field(mut digest, imageinputs.environment_path(env, variable, architecture))
	}
	for index, path in package_image_paths(architecture, env)! {
		hash_path(mut digest, path, 'input-' + index.str(), false)!
	}
	return digest.sum([]u8{}).hex()
}
