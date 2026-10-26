// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import compress.szip
import encoding.utf8
import os

const manifest_limit = 4 * 1024 * 1024
const absent = u32(0xffffffff)
const android_namespace = 'http://schemas.android.com/apk/res/android'

fn le16(data []u8, at int) u16 {
	return u16(data[at]) | u16(data[at + 1]) << 8
}

fn le32(data []u8, at int) u32 {
	return u32(le16(data, at)) | u32(le16(data, at + 2)) << 16
}

fn pool_length(data []u8, at int, utf8_pool bool) !(int, int) {
	if at < 0 || at >= data.len { return error('truncated manifest string length') }
	if utf8_pool {
		if data[at] & 0x80 == 0 { return int(data[at]), at + 1 }
		if at + 2 > data.len { return error('truncated manifest string length') }
		return int(data[at] & 0x7f) << 8 | int(data[at + 1]), at + 2
	}
	if at + 2 > data.len { return error('truncated manifest string length') }
	first := le16(data, at)
	if first & 0x8000 == 0 { return int(first), at + 2 }
	if at + 4 > data.len { return error('truncated manifest string length') }
	return int(first & 0x7fff) << 16 | int(le16(data, at + 2)), at + 4
}

fn string_pool(data []u8, header int) ![]string {
	if header < 28 || data.len < header { return error('invalid manifest string pool header') }
	count, styles := int(le32(data, 8)), int(le32(data, 12))
	flags := le32(data, 16)
	start, style_start := int(le32(data, 20)), int(le32(data, 24))
	if count < 0 || count > 65536 || styles != 0 || style_start != 0 || flags & ~u32(0x101) != 0
		|| start < header + count * 4 || start > data.len {
		return error('invalid manifest string pool bounds or styles')
	}
	utf8_pool := flags & 0x100 != 0
	mut result := []string{cap: count}
	mut accepted := false
	defer { if !accepted { unsafe { result.free() } } }
	mut decoded_bytes := 0
	for i in 0 .. count {
		offset := int(le32(data, header + i * 4))
		if offset < 0 || offset >= data.len - start { return error('manifest string offset out of bounds') }
		value, weight := manifest_pool_string(data, start + offset, utf8_pool, manifest_limit * 4 - decoded_bytes)!
		decoded_bytes += weight
		// Appending to []string clones the string; release the decoder's copy.
		result << value
		unsafe { value.free() }
	}
	accepted = true
	return result
}

fn manifest_pool_string(data []u8, offset int, utf8_pool bool, remaining int) !(string, int) {
	units, next := pool_length(data, offset, utf8_pool)!
	mut at := next
	if utf8_pool {
		bytes, content := pool_length(data, at, true)!
		at = content
		if bytes >= data.len - at || data[at + bytes] != 0 {
			return error('unterminated manifest UTF-8 string')
		}
		if bytes > remaining {
			return error('manifest decoded strings exceed limit')
		}
		value := data[at..at + bytes].bytestr()
		mut accepted := false
		defer { if !accepted { unsafe { value.free() } } }
		if !utf8.validate_str(value) || value.contains('\x00') {
			return error('invalid manifest UTF-8')
		}
		mut actual_units := 0
		for i in 0 .. value.len {
			if value[i] & 0xc0 != 0x80 { actual_units += if value[i] & 0xf8 == 0xf0 { 2 } else { 1 } }
		}
		if actual_units != units { return error('manifest UTF-8 length mismatch') }
		accepted = true
		return value, bytes
	} else {
		if units > (data.len - at - 2) / 2 || at + 2 > data.len
			|| le16(data, at + units * 2) != 0 {
			return error('unterminated manifest UTF-16 string')
		}
		if units > remaining / 3 {
			return error('manifest decoded strings exceed limit')
		}
		mut points := []rune{cap: units}
		defer { unsafe { points.free() } }
		end := at + units * 2
		for at < end {
			first := u32(le16(data, at))
			at += 2
			if first == 0 { return error('embedded null in manifest string') }
			if first >= 0xd800 && first <= 0xdbff {
				if at >= end { return error('unpaired manifest UTF-16 surrogate') }
				second := u32(le16(data, at))
				at += 2
				if second < 0xdc00 || second > 0xdfff {
					return error('invalid manifest UTF-16 surrogate')
				}
				points << rune(0x10000 + ((first - 0xd800) << 10) + second - 0xdc00)
			} else if first >= 0xdc00 && first <= 0xdfff {
				return error('unpaired manifest UTF-16 surrogate')
			} else {
				points << rune(first)
			}
		}
		return points.string(), units * 3
	}
}

fn pool_value(pool []string, index u32, optional bool) !string {
	if index == absent && optional { return '' }
	if index >= u32(pool.len) { return error('invalid manifest string reference') }
	return pool[int(index)]
}

