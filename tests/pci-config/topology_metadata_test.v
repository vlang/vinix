module main

fn minimal_metadata_source() string {
	mut declarations := ''
	for name in ['Topology', 'TopologyBus', 'TopologyFunction', 'CapabilityInfo'] {
		declaration := 'typedef struct pci__' + name + ' pci__' + name + ';\n'
		declarations += declaration + declaration
	}
	return declarations + 'struct multi_return_u32_i64 {\n u32 arg0;\n i64 arg1;\n};\n' +
		'int pci__topology_build(void) {\n if (nested()) {\n  return 1;\n }\n return 0;\n}\n' +
		'void pci__topology_destroy(void) {\n}\nint pci__capabilities_read(void) {\n return 0;\n}\n' +
		'int pci__checked_config_read(void) {\n return 0;\n}\n'
}

fn test_metadata_preserves_complete_functions_and_nested_blocks() {
	raw := minimal_metadata_source()
	compiled, metadata := compiler_metadata(raw)!
	assert bodies(raw) == bodies(compiled)
	assert bodies(compiled).len == 4
	assert bodies(compiled)[0].contains('if (nested()) {\n  return 1;')
	assert metadata['removed_second_identical_forward_typedefs'].as_array().len == 4
}

fn test_rejects_native_tuple_type_or_field_changes() {
	raw := minimal_metadata_source()
	for mutated in [raw.replace('u32 arg0;', 'u64 arg0;'), raw.replace('i64 arg1;', 'i32 arg1;'),
		raw.replace('u32 arg0;', 'u32arg0;'), raw.replace('u32 arg0;', 'u32  arg0;')] {
		compiler_metadata(mutated) or {
			assert err.msg() == 'Native V callback tuple did not retain its actual u32/i64 ABI'
			continue
		}
		assert false
	}
}

fn test_rejects_forward_inventory_and_unrelated_callbacks() {
	raw := minimal_metadata_source()
	compiler_metadata(raw + 'typedef struct pci__Topology pci__Topology;\n') or {
		assert err.msg() == 'Unexpected generated forward declaration: Topology'
		return
	}
	assert false
}

fn test_rejects_missing_production_body() {
	raw := minimal_metadata_source().replace('pci__topology_destroy(', 'other_destroy(')
	compiler_metadata(raw) or {
		assert err.msg() == 'Production code missing from actual generated bodies'
		return
	}
	assert false
}

fn test_rejects_unrelated_callback_modules() {
	for symbol in ['encoding__binary__', 'io__Reader'] {
		compiler_metadata(minimal_metadata_source() + symbol) or {
			assert err.msg() == 'Private observer stage unexpectedly acquired unrelated callback modules'
			continue
		}
		assert false
	}
}

fn test_required_names_use_original_body_search_and_word_boundaries() {
	raw := minimal_metadata_source().replace('void pci__topology_destroy(void)', 'void pci__observer(void)').replace('return 0;\n}', 'pci__topology_destroy();\n return 0;\n}')
	compiler_metadata(raw)!
	assert !named('épci__topology_destroy(', 'pci__topology_destroy')
	assert !named('_pci__topology_destroy(', 'pci__topology_destroy')
	assert named(' pci__topology_destroy(', 'pci__topology_destroy')
}

fn test_later_valid_tuple_preserves_original_search() {
	raw := minimal_metadata_source()
	compiler_metadata(raw.replace('struct multi_return_u32_i64 {', 'struct multi_return_u32_i64 { u64 wrong; };\nstruct multi_return_u32_i64 {'))!
}
