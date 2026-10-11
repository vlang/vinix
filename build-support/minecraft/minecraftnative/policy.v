// SPDX-License-Identifier: GPL-2.0-or-later
module minecraftnative

import json2

pub const manifest_url = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
pub const maven_url = 'https://repo1.maven.org/maven2'
pub const assets_url = 'https://resources.download.minecraft.net'

pub fn field(value json2.Any, name string) !json2.Any {
	if value !is map[string]json2.Any { return error('Expected JSON object for ' + name) }
	return value[name] or { return error('Missing JSON field ' + name) }
}

pub fn optional(value json2.Any, name string, fallback json2.Any) json2.Any {
	if value !is map[string]json2.Any { return fallback }
	return value[name] or { fallback }
}

pub fn text(value json2.Any) !string {
	if value is string { return value }
	return error('Expected JSON string')
}

pub fn items(value json2.Any) ![]json2.Any {
	if value is []json2.Any { return value }
	return error('Expected JSON array')
}

pub fn rule_matches(rule json2.Any, features map[string]bool) !bool {
	os_clause := optional(rule, 'os', json2.Any(map[string]json2.Any{}))
	for name, expected in {
		'name': 'linux'
		'arch': 'arm64'
	} {
		if actual := os_clause.as_map()[name] {
			if text(actual)! != expected { return false }
		}
	}
	if 'version' in os_clause.as_map() || 'versionRange' in os_clause.as_map() { return false }
	for name, wanted in optional(rule, 'features', json2.Any(map[string]json2.Any{})).as_map() {
		if wanted !is bool { return error('Expected boolean feature ' + name) }
		if features[name] != wanted { return false }
	}
	return true
}

pub fn rule_allows(rules json2.Any, features map[string]bool) !bool {
	if rules is json2.Null { return true }
	rows := items(rules)!
	if rows.len == 0 { return true }
	mut allowed := !rows.any(optional(it, 'action', json2.Any('')).str() == 'allow')
	for rule in rows {
		if rule_matches(rule, features)! {
			allowed = optional(rule, 'action', json2.Any('')).str() == 'allow'
		}
	}
	return allowed
}

pub fn flatten_arguments(raw json2.Any, features map[string]bool) ![]string {
	mut result := []string{}
	for value in items(raw)! {
		if value is string {
			result << value
			continue
		}
		if !rule_allows(optional(value, 'rules', json2.Any(json2.Null{})), features)! { continue }
		data := optional(value, 'value', json2.Any([]json2.Any{}))
		if data is string {
			result << data
		} else {
			for entry in items(data)! { result << text(entry)! }
		}
	}
	return result
}

pub fn shell_quote(value string) string { return "'" + value.replace("'", "'\\''") + "'" }

pub fn maven_path(coordinate string) !string {
	parts := coordinate.split(':')
	if parts.len !in [3, 4] || parts.any(it == '' || it.contains('/') || it.contains('\\') || it == '..') {
		return error('Invalid Maven coordinate: ' + coordinate)
	}
	return parts[0].replace('.', '/') + '/' + parts[1] + '/' + parts[2] + '/' + parts[1] + '-' + parts[2] + if parts.len == 4 {
		'-' + parts[3] + '.jar'
	} else {
		'.jar'
	}
}

pub fn safe_relative(path string) !string {
	if path == '' || path.starts_with('/') || path.contains('\\') || path.contains('\x00') || path.split('/').any(it in ['',
		'.', '..']) {
		return error('Unsafe download path: ' + path)
	}
	return path
}

fn java_major(version json2.Any) int {
	return optional(optional(version, 'javaVersion', json2.Any(map[string]json2.Any{})), 'majorVersion', json2.Any(8)).int()
}

pub fn (source Source) fetch_version(entry json2.Any) !json2.Any {
	data := source.fetch(text(field(entry, 'url')!)!)!
	expected := text(field(entry, 'sha1')!)!
	if digest(data) != expected {
		return error('version manifest checksum mismatch for ' + text(field(entry, 'id')!)!)
	}
	return json2.decode[json2.Any](data.bytestr())!
}

pub fn (source Source) resolve_version(requested string, maximum ?int) !(string, json2.Any) {
	println('=== resolving Minecraft ' + requested + ' ===')
	manifest := json2.decode[json2.Any](source.fetch(source.manifest)!.bytestr())!
	mut version_id := requested
	if requested in ['release', 'snapshot'] {
		if limit := maximum {
			for entry in items(field(manifest, 'versions')!)! {
				if optional(entry, 'type', json2.Any('')).str() != requested { continue }
				version := source.fetch_version(entry)!
				if java_major(version) <= limit {
					version_id = text(field(entry, 'id')!)!
					println('  newest ' + requested + ' for Java ' + limit.str() + ' resolves to ' + version_id + ' (Java ' + java_major(version).str() + ')')
					return version_id, version
				}
			}
			return error('no Minecraft ' + requested + ' supports Java ' + limit.str() + ' or older')
		} else {
			version_id = text(field(field(manifest, 'latest')!, requested)!)!
			println('  latest ' + requested + ' resolves to ' + version_id)
		}
	}
	for entry in items(field(manifest, 'versions')!)! {
		if text(field(entry, 'id')!)! != version_id { continue }
		version := source.fetch_version(entry)!
		if limit := maximum {
			if java_major(version) > limit {
				return error('Minecraft ' + version_id + ' needs Java ' + java_major(version).str() + '; the selected runtime supports up to Java ' + limit.str())
			}
		}
		return version_id, version
	}
	return error('unknown Minecraft version: ' + version_id)
}
