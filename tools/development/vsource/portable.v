// SPDX-License-Identifier: GPL-2.0-or-later
module vsource

fn replace_one(source string, anchor string, replacement string) !string {
	if source.count(anchor) != 1 {
		return error('unsupported V source layout for portable bootstrap')
	}
	return source.replace_once(anchor, replacement)
}

// Exported installations have no .git and move away from their build path.
// Keep these adaptations in V source, before compiler translation, and record
// the original and resulting source hashes in the staging receipt.
pub fn portable_pref(source string) !string {
	anchor := 'fn detect_vroot() string {\n\tbaked_root := @VMODROOT\n\tif baked_root.len > 0 {\n\t\treturn baked_root\n\t}'
	replacement := 'fn detect_vroot() string {\n' +
		"\tif selected := os.getenv_opt('VINIX_V_ROOT') {\n" +
		"\t\tif !os.is_abs_path(selected) || !os.is_dir(os.join_path(selected, 'vlib', 'builtin')) {\n" +
		"\t\t\tpanic('VINIX_V_ROOT must name an absolute V installation root')\n\t\t}\n" +
		'\t\treturn os.real_path(selected)\n\t}\n' +
		'\texecutable_root := detect_vroot_from(os.real_path(os.executable()))\n' +
		'\tif executable_root.len > 0 { return executable_root }\n' +
		'\tbaked_root := @VMODROOT\n' +
		"\tif baked_root.len > 0 && os.is_dir(os.join_path(baked_root, 'vlib', 'builtin')) {\n" +
		'\t\treturn baked_root\n\t}'
	return replace_one(source, anchor, replacement)
}

pub fn stamped_builtin(source string, revision string) !string {
	if revision.len !in [40, 64] || !revision.bytes().all(it.is_hex_digit()) {
		return error('V bootstrap needs a full Git revision')
	}
	return replace_one(source, 'pub fn vcurrent_hash() string {\n\treturn @VCURRENTHASH\n}',
		"pub fn vcurrent_hash() string {\n\treturn '${revision[..7]}'\n}")
}

pub fn stamped_cli(source string, revision string) !string {
	if revision.len !in [40, 64] || !revision.bytes().all(it.is_hex_digit()) {
		return error('V bootstrap needs a full Git revision')
	}
	anchor := "println('V \${v_version} \${@VCURRENTHASH}')"
	if source.count(anchor) != 1 { return error('unsupported V CLI version source') }
	return source.replace('\${@VCURRENTHASH}', revision[..7])
}

// Assertions stay enabled. Reproducible builds report project source paths
// relative to their working directory; explicit #line filenames keep their
// requested meaning, and sources outside the project keep their full path.
pub fn reproducible_assert_sources(source string) !string {
	anchor := '\tposition := file.logical_position_at(start)\n\treturn AssertSourceDetail{\n\t\tfile:       position.filename'
	replacement := '\tposition := file.logical_position_at(start)\n' +
		'\tmut diagnostic_file := position.filename\n' +
		"\tif os.getenv('SOURCE_DATE_EPOCH').len > 0 && diagnostic_file == file.name {\n" +
		"\t\tproject_prefix := os.getwd().trim_right('/') + '/'\n" +
		'\t\tif diagnostic_file.starts_with(project_prefix) {\n' +
		'\t\t\tdiagnostic_file = diagnostic_file[project_prefix.len..]\n' +
		'\t\t}\n\t}\n' +
		'\treturn AssertSourceDetail{\n\t\tfile:       diagnostic_file'
	return replace_one(source, anchor, replacement)
}
