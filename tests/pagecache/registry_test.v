@[has_globals]
module pagecache

import errno

struct RegistryDevice {
mut:
    bytes [4096]u8
    fail_write bool
}

fn registry_device() &RegistryDevice { return &RegistryDevice{} }

fn registry_load(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
    d := unsafe { &RegistryDevice(context) }
    unsafe { C.memcpy(buf, &d.bytes[loc], count) }
    return i64(count)
}

fn registry_store(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
    mut d := unsafe { &RegistryDevice(context) }
    if d.fail_write { errno.set(errno.eio); return none }
    unsafe { C.memcpy(&d.bytes[loc], buf, count) }
    return i64(count)
}

fn registry_write(mut cache Cache, device &RegistryDevice, offset int, data []u8) {
    ret := cache.write(device, registry_load, registry_store, unsafe { &data[0] }, u64(offset), u64(data.len), 4096) or { panic('write') }
    assert ret == data.len
}

__global (
	registry_hook_cache &Cache = unsafe { nil }
	registry_hook_device &RegistryDevice = unsafe { nil }
	registry_hook_fail bool
	registry_hook_calls int
	registry_barrier_calls int
	registry_barrier_fail bool
)

fn registry_hook() bool {
	registry_hook_calls++
	registry_write(mut registry_hook_cache, registry_hook_device, 0, [u8(0xd3)])
	return !registry_hook_fail
}

fn registry_barrier(context voidptr) ? {
	mut d := unsafe { &RegistryDevice(context) }
	// Even the first barrier follows every pre-sync hook and this cache's
	// write. Device 2 must still complete if device 1 or a hook fails.
	assert registry_hook_calls > 0
	assert d.bytes[0] == 0xd3 || d.bytes[0] == 0x91
	registry_barrier_calls++
	if context == voidptr(registry_hook_device) && registry_barrier_fail {
		errno.set(errno.eio)
		return none
	}
}

fn test_global_hooks_flush_barriers_failure_continuity_and_retry() {
	mut first := registry_device()
	mut second := registry_device()
	mut first_cache := &Cache{}
	mut second_cache := &Cache{}
	registry_hook_cache = first_cache
	registry_hook_device = first
	assert register_sync_hook(registry_hook)
	assert register_sync_hook(registry_hook)
	assert sync_hooks_len == 1
	assert register_cache(first_cache, first, registry_store, registry_barrier)
	assert register_cache(second_cache, second, registry_store, registry_barrier)
	registry_write(mut second_cache, second, 0, [u8(0x91)])
	registry_hook_fail = true
	registry_barrier_fail = true
	assert !sync_all()
	assert registry_barrier_calls == 2
	assert first.bytes[0] == 0xd3 && second.bytes[0] == 0x91
	registry_hook_fail = false
	registry_barrier_fail = false
	assert sync_all()
	assert registry_barrier_calls == 4
	first.fail_write = true
	registry_write(mut second_cache, second, 1, [u8(0x29)])
	assert !sync_all()
	assert second.bytes[1] == 0x29 && registry_barrier_calls == 6
	assert first_cache.dirty_pages != 0
	first.fail_write = false
	assert sync_all()
	assert first_cache.dirty_pages == 0 && registry_barrier_calls == 8
	// Production registrations are mount-lifetime; test-only reset permits
	// freeing the host fixture after the callbacks have completed.
	registered_caches_len = 0
	sync_hooks_len = 0
	first_cache.release(first, registry_store) or { panic('release') }
	second_cache.release(second, registry_store) or { panic('release') }
}
