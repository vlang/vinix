module memory

@[export: 'vinix_acpi_sync_heap_snapshot']
fn acpi_sync_heap_snapshot(out &u64) {
	$if acpi_sync_test ? {
		// Read the live object counters directly: no allocating observer.
		for i := 0; i < slabs.len; i++ {
			mut slab := unsafe { &slabs[i] }
			slab.@lock.acquire()
			unsafe { out[i] = slab.live }
			slab.@lock.release()
		}
	}
}
