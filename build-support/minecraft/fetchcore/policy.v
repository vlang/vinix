// SPDX-License-Identifier: GPL-2.0-or-later
module fetchcore

import androidhost as ah
import json2

fn rule_matches(rule ah.Value, features ah.Value) !bool {
	os_clause := get(rule, 'os', ah.Value(map[string]ah.Value{}))!
	if compare('contains', os_clause, ah.Value('name'))! && !equal(item(os_clause, ah.Value('name'))!, constant('TARGET_OS')!)! {
		return false
	}
	if compare('contains', os_clause, ah.Value('arch'))! && !equal(item(os_clause, ah.Value('arch'))!, constant('TARGET_ARCH')!)! {
		return false
	}
	if compare('contains', os_clause, ah.Value('version'))! || compare('contains', os_clause, ah.Value('versionRange'))! {
		return false
	}
	for entry in iterable(method('items', [get(rule, 'features', ah.Value(map[string]ah.Value{}))!])!)! {
		pair := entry.items()
		wanted := item(entry, ah.Value(1))!
		if !equal(method('get', [features, pair[0], ah.Value(false)])!, wanted)! { return false }
	}
	return true
}

fn rule_allows(rules ah.Value, features ah.Value) !bool {
	if !truth(rules)! { return true }
	mut allowed := true
	for rule in iterable(rules)! {
		if equal(get(rule, 'action', null())!, ah.Value('allow'))! {
			allowed = false
			break
		}
	}
	for rule in iterable(rules)! {
		if !truth(public('rule_matches', [argument('value', rule), argument('value', features)], false)!)! {
			continue
		}
		allowed = equal(get(rule, 'action', null())!, ah.Value('allow'))!
	}
	return allowed
}

fn maven_path(coordinate ah.Value) !string {
	parts := method('split', [coordinate, ah.Value(':')])!
	group := item(parts, ah.Value(0))!
	artifact := item(parts, ah.Value(1))!
	version := item(parts, ah.Value(2))!
	classifier := if compare('gt', builtin('len', parts)!, ah.Value(3))! {
		'-' + stringify(item(parts, ah.Value(3))!)!
	} else {
		''
	}
	return method('replace', [group, ah.Value('.'), ah.Value('/')])!.text() + '/' + stringify(artifact)! + '/' + stringify(version)! + '/' + stringify(artifact)! + '-' + stringify(version)! + classifier + '.jar'
}

fn flatten(raw ah.Value, features ah.Value) ![]ah.Value {
	mut result := []ah.Value{}
	for value in iterable(raw)! {
		if value is string {
			result << value
			continue
		}
		if !truth(public('rule_allows', [
			argument('value', get(value, 'rules', null())!),
			argument('value', features),
		], false)!)! {
			continue
		}
		data := get(value, 'value', ah.Value([]ah.Value{}))!
		if data is string { result << data } else { result << iterable(data)! }
	}
	return result
}

fn shell_quote(value ah.Value) !string {
	return "'" + method('replace', [value, ah.Value("'"), ah.Value("'\\''")])!.text() + "'"
}

fn fetch_api(url ah.Value) !string {
	return public('fetch', [argument('value', url)], true)!.text()
}

fn fetch_version(entry ah.Value) !ah.Value {
	data := fetch_api(item(entry, ah.Value('url'))!)!
	actual := hash_payload(data)!
	if !equal(ah.Value(actual), item(entry, ah.Value('sha1'))!)! {
		return failed('RuntimeError', 'version manifest checksum mismatch for ' + stringify(item(entry, ah.Value('id'))!)!)
	}
	return json_load(ah.Value(data), true)!
}

fn version_api(entry ah.Value) !ah.Value {
	return public('fetch_version', [argument('value', entry)], false)!
}

fn java_major(version ah.Value) !ah.Value {
	return builtin('int', get(get(version, 'javaVersion', ah.Value(map[string]ah.Value{}))!, 'majorVersion', ah.Value(8))!)!
}

fn resolve_version(requested ah.Value, max_java ah.Value) !ah.Value {
	mut version_id := requested
	log('=== resolving Minecraft ' + stringify(version_id)! + ' ===')!
	manifest := json_load(ah.Value(fetch_api(constant('VERSION_MANIFEST')!)!), true)!
	if equal(version_id, ah.Value('release'))! || equal(version_id, ah.Value('snapshot'))! {
		channel := version_id
		if max_java is json2.Null {
			version_id = item(item(manifest, ah.Value('latest'))!, channel)!
			log('  latest ' + stringify(channel)! + ' resolves to ' + stringify(version_id)!)!
		} else {
			for entry in iterable(item(manifest, ah.Value('versions'))!)! {
				if !equal(get(entry, 'type', null())!, channel)! { continue }
				version := version_api(entry)!
				major := java_major(version)!
				if compare('le', major, max_java)! {
					log('  newest ' + stringify(channel)! + ' for Java ' + stringify(max_java)! + ' resolves to ' + stringify(item(entry, ah.Value('id'))!)! + ' (Java ' + stringify(major)! + ')')!
					return ah.Value([item(entry, ah.Value('id'))!, version])
				}
			}
			return failed('SystemExit', 'no Minecraft ' + stringify(channel)! + ' supports Java ' + stringify(max_java)! + ' or older')
		}
	}
	for entry in iterable(item(manifest, ah.Value('versions'))!)! {
		if equal(item(entry, ah.Value('id'))!, version_id)! {
			version := version_api(entry)!
			major := java_major(version)!
			if max_java !is json2.Null && compare('gt', major, max_java)! {
				return failed('SystemExit', 'Minecraft ' + stringify(version_id)! + ' needs Java ' + stringify(major)! + '; the selected runtime supports up to Java ' + stringify(max_java)!)
			}
			return ah.Value([version_id, version])
		}
	}
	return failed('SystemExit', 'unknown Minecraft version: ' + stringify(version_id)!)
}
