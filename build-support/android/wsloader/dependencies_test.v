module wsloader

struct LookupNode {
mut:
	dynamic &DynamicEntry = unsafe { nil }
	symbol [24]u8
}

fn node_lookup(node voidptr, name &char) voidptr {
	unsafe {
		n := &LookupNode(node)
		return voidptr(&n.symbol[0])
	}
}

fn test_handle_lookup_scope_order_cycles_weak_and_undefined() {
	mut root := LookupNode{}
	mut first := LookupNode{}
	mut second := LookupNode{}
	mut deep := LookupNode{}
	mut unrelated := LookupNode{}
	// Elf64_Sym: st_info at byte 4; st_shndx at bytes 6..7.
	mut nodes := [&second, &deep, &unrelated]
	for mut node in nodes {
		node.symbol[4] = 0x12
		node.symbol[6] = 1
	}
	root.symbol[4] = 0x12 // undefined symbols cannot satisfy a lookup
	mut root_dynamic := [DynamicEntry{ tag: 1, value: usize(&first) },
		DynamicEntry{ tag: 1, value: usize(&second) }, DynamicEntry{}]!
	mut first_dynamic := [DynamicEntry{ tag: 1, value: usize(&deep) }, DynamicEntry{}]!
	mut deep_dynamic := [DynamicEntry{ tag: 1, value: usize(&root) }, DynamicEntry{}]!
	unsafe {
		root.dynamic = &root_dynamic[0]
		first.dynamic = &first_dynamic[0]
		deep.dynamic = &deep_dynamic[0]
		mut found := voidptr(nil)
		assert lookup_dependencies(&root, c'probe', &found, 0, node_lookup) == voidptr(&second.symbol[0])
		assert found == voidptr(&second) // breadth first, ahead of deep
		second.symbol[6] = 0
		deep.symbol[4] = 0x22 // weak definition
		assert lookup_dependencies(&root, c'probe', &found, 0, node_lookup) == voidptr(&deep.symbol[0])
		assert found == voidptr(&deep)
		deep.symbol[6] = 0
		assert lookup_dependencies(&root, c'probe', &found, 0, node_lookup) == nil
		assert found == nil // unrelated's definition never enters this scope
		root.symbol[6] = 1
		assert lookup_dependencies(&root, c'probe', &found, 0, node_lookup) == voidptr(&root.symbol[0])
		assert found == voidptr(&root)
	}
}
