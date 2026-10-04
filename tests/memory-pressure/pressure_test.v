module file

import errno
import katomic
import memory
import resource
import stat

fn read_pressure(mut pressure resource.Resource, loc u64, count u64) string {
	mut bytes := []u8{len: int(count)}
	got := pressure.read(unsafe { nil }, bytes.data, loc, count) or { panic('read failed') }
	return bytes[..int(got)].bytestr()
}

fn open_pressure(mut source resource.Resource) &resource.Resource {
	mut file := source as MemoryPressureFile
	mut opened := file.open(resource.o_rdonly) or { panic('open failed') }
	katomic.inc(mut &opened.refcount)
	return opened
}

fn test_independent_consumption_partial_reads_and_transition_edges() {
	memory.set_snapshot(0, 0)
	mut source := new_memory_pressure_source(stat.Stat{})
	mut a := open_pressure(mut source)
	mut b := open_pressure(mut source)
	assert a.status == pollin && b.status == pollin
	head := read_pressure(mut a, 0, 13)
	assert head == 'level normal\n'
	assert a.status == 0 && b.status == pollin
	memory.set_snapshot(1, 1)
	assert a.status == pollin && b.status == pollin
	// Remaining bytes belong to the original stable snapshot.
	tail := read_pressure(mut a, 13, 512)
	assert tail.starts_with('generation 0\n')
	assert a.status == pollin
	assert read_pressure(mut b, 0, 512).starts_with('level warning\ngeneration 1\n')
	assert b.status == 0 && a.status == pollin
	assert read_pressure(mut a, 0, 512).starts_with('level warning\ngeneration 1\n')
	assert a.status == 0
	assert pressure_files[0].refcount == 1
	assert a.refcount == 1
	assert read_pressure(mut a, 512, 1) == ''
	memory.set_snapshot(2, 2)
	assert a.status == pollin && b.status == pollin
	assert read_pressure(mut a, 0, 512).starts_with('level critical\n')
	// A delayed notification already acknowledged cannot create a new edge.
	notify_memory_pressure(2)
	assert a.status == 0
	a.unref(unsafe { nil }) or { panic('close failed') }
	b.unref(unsafe { nil }) or { panic('close failed') }
	assert pressure_file_used.count(it) == 0
}

fn test_subscription_limit_reuse_path_opens_and_access_modes() {
	mut source := new_memory_pressure_source(stat.Stat{})
	mut source_file := source as MemoryPressureFile
	assert source_file.open(resource.o_wronly) == none
	assert errno.get() == errno.eacces
	assert source_file.open(resource.o_path) or { panic('O_PATH failed') } == source
	for _ in 0 .. 3 {
		mut opened := []&resource.Resource{}
		for _ in 0 .. pressure_subscriptions { opened << open_pressure(mut source) }
		assert source_file.open(resource.o_rdonly) == none
		assert errno.get() == errno.enospc
		for mut subscription in opened { subscription.unref(unsafe { nil }) or {} }
	}
}
