Independent relative procfs link lifetime review: PASS

Read-only review by `/root/procself_lifetime_review`, as required by AGENTS.md.
The join failure found in the initial fixture is fixed: `_exit(1)` prevents
stack unwinding or shared descriptor cleanup while a worker could still run.

Kernel Text storage remains on the stack. `finish_text` frees the Text byte
buffer and returns owned target bytes. Both VFS consumers free that string
after synchronous lookup/copy, including copy-error returns. Namespace views
remain synchronous borrows with unchanged ownership. No new kernel lifetime
or reference transfer is introduced by relative target spelling.

The fixture bank survives both forked cohorts. Every started worker is joined
before its stack state expires; partial creation failures join existing workers.
Descriptor error paths clean up. Both previews and actual guest fixture C match,
with three bounded explicit `alloca` objects and no hidden malloc, memdup,
new_array, v_fixed_index or promoted fixture storage. Final captures contain
zero matrix failures, correct selected inode/Tgid and passing chroot resolution.
All live slab counts stay exact after 200 cycles; large pages stay 63/63 ARM
and 160/160 x86 in both credential groups.

The full mount retention failure is outside this approval. Namespace
retargeting, unmount and concurrent close races are not lifetime qualifications.

| Final artifact | SHA256 |
| --- | --- |
| kernel/fs/procfs.v | 9b3f54c37e09fb4b15ac1bb5ff83894c2018547d8a5a866f468e15b43dcfa27f |
| tests/linux-compat/procselffixture/core.v | 7152f11a7c5543ef1d904ae831c713c175ed272552dd5440f4137ab7ddad0f37 |
| preview-arm.c | a8da678def105f06f0ab0cb408907c6c174d662af4bf9b066c4df8b2252d462b |
| preview-x86.c | a8da678def105f06f0ab0cb408907c6c174d662af4bf9b066c4df8b2252d462b |
| kernel-arm/kernel/obj/blob.c | b767c37c0a73c78ce898c8f1d746db0d10d5c784e932005648aa7ed5d6ba71b9 |
| kernel-x86/kernel/obj/blob.c | f42289431333f6e194eeacea02f4fa1755a259c7277c01a91d15a6cc1632e380 |
| after-arm/procself/serial.log | 64187947955114b014d77582a7ffbac9c67aee9e0ae128802d11968e683c00b4 |
| after-x86/procself/serial.log | 3ee7e4b0e5c08c661333e9c9e6bbaa6830f352cd84ed6ba8943c496e3971db03 |

Both actual after-guest fixture C hashes equal their preview above.
