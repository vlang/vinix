void fs__reap_removed(void) {
	u64 now = time__monotonic_ns();
	klock__Lock__acquire(&fs__removed_lock);
	if (((now - fs__removed_last_reap) < fs__removed_reap_interval_ns) || (fs__removed_items.len == 0)) {
		klock__Lock__release(&fs__removed_lock);
		return;
	}
	fs__removed_last_reap = now;
	i64 due = 0;
	while ((due < fs__removed_items.len) && ((now - ((*(fs__RetiredItem*)array_get(fs__removed_items, due))).at) >= fs__removed_grace_ns)) {
		due++;
	}
	if (due == 0) {
		klock__Lock__release(&fs__removed_lock);
		return;
	}
	Array items = array_new(	sizeof(fs__RetiredItem), 0, 0);
	if (due == fs__removed_items.len) {
		items = fs__removed_items;
		fs__removed_items = array_new(		sizeof(fs__RetiredItem), 0, 0);
	} else {
		Array __arr_init_0 = array_new(		sizeof(fs__RetiredItem), due, 0);
		{
			i64 __arr_idx_1 = 0;
			for (; __arr_idx_1 < __arr_init_0.len; __arr_idx_1++) {
				i64 v_index = __arr_idx_1;
				{ Array* _a0 = &__arr_init_0; int _i0 = __arr_idx_1; array__set(_a0, _i0, &(fs__RetiredItem[]){(fs__RetiredItem){.resource = (resource__Resource*)NULL, .node = NULL, .overlay_backing = NULL, .bytes = NULL, .text = (string){.str = 0}, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0), .charge = (kbudget__Charge){.kind = kbudget__Kind__file}}}); }
			}
		}
		items = __arr_init_0;
		{
			memcpy(items.data, fs__removed_items.data, (size_t)(due) * sizeof(fs__RetiredItem));
		}
		array__delete_many(&fs__removed_items, 0, due);
	}
	klock__Lock__release(&fs__removed_lock);
	Array nodes = array_new(	sizeof(void*), 0, due);
	{
		i64 __for_idx_2 = 0;
		for (; __for_idx_2 < items.len; __for_idx_2++) {
			fs__RetiredItem item = *(fs__RetiredItem*)(array_get(items, __for_idx_2));
			if (item.node != NULL) {
				void* __arr_val_3 = (void*)(item.node);
				array_push(&nodes, &__arr_val_3);
			}
		}
	}
	Array running = __new_array_noscan(nodes.len, 0, sizeof(bool));
	proc__mark_programs_in_use(nodes, &running);
	i64 v_index = 0;
	{
		i64 __for_idx_4 = 0;
		for (; __for_idx_4 < items.len; __for_idx_4++) {
			fs__RetiredItem item = *(fs__RetiredItem*)(array_get(items, __for_idx_4));
			if (item.node == NULL) {
				if (item.overlay_backing != NULL) {
					fs__overlay_release_node(item.overlay_backing);
				}
				{
					v_free(item.bytes);
				}
				{
					string__free(&item.text);
				}
				Array lower_nodes = item.lower_nodes;
				Array lower_resources = item.lower_resources;
				{
					array__free(&lower_nodes);
					array__free(&lower_resources);
				}
				if (item.resource != NULL) {
					resource__Resource* res = item.resource;
					resource__release_resource(res);
				}
				kbudget__release(item.charge);
				continue;
			}
			fs__VFSNode* node = item.node;
			bool in_use = (*(bool*)array_get(running, v_index));
			v_index++;
			if (fs__pinned(node)) {
				continue;
			}
			if (katomic__load_T_v_int(&node->overlay_refs) != 0) {
				katomic__store_T_u32(&node->retired, (u32)(0));
				if (katomic__load_T_v_int(&node->overlay_refs) == 0) {
					fs__retire_node(node);
				}
				continue;
			}
			if (katomic__load_T_v_int(&node->handles) != 0) {
				katomic__store_T_u32(&node->retired, (u32)(0));
				if (katomic__load_T_v_int(&node->handles) == 0) {
					fs__retire_node(node);
				}
				continue;
			}
			if (in_use || (katomic__load_T_v_int(&node->parent_refs) != 0)) {
				fs__retire((fs__RetiredItem){.node = node, .directory_busy = item.directory_busy, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			bool directory_busy = node->removed && proc__directory_in_use((void*)(node));
			if (directory_busy) {
				fs__retire((fs__RetiredItem){.node = node, .directory_busy = directory_busy, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			if (item.directory_busy) {
				fs__retire((fs__RetiredItem){.node = node, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			u64 released = katomic__load_T_u64(&node->directory_released);
			u64 checked_at = time__monotonic_ns();
			if (node->removed && ((checked_at < released) || ((checked_at - released) < fs__removed_grace_ns))) {
				fs__retire((fs__RetiredItem){.node = node, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			fs__free_node(node);
		}
	}
	{
		array__free(&items);
		array__free(&nodes);
		array__free(&running);
	}
}
