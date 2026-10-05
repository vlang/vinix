__v_option memory__Pagemap__unmap_page_unlocked(memory__Pagemap* pagemap, u64 virt) {
	u64 pml5_entry = (u64)(((u64)(	(virt & ((u64)(((u64)(	(u64)(0x1ff))) << (48)))))) >> (48));
	u64 pml4_entry = (u64)(((u64)(	(virt & ((u64)(((u64)(	(u64)(0x1ff))) << (39)))))) >> (39));
	u64 pml3_entry = (u64)(((u64)(	(virt & ((u64)(((u64)(	(u64)(0x1ff))) << (30)))))) >> (30));
	u64 pml2_entry = (u64)(((u64)(	(virt & ((u64)(((u64)(	(u64)(0x1ff))) << (21)))))) >> (21));
	u64 pml1_entry = (u64)(((u64)(	(virt & ((u64)(((u64)(	(u64)(0x1ff))) << (12)))))) >> (12));
	u64* pml5 = pagemap->top_level;
	u64* pml5_p = (u64*)((u64)(pml5) + memory__higher_half);
	u64* __if_val_0 = {0};
	if (!memory__la57) {
		__if_val_0 = pagemap->top_level;
	} else {
		__v_option_u64ptr __or_opt_1 = memory__get_next_level(pml5, pml5_entry, false);
		u64* __or_val_2 = {0};
		if (__or_opt_1.ok) {
			__or_val_2 = __or_opt_1.value;
		} else {
			return (__v_option){.ok = false};
		}
		__if_val_0 = __or_val_2;
	}
	u64* pml4 = __if_val_0;
	u64* pml4_p = (u64*)((u64)(pml4) + memory__higher_half);
	__v_option_u64ptr __or_opt_3 = memory__get_next_level(pml4, pml4_entry, false);
	u64* __or_val_4 = {0};
	if (__or_opt_3.ok) {
		__or_val_4 = __or_opt_3.value;
	} else {
		return (__v_option){.ok = false};
	}
	u64* pml3 = __or_val_4;
	u64* pml3_p = (u64*)((u64)(pml3) + memory__higher_half);
	__v_option_u64ptr __or_opt_5 = memory__get_next_level(pml3, pml3_entry, false);
	u64* __or_val_6 = {0};
	if (__or_opt_5.ok) {
		__or_val_6 = __or_opt_5.value;
	} else {
		return (__v_option){.ok = false};
	}
	u64* pml2 = __or_val_6;
	u64* pml2_p = (u64*)((u64)(pml2) + memory__higher_half);
	__v_option_u64ptr __or_opt_7 = memory__get_next_level(pml2, pml2_entry, false);
	u64* __or_val_8 = {0};
	if (__or_opt_7.ok) {
		__or_val_8 = __or_opt_7.value;
	} else {
		return (__v_option){.ok = false};
	}
	u64* pml1 = __or_val_8;
	u64* pml1_p = (u64*)((u64)(pml1) + memory__higher_half);
	u64* pte_p = (u64*)((u64)(&(pml1)[pml1_entry]) + memory__higher_half);
	{
		u64 old = *pte_p;
		*pte_p = 0;
		if (!memory__table_empty_after_clear(pml1_p, pml1_entry)) {
			if ((old & 1) != 0) {
				memory__Pagemap__invalidate(pagemap, virt);
			}
			return (__v_option){.ok = true};
		}
		(pml2_p)[pml2_entry] = 0;
		bool remove_pml2 = memory__table_empty_after_clear(pml2_p, pml2_entry);
		bool remove_pml3 = false;
		bool remove_pml4 = false;
		if (remove_pml2) {
			(pml3_p)[pml3_entry] = 0;
			remove_pml3 = memory__table_empty_after_clear(pml3_p, pml3_entry);
			if (remove_pml3) {
				(pml4_p)[pml4_entry] = 0;
				if (memory__la57) {
					remove_pml4 = memory__table_empty_after_clear(pml4_p, pml4_entry);
					if (remove_pml4) {
						(pml5_p)[pml5_entry] = 0;
					}
				}
			}
		}
		memory__Pagemap__invalidate(pagemap, virt);
		memory__pmm_free((void*)(pml1), 1);
		if (remove_pml2) {
			memory__pmm_free((void*)(pml2), 1);
		}
		if (remove_pml3) {
			memory__pmm_free((void*)(pml3), 1);
		}
		if (remove_pml4) {
			memory__pmm_free((void*)(pml4), 1);
		}
	}
	return (__v_option){.ok = true};
}
