module memory

// Limine enters with 4 KiB tables. Keep this as one asm block: there must
// be no context synchronization between installing the 16 KiB tables and TCR.
fn switch_granule(mair u64, root u64, tcr u64) {
	asm volatile aarch64 {
		dsb ishst
		tlbi vmalle1is
		dsb ish
		isb
		msr MAIR_EL1, mair
		msr TTBR0_EL1, root
		msr TTBR1_EL1, root
		msr TCR_EL1, tcr
		isb
		tlbi vmalle1is
		dsb ish
		isb
		; ; r (mair)
		    r (root)
		    r (tcr)
		; memory
	}
}
