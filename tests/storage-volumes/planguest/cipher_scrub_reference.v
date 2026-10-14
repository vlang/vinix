// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn cipher_binding_tool(reference &char, report &char, readonly bool, changed bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-volume-scrub-reference'), reference, report, &char(nil)]!
		capture := C.open(c'/root/cipher-bind.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(capture >= 0, c'open binding capture'); child := C.fork(); check(child >= 0, c'fork binding tool')
		if child == 0 { if C.dup2(capture, 1) != 1 || C.close(capture) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		check(C.close(capture) == 0, c'close binding capture'); mut code := i32(0); check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'binding exact exit')
		fd := C.open(c'/root/cipher-bind.out', C.O_RDONLY); mut text := [2048]char{}; check(fd >= 0, c'open binding output'); count := C.read(fd, &text[0], 2047); check(count >= 0 && count < 2047 && C.close(fd) == 0, c'bounded binding output')
		if expected == 1 { check(C.strstr(&text[0], c'operation=') == nil, c'invalid binding emits no findings'); return }
		mut wanted := [2048]char{}
		check(C.snprintf(&wanted[0], 2048, c'format=VINIXCS1 operation=verified-ciphertext-scrub-reference mappings=1 matched=%lu changed=%lu algorithm=sha256 reference_sha256=%s report_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', u64(!changed), u64(changed), reference_hash(readonly, false), cipher_binding_report_hash(readonly, changed), u64(readonly), if changed { &char(c'changed') } else { &char(c'match') }, reference_digest(false), reference_digest(changed)) > 0, c'construct binding expectation')
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact complete independent binding output and both fingerprints')
	}
}
@[direct_array_access]
fn cipher_binding_matrix() {
	mut name := [64]char{}; mut output := [64]char{}
	for readonly in [false, true]! { for changed in [false, true]! { for recovery in [false, true]! {
		volume_scrub_name(&name[0], recovery, readonly, changed); cipher_binding_tool(if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }, &name[0], readonly, changed, if changed { 2 } else { 0 })
		check(C.snprintf(&output[0], 64, c'/root/bound-%s%s-%s.txt', if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') }, if changed { &char(c'changed') } else { &char(c'clean') }) > 0, c'bounded binding view path'); copy_scrub_report(c'/root/cipher-bind.out', &output[0])
	} } }
	cipher_binding_tool(c'/root/volume.vchash', c'/root/changed-recovery-ro.vcscrub', true, true, 1)
	for path in [&char(c'/root/volume-ro.vchash'), &char(c'/root/changed-recovery-ro.vcscrub')]! { check(C.chmod(path, 0o644) == 0, c'change binding privacy'); cipher_binding_tool(c'/root/volume-ro.vchash', c'/root/changed-recovery-ro.vcscrub', true, true, 1); check(C.chmod(path, 0o600) == 0, c'restore binding privacy') }
}
fn cipher_binding_cycles(count int) {
	for _ in 0 .. count { cipher_binding_tool(c'/root/volume-ro.vchash', c'/root/clean-volume-ro.vcscrub', true, false, 0); cipher_binding_tool(c'/root/volume-ro.vchash', c'/root/changed-recovery-ro.vcscrub', true, true, 2); cipher_binding_tool(c'/root/volume.vchash', c'/root/clean-recovery.vcscrub', false, false, 0) }
	C.sleep(13); C.printf(c'PLAN CIPHER SCRUB REFERENCE CYCLES count=%d\n', count)
}
@[direct_array_access]
fn cipher_binding_retention() {
	cipher_binding_cycles(100); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); cipher_binding_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHER SCRUB REFERENCE LARGE before=%ld after=%ld\n', before.large, after.large); check(before.count == after.count && before.large == after.large, c'binding large-page retention')
	for i in 0 .. before.count { C.printf(c'PLAN CIPHER SCRUB REFERENCE RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'binding slab retention') }
}

@[direct_array_access]
fn cipher_scrub_reference_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		volume_scrub_first($if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') })
		scrub_compare_matrix(); cipher_binding_matrix()
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		status_before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(held >= 0, c'hold comparison mapping')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold binding writer lock'); cipher_binding_matrix(); check(C.close(root) == 0, c'close binding writer lock')
		check(status_before == status(c'/dev/mapper/vinix60'), c'comparison preserves live status'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close comparison mapping'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		cipher_binding_retention(); C.printf(c'PLAN CIPHER SCRUB REFERENCE PASSED: complete supplied-reference binding, private pinned inputs, exact historical findings and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close comparison phase'); scrub_compare_matrix(); cipher_binding_matrix()
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		C.printf(c'PLAN CIPHER SCRUB REFERENCE REORDERED BOOT PRESERVED\n')
	}
	check(C.unlink(c'/root/compare.out') == 0 && C.unlink(c'/root/cipher-bind.out') == 0, c'reclaim binding captures'); root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.fsync(root) == 0 && C.close(root) == 0, c'persist binding views')
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}

fn cipher_binding_report_hash(readonly bool, changed bool) &char {
	if !readonly { return if changed { &char(c'9d53de2c4dc8ace06e17061e283beef056be711bb4f17d499f2c94a098886187') } else { &char(c'784f47ace251c64a8197e18076a60cc44ab859d224d9a85c19ef349819bf985e') } }
	return if changed { &char(c'64618f986973899ceb7bd970a14015e9cab2d536167819bc29669959fcbd6c0b') } else { &char(c'2dfec11f02d3614a53716cbcc57e9924e028a54a909ed865753d9f15639121a5') }
}
