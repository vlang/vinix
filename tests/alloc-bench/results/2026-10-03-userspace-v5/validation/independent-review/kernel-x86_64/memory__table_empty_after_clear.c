		if (!memory__table_empty_after_clear(pml1_p, pml1_entry)) {
			if ((old & 1) != 0) {
				memory__Pagemap__invalidate(pagemap, virt);
			}
			return (__v_option){.ok = true};
		}
