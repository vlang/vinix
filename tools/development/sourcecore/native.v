// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecore

fn native_source(path string) bool {
	return (path.ends_with('.v') && !path.ends_with('_test.v')) || path.ends_with('.h')
		|| path.ends_with('/v.mod')
}

// Native development builds compile the real package CLI alongside the base
// utilities. Keep its imported repository modules in the committed source tree;
// neither a host checkout nor an installed module cache is a build input.
pub fn export_native_userland(root string, commit string, destination string) ! {
	export(root, commit, ['util-vinix', 'init', 'tools/packages/main.v',
		'tools/packages/pkgcore', 'tools/packages/pkgprotocol', 'tools/packages/signing',
		'tools/packages/pkgadmin', 'tools/packages/pkglaunch', 'tools/packages/appsdk',
		'tools/packages/x11auth', 'tools/packages/audiopcm', 'tools/accounts/authclient',
		'tools/accounts/authproto', 'compat/ios/plist'], destination, native_source)!
}

pub fn native_package_module_path(work string) string {
	return '@vlib|' + work + '|' + work + '/tools/accounts'
}