fn class_name(value string, package_name string) !string {
	full := if value.starts_with('.') {
		package_name + value
	} else if !value.contains('.') {
		package_name + '.' + value
	} else {
		value
	}
	if full.len == 0 || full.len > 2048 { return error('invalid Activity class name') }
	for segment in full.split('.') {
		if segment == '' || !(segment[0].is_letter() || segment[0] in [`_`, `$`])
			|| !segment.bytes().all(it.is_letter() || it.is_digit() || it in [`_`, `$`]) {
			return error('invalid Activity class name')
		}
	}
	return full
}

struct XmlName {
	namespace string
	name      string
}

struct Namespace {
	prefix u32
	uri    u32
	depth  int
}

fn namespace_bound(namespaces []Namespace, pool []string, value string) bool {
	if value == '' { return true }
	for item in namespaces { if pool[int(item.uri)] == value { return true } }
	return false
}

// Parse the complete document before accepting a declaration. Matching text in
// an alias, a foreign namespace or a malformed suffix cannot authorize launch.
fn verify_xml(data []u8, expected_package string, expected_class string) ! {
	if data.len < 8 || data.len > manifest_limit || le16(data, 0) != 3
		|| le16(data, 2) != 8 || int(le32(data, 4)) != data.len {
		return error('invalid binary Android manifest')
	}
	if expected_package == '' || expected_package.len > 1024
		|| class_name(expected_package + '.Check', expected_package)! != expected_package + '.Check' {
		return error('invalid expected manifest package')
	}
	target := class_name(expected_class, expected_package)!
	mut pool := []string{}
	mut has_pool := false
	mut resources := []u32{}
	mut has_resources := false
	mut nodes_started := false
	mut stack := []XmlName{}
	mut namespaces := []Namespace{}
	mut roots := 0
	mut applications := 0
	mut activities := map[string]bool{}
	mut found := false
	mut attribute_bytes := 0
	mut cursor := 8
	for cursor < data.len {
		if data.len - cursor < 8 { return error('truncated manifest chunk') }
		kind, header := le16(data, cursor), int(le16(data, cursor + 2))
		size := int(le32(data, cursor + 4))
		if header < 8 || size < header || size > data.len - cursor || size % 4 != 0 {
			return error('invalid manifest chunk bounds')
		}
		chunk := data[cursor..cursor + size]
		if kind == 1 {
			if has_pool || nodes_started || has_resources {
				return error('misplaced manifest string pool')
			}
			pool = string_pool(chunk, header)!
			has_pool = true
		} else if kind == 0x180 {
			if !has_pool || has_resources || nodes_started || header != 8 || (size - 8) / 4 > pool.len {
				return error('invalid manifest resource map')
			}
			for at := 8; at < size; at += 4 { resources << le32(chunk, at) }
			has_resources = true
		} else {
			if !has_pool || header != 16 || size < 24 { return error('invalid manifest XML node') }
			_ := pool_value(pool, le32(chunk, 12), true)!
			nodes_started = true
			match kind {
				0x100, 0x101 {
					if size != 24 { return error('invalid manifest namespace node') }
					prefix, uri := le32(chunk, 16), le32(chunk, 20)
					_ := pool_value(pool, prefix, true)!
					if pool_value(pool, uri, false)! == '' {
						return error('empty manifest namespace URI')
					}
					if kind == 0x100 {
						if namespaces.len >= 256 || roots > 0 && stack.len == 0 {
							return error('misplaced manifest namespace')
						}
						for scope in namespaces {
							if scope.depth == stack.len && scope.prefix == prefix {
								return error('duplicate manifest namespace prefix')
							}
						}
						namespaces << Namespace{prefix, uri, stack.len}
					} else {
						if namespaces.len == 0 { return error('unmatched manifest namespace end') }
						last := namespaces.last()
						if last.prefix != prefix || last.uri != uri || last.depth != stack.len {
							return error('mismatched manifest namespace end')
						}
						namespaces.delete_last()
					}
				}
				0x102 {
					if size < 36 || stack.len >= 256 {
						return error('invalid manifest element start')
					}
					name := XmlName{pool_value(pool, le32(chunk, 16), true)!, pool_value(pool, le32(chunk, 20), false)!}
					if name.name == '' || !namespace_bound(namespaces, pool, name.namespace) {
						return error('unbound manifest element namespace')
					}
					start, stride, count := int(le16(chunk, 24)), int(le16(chunk, 26)), int(le16(chunk, 28))
					if start < 20 || stride != 20 || count > 4096 || 16 + start > size
						|| count > (size - 16 - start) / stride {
						return error('invalid manifest attribute bounds')
					}
					for at in [30, 32, 34] {
						if int(le16(chunk, at)) > count {
							return error('invalid manifest attribute index')
						}
					}
					mut attributes := map[string]string{}
					for i in 0 .. count {
						at := 16 + start + i * stride
						ns := pool_value(pool, le32(chunk, at), true)!
						index := le32(chunk, at + 4)
						attribute := pool_value(pool, index, false)!
						if attribute == '' || !namespace_bound(namespaces, pool, ns) {
							return error('unbound manifest attribute namespace')
						}
						if ns.len + attribute.len + 1 > manifest_limit * 4 - attribute_bytes {
							return error('manifest decoded attribute names exceed limit')
						}
						attribute_bytes += ns.len + attribute.len + 1
						key := ns + '\x00' + attribute
						if key in attributes { return error('duplicate manifest attribute') }
						if le16(chunk, at + 12) != 8 || chunk[at + 14] != 0 {
							return error('invalid manifest typed value')
						}
						type_id := chunk[at + 15]
						if type_id > 8 && !(type_id >= 0x10 && type_id <= 0x1f) {
							return error('unsupported manifest typed value')
						}
						raw := le32(chunk, at + 8)
						mut value := pool_value(pool, raw, true)!
						if type_id == 3 {
							typed := pool_value(pool, le32(chunk, at + 16), false)!
							if raw != absent && value != typed {
								return error('inconsistent manifest string attribute')
							}
							value = typed
						} else if key in ['\x00package', android_namespace + '\x00name'] {
							return error('manifest component identity must be a literal string')
						}
						if ns == android_namespace && attribute == 'name' && int(index) < resources.len
							&& resources[int(index)] != 0 && resources[int(index)] != 0x01010003 {
							return error('manifest android:name resource ID mismatch')
						}
						attributes[key] = value
					}
					if stack.len == 0 {
						roots++
						if roots != 1 || name != XmlName{'', 'manifest'}
							|| (attributes['\x00package'] or { '' }) != expected_package {
							return error('manifest package does not match pinned package')
						}
					} else if stack.len == 1 && name == XmlName{'', 'application'} {
						applications++
						if applications != 1 { return error('duplicate manifest application') }
					} else if stack.len == 2 && stack[1] == XmlName{'', 'application'}
						&& name == XmlName{'', 'activity'} {
						declared := class_name(attributes[android_namespace + '\x00name'] or { '' }, expected_package)!
						if declared in activities { return error('duplicate manifest Activity') }
						activities[declared] = true
						if declared == target { found = true }
					}
					stack << name
				}
				0x103 {
					if size != 24 || stack.len == 0 {
						return error('unmatched manifest element end')
					}
					name := XmlName{pool_value(pool, le32(chunk, 16), true)!, pool_value(pool, le32(chunk, 20), false)!}
					if stack.last() != name { return error('mismatched manifest element end') }
					stack.delete_last()
					for scope in namespaces {
						if scope.depth > stack.len {
							return error('unclosed manifest namespace scope')
						}
					}
				}
				0x104 {
					if size != 28 || stack.len == 0 || le16(chunk, 20) != 8 || chunk[22] != 0 {
						return error('invalid manifest text node')
					}
					_ := pool_value(pool, le32(chunk, 16), false)!
					if chunk[23] > 8 && !(chunk[23] >= 0x10 && chunk[23] <= 0x1f) {
						return error('unsupported manifest text value')
					}
					if chunk[23] == 3 { _ := pool_value(pool, le32(chunk, 24), false)! }
				}
				else { return error('unsupported manifest chunk') }
			}
		}
		cursor += size
	}
	if roots != 1 || applications != 1 || stack.len != 0 || namespaces.len != 0 || !found {
		return error('pinned Activity is not declared in the APK manifest')
	}
}

