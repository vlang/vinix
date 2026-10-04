void klock__Lock__release(klock__Lock* l) {
	bool ints = l->ints;
	katomic__store_release(&l->l, false);
	cpu__interrupt_toggle(ints);
}
