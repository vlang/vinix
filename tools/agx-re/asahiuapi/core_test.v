// SPDX-License-Identifier: MIT
module asahiuapi

fn test_nested_structs_arrays_and_native_oracle() {
	header := '#define DRM_ASAHI_MAX_CLUSTERS 64\n/* struct drm_asahi_spoof { __u32 a; }; */\n' +
		'struct drm_asahi_one {\n __u32 word;\n};\nstruct drm_asahi_two {\n struct drm_asahi_one item;\n __u64 masks[DRM_ASAHI_MAX_CLUSTERS];\n};\n'
	parsed := records(header)!
	assert parsed.len == 2 && parsed[1].fields[1].count == 64
	generated := generate(header)!
	assert generated.contains('pub struct Two') && generated.contains('masks [64]u64')
	check := oracle(header)!
	assert check.contains('sizeof(asahi.Two) == sizeof(C.drm_asahi_two)')
	assert check.contains('__offsetof(asahi.Two, masks) == __offsetof(C.drm_asahi_two, masks)')
}

fn test_unknown_or_malformed_declarations_fail() {
	for text in ['struct drm_asahi_empty {\n};', 'struct drm_asahi_a {\n void *ptr;\n};',
		'struct drm_asahi_a {\n __u32 a[UNKNOWN];\n};', 'struct drm_asahi_a {\n __u32 a;\n',
		'/* unclosed', 'struct drm_asahi_a {\n __u32 a;\n __u32 a;\n};'] {
		if _ := records(text) {
			assert false, 'accepted malformed UAPI'
		}
	}
}
