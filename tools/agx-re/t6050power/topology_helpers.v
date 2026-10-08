module t6050power

import appleadt as a
import traceanalysis as j

struct NodeMatch {
	name       string
	compatible string
	property   string
	value      string
}

// Evaluate predicates as the original preorder iterator yields each node.
// Reading every later node first could change which malformed field wins.
fn selected(node a.Node, match_spec NodeMatch) !bool {
	if match_spec.name != '' && a.node_name(node)! != match_spec.name { return false }
	if match_spec.property != '' {
		property := node.properties[match_spec.property] or { return false }
		field := if match_spec.property == 'role' { 'PMP role' } else { match_spec.property }
		if a.decode_cstring(property.data, field)! != match_spec.value { return false }
	}
	return match_spec.compatible == '' || a.compatible_with(node, match_spec.compatible)!
}

fn collect_selected(node a.Node, parent string, match_spec NodeMatch, mut result []a.Visit) ! {
	name := a.node_name(node)!
	path := if parent == '' { '/' + name } else { parent + '/' + name }
	if selected(node, match_spec)! { result << a.Visit{path, node} }
	for child in node.children { collect_selected(child, path, match_spec, mut result)! }
}

fn find_selected(root a.Node, description string, match_spec NodeMatch) !a.Visit {
	mut matches := []a.Visit{}
	collect_selected(root, '', match_spec, mut matches)!
	if matches.len != 1 {
		paths := if matches.len == 0 { 'none' } else { matches.map(it.path).join(', ') }
		return error('expected one ${description}, found: ${paths}')
	}
	return matches[0]
}

fn collect_wrappers(node a.Node, parent string, mut wrappers map[string]a.Visit) ! {
	name := a.node_name(node)!
	path := if parent == '' { '/' + name } else { parent + '/' + name }
	if property := node.properties['role'] {
		if a.compatible_with(node, 'iop,ascwrap-v6')! {
			role := a.decode_cstring(property.data, 'PMP role')!
			if role in ['PMP0', 'PMP1'] {
				if role in wrappers { return error('duplicate T6050 ${role} wrapper') }
				wrappers[role] = a.Visit{path, node}
			}
		}
	}
	for child in node.children { collect_wrappers(child, path, mut wrappers)! }
}

fn node_from_request(value j.Value) !a.Node {
	row := value.as_map()
	mut properties := map[string]a.Property{}
	for name, encoded in j.value(row, 'properties').as_map() {
		property := encoded.as_map()
		data := j.bytes_fromhex(j.string_value(j.value(j.value(property, 'data').as_map(), '$bytes')))!
		properties[name] = a.Property{data, u8(j.value(property, 'flags').u64())}
	}
	mut children := []a.Node{}
	for child in j.value(row, 'children').arr() { children << node_from_request(child)! }
	return a.Node{properties, children}
}

fn region_rows(regions []a.Region) j.Value {
	mut rows := []j.Value{}
	for index, region in regions {
		rows << j.Value(map[string]j.Value{
			'index': j.Value(index)
			'base':  j.Value(region.address)
			'size':  j.Value(region.bytes)
		})
	}
	return j.Value(rows)
}

fn region_repr(regions []a.Region) string {
	return '[' + regions.map('(${it.address}, ${it.bytes})').join(', ') + ']'
}

fn words_repr(words []u32) string { return j.string_value(j.Value(words.map(j.Value(it)))) }

fn maps_value(rows []map[string]j.Value) j.Value { return j.Value(rows.map(j.Value(it))) }

fn map_repr(rows []map[string]j.Value) string { return j.string_value(maps_value(rows)) }

fn number_fields(row map[string]j.Value, names []string) []j.Value {
	return names.map(j.value(row, it))
}

fn relative_path(path string, node a.Node, absolute string) !string {
	prefix := '/' + a.node_name(node)!
	return if path.starts_with(prefix) { absolute + path[prefix.len..] } else { path }
}

pub fn query_topology(operation string, request map[string]j.Value) !j.Value {
	root := node_from_request(j.value(request, 'root'))!
	if operation == 'recover_t6050_power' { return j.Value(recover_power_topology(root)!) }
	if operation == 'recover_t6050_pmp_darts' {
		mut wrappers := map[string]a.Visit{}
		for role, item in j.value(request, 'pmp_wrappers').as_map() {
			tuple := item.arr()
			wrappers[role] = a.Visit{j.string_value(tuple[0]), node_from_request(tuple[1])!}
		}
		return maps_value(recover_pmp_darts(root, wrappers, j.value(request, 'die_stride'))!)
	}
	return error('unknown T6050 topology operation ${operation}')
}