// Only a bounded, unique root manifest entry is read; archive paths are never
// extracted to disk. Package/APK/certificate authentication remains the caller's.
pub fn verify_activity(apk string, expected_package string, expected_class string) ! {
	if os.file_size(apk) > 1024 * 1024 * 1024 {
		return error('APK exceeds manifest verification size limit')
	}
	mut archive := szip.open(apk, .no_compression, .read_only)!
	defer { archive.close() }
	count := archive.total()!
	if count > 65536 { return error('APK has too many ZIP entries') }
	mut manifest := []u8{}
	mut seen := false
	for i in 0 .. count {
		archive.open_entry_by_index(i)!
		if archive.name() != 'AndroidManifest.xml' {
			archive.close_entry()
			continue
		}
		if seen || archive.size() < 8 || archive.size() > u64(manifest_limit) {
			archive.close_entry()
			return error('APK manifest must be unique and bounded')
		}
		seen = true
		manifest = []u8{len: int(archive.size())}
		read := archive.read_entry_buf(manifest.data, manifest.len) or {
			archive.close_entry()
			return err
		}
		archive.close_entry()
		if read != manifest.len { return error('truncated APK manifest ZIP entry') }
	}
	if !seen { return error('APK has no AndroidManifest.xml') }
	verify_xml(manifest, expected_package, expected_class)!
}
