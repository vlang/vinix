// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn configuration_field(parent string, key string) bool {
	return match parent {
		'' { key in ['format', 'architecture', 'repositories', 'policy', 'launch_user']! }
		'repositories' { key in ['id', 'url', 'public_key']! }
		'policy' { policy_field(key) }
		'pins' { key in ['id', 'minimum', 'before']! }
		else { false }
	}
}

fn configuration_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		if key == 'format' { return token == `-` || (token >= `0` && token <= `9`) }
		if key == 'repositories' { return token == `[` }
		if key == 'policy' { return token == `{` }
	} else if parent == 'policy' {
		if key in ['offline', 'allow_firmware']! { return token in [u8(`t`), `f`]! }
		if key == 'reserve_bytes' { return token == `-` || (token >= `0` && token <= `9`) }
		return token == `[`
	}
	return token == `"`
}

// Legacy configuration permits omitted defaults, including partial policies.
// Explicit values must keep their type and spelling: an ignored policy typo
// must never silently become the default permissions or unrestricted allowlist.
fn decode_configuration(text string) !Config {
	return read_stored_configuration(text)
}

// Only independently JSON-decoded configurations own these allocations.
// Service overlays and plans can borrow them and must not call this helper.
fn close_decoded_configuration(config Config) {
	unsafe {
		config.architecture.free(); config.launch_user.free()
		for repository in config.repositories {
			repository.id.free(); repository.url.free(); repository.public_key.free()
		}
		(&array(&config.repositories)).free()
	}
	close_owned_policy(config.policy)
}
