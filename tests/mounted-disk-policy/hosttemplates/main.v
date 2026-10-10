
module main
import resource
import security
import stat
import errno
fn C.host_signal_started()
fn C.host_wait_started()
fn C.host_signal_release()
fn C.host_wait_release()
struct Hardware {
pub mut:
 stat stat.Stat
 identity resource.BlockIdentity
}
fn (device &Hardware) block_identity() resource.BlockIdentity { return device.identity }
struct Fake {
pub mut:
 stat stat.Stat
}
fn device(identity resource.BlockIdentity, mode u32) resource.Resource {
    return Hardware{stat: stat.Stat{mode: mode, rdev: identity.disk_id, size: i64(identity.length)}, identity: identity}
}
fn hold_raw_write(disk &resource.Resource) {
    mut actual := unsafe { disk }
    token := security.begin_user_device_write(mut actual) or { panic('writer should start insecure') }
    C.host_signal_started()
    C.host_wait_release()
    security.end_user_device_write(token)
}
fn main() {
    whole := resource.BlockIdentity{is_block: true, disk_id: 1, length: 1048576}
    volume := resource.BlockIdentity{is_block: true, disk_id: 1, start: 16384, length: 65536}
    sibling := resource.BlockIdentity{is_block: true, disk_id: 1, start: 131072, length: 65536}
    overlap := resource.BlockIdentity{is_block: true, disk_id: 1, start: 32768, length: 65536}
    other := resource.BlockIdentity{is_block: true, disk_id: 2, length: 1048576}
    assert volume.overlaps(whole) && whole.overlaps(volume)
    assert volume.overlaps(overlap) && !volume.overlaps(sibling) && !volume.overlaps(other)
    assert !resource.BlockIdentity{is_block: true, disk_id: 1, start: u64(-16), length: 32}.valid()
    assert !resource.BlockIdentity{is_block: true, disk_id: 1, length: 0}.valid()
    for identity in [whole, volume, sibling, overlap, other] { security.register_block_device(identity) }
    mut disk := device(whole, 0o060000)
    mut part := device(volume, 0o060000)
    mut neighbor := device(sibling, 0o060000)
    mut spare := device(other, 0o060000)
    mut alias := device(whole, 0o020000) // Caller mode cannot change real backing provenance.
    mut fake := resource.Resource(Fake{stat: stat.Stat{mode: 0o060000, rdev: 1, size: 1048576}})
    assert !resource.block_identity(mut fake).valid()
    security.set_level(0)
    writer := spawn hold_raw_write(&disk)
    C.host_wait_started()
    during_write := security.claim_swap(volume) or { assert errno.get() == errno.ebusy; -1 }
    assert during_write == -1
    security.set_level(1)
    token := security.begin_block_mount(volume) or {
        assert errno.get() == errno.ebusy
        -1
    }
    assert token == -1
    // Growing the inventory while a writer sleeps cannot invalidate its token.
    for id in 3 .. 300 { security.register_block_device(resource.BlockIdentity{is_block: true, disk_id: u64(id), length: 4096}) }
    C.host_signal_release()
    writer.wait()
    reserved := security.begin_block_mount(volume) or { panic('completed writer must release reservation conflict') }
    during_mount := security.claim_swap(volume) or { assert errno.get() == errno.ebusy; -1 }
    assert during_mount == -1
    assert !security.user_device_write_allowed(mut disk)
    assert !security.user_device_write_allowed(mut part)
    assert security.user_device_write_allowed(mut neighbor) && security.user_device_write_allowed(mut spare)
    security.finish_block_mount(reserved, false)
    assert security.user_device_write_allowed(mut disk) // Failed mount cancels protection.
    cancelled := security.begin_user_device_write(mut part) or { panic('cancelled mount should permit raw writes') }
    security.end_user_device_write(cancelled)
    security.set_level(0)
    swap := security.claim_swap(volume) or { panic('unmounted extent should permit swap') }
    assert !security.user_device_write_allowed(mut alias) && errno.get() == errno.ebusy
    assert !security.user_device_write_allowed(mut disk)
    assert !security.user_device_write_allowed(mut part)
    assert security.user_device_write_allowed(mut neighbor) && security.user_device_write_allowed(mut spare)
    denied_write := security.begin_user_device_write(mut disk) or { assert errno.get() == errno.ebusy; -1 }
    assert denied_write == -1
    denied_mount := security.begin_block_mount(overlap) or { assert errno.get() == errno.ebusy; -1 }
    assert denied_mount == -1
    denied_swap := security.claim_swap(whole) or { assert errno.get() == errno.ebusy; -1 }
    assert denied_swap == -1
    adjacent := security.begin_block_mount(sibling) or { panic('disjoint mount must remain available') }
    security.finish_block_mount(adjacent, false)
    security.release_swap(swap)
    assert security.user_device_write_allowed(mut disk)
    security.set_level(1)
    committed := security.begin_block_mount(volume) or { panic('mount should reserve') }
    security.finish_block_mount(committed, true)
    for _ in 0 .. 10000 {
        assert !security.user_device_write_allowed(mut alias)
        denial := security.begin_user_device_write(mut disk) or { assert errno.get() == errno.eperm; -1 }
        assert denial == -1
    }
    assert !security.user_device_write_allowed(mut fake)
    allowed := security.begin_user_device_write(mut neighbor) or { panic('non-overlap must stay writable') }
    security.end_user_device_write(allowed)
    allowed_other := security.begin_user_device_write(mut spare) or { panic('unrelated disk must stay writable') }
    security.end_user_device_write(allowed_other)
    security.set_level(2)
    assert !security.user_device_write_allowed(mut spare) && !security.user_device_write_allowed(mut alias)
    security.set_level(0)
    assert security.user_device_write_allowed(mut disk)
    protected_swap := security.claim_swap(volume) or { assert errno.get() == errno.ebusy; -1 }
    assert protected_swap == -1
    println('PASS: production topology, provenance, swap exclusivity, mount/write interleaving, cancellation, inventory growth and securelevels')
}
