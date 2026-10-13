module vsource

fn test_portable_bootstrap_requires_exact_source_and_stamps_revision() {
	pref := 'module pref\nfn detect_vroot() string {\n\tbaked_root := @VMODROOT\n\tif baked_root.len > 0 {\n\t\treturn baked_root\n\t}\n\treturn detect_vroot_from(os.getwd())\n}\n'
	patched := portable_pref(pref)!
	executable := patched.index('executable_root :=') or { panic('missing executable lookup') }
	baked := patched.index('baked_root :=') or { panic('missing source fallback') }
	assert executable < baked
	selected := patched.index("os.getenv_opt('VINIX_V_ROOT')") or { panic('missing explicit root lookup') }
	assert selected < executable
	assert patched.contains('!os.is_abs_path(selected)')
	assert patched.contains('return os.real_path(selected)')
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

fn test_reproducible_assert_sources_require_one_exact_generator_anchor() {
	source := '\tposition := file.logical_position_at(start)\n\treturn AssertSourceDetail{\n\t\tfile:       position.filename\n\t\tline:       position.line\n\t\texpression: expression\n\t}\n'
	patched := reproducible_assert_sources(source)!
	assert patched.contains("os.getenv('SOURCE_DATE_EPOCH').len > 0 && diagnostic_file == file.name")
	assert patched.contains("project_prefix := os.getwd().trim_right('/') + '/'")
	assert patched.contains('diagnostic_file.starts_with(project_prefix)')
	assert patched.ends_with('\n\t\tline:       position.line\n\t\texpression: expression\n\t}\n')
	for unsupported in ['', source + source, source.replace('position.filename', 'file.name')] {
		if _ := reproducible_assert_sources(unsupported) {
			assert false, 'unknown/ambiguous assertion source must be refused'
		}
	}
}
