module vsource

fn test_portable_bootstrap_requires_exact_source_and_stamps_revision() {
	pref := 'module pref\nfn detect_vroot() string {\n\tbaked_root := @VMODROOT\n\tif baked_root.len > 0 {\n\t\treturn baked_root\n\t}\n\treturn detect_vroot_from(os.getwd())\n}\n'
	patched := portable_pref(pref)!
	executable := patched.index('executable_root :=') or { panic('missing executable lookup') }
	baked := patched.index('baked_root :=') or { panic('missing source fallback') }
	assert executable < baked
	assert patched.contains("os.is_dir(os.join_path(baked_root, 'vlib', 'builtin'))")
	assert patched.ends_with('return detect_vroot_from(os.getwd())\n}\n')
	for unsupported in ['', pref + pref] {
		if _ := portable_pref(unsupported) {
			assert false, 'unknown/ambiguous source must be refused'
		}
	}
	builtin := 'module builtin\npub fn vcurrent_hash() string {\n\treturn @VCURRENTHASH\n}\n'
	assert stamped_builtin(builtin, 'f6358ec' + '0'.repeat(33))! ==
		"module builtin\npub fn vcurrent_hash() string {\n\treturn 'f6358ec'\n}\n"
	for invalid in ['f6358ec', 'z'.repeat(40), "'".repeat(40)] {
		if _ := stamped_builtin(builtin, invalid) {
			assert false, 'invalid revision must be refused'
		}
	}
	cli := "fn main() { println('V \${v_version} \${@VCURRENTHASH}') }"
	assert stamped_cli(cli, 'f6358ec' + '0'.repeat(33))! == "fn main() { println('V \${v_version} f6358ec') }"
	if _ := stamped_cli('fn main() {}', 'f6358ec' + '0'.repeat(33)) {
		assert false
	}
}
