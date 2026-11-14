module fs

import dev.virtio_9p
import errno
import file as filemod
import proc
import resource
import stat

fn test_actual_facade_mount_read_host_edit_mutations_and_unmount() {
	initial_mount_table = &MountTable{}
	mut template := &NinePFS{}
	mut instance := template.instantiate()
	assert instance is NinePFS
	mut backend := unsafe { &NinePFS(0) }
	if mut instance is NinePFS { backend = unsafe { instance } }
	mut parent := create_node(instance, unsafe { nil }, '/', true)
	mut root := backend.mount_specifier(parent, 'mnt', 'share', 0,
		'trans=virtio,version=9p2000.L,cache=none,msize=65536') or { panic('mount') }
	assert root.filesystem == instance
	mut dir := ninep_resource(root)
	mut acl := []u8{}
	dir.snapshot_permissions(mut acl) or { panic('permissions') }
	assert root.children.len == 3
	mut file := ninep_resource(lookup_child_synced(root, 'alpha'))
	assert file != unsafe { nil } && file.stat.size == 3
	mut opening := file.box
	opened := resource.open_resource(mut opening, 0) or { panic('real owned open dispatch') }
	assert opened.resource == file.box && opened.owned
	mut initial_handle := filemod.Handle{}
	file.unref(voidptr(unsafe { &initial_handle })) or { panic('close initial description') }
	mut data := [16]u8{}
	assert file.read(unsafe { nil }, &data[0], 0, 16) or { i64(-1) } == 3
	assert unsafe { tos(&data[0], 3) } == 'old'
	virtio_9p.host_edit()
	assert file.read(unsafe { nil }, &data[0], 0, 16) or { i64(-1) } == 5
	assert unsafe { tos(&data[0], 5) } == 'fresh'
	assert file.stat.size == 5
	mut mode_box := file.box
	assert mode_box is resource.ModeResource
	file.chmod_mode(0o600) or { panic('chmod hook') }
	assert virtio_9p.host_mode() == 0o100600 && virtio_9p.last_setattr_mask() == 1
	// A descriptor timestamp update must preserve a newer host chmod.
	virtio_9p.host_chmod(0o640)
	file.stat.mtim.tv_sec = 17
	file.persist_metadata() or { panic('timestamp delta') }
	assert virtio_9p.last_setattr_mask() == (32 | 256)
	assert virtio_9p.host_mode() == 0o100640 && file.stat.mode == 0o100640
	// A conflicting update to the same field must fail, without an RPC write.
	file.stat.mode = 0o100644
	virtio_9p.host_chmod(0o400)
	before_conflict := virtio_9p.call_count()
	file.persist_metadata() or { assert errno.get() == errno.ebusy }
	assert virtio_9p.call_count() == before_conflict + 1
	assert virtio_9p.host_mode() == 0o100400
	file.stat.mode = file.host.mode
	file.chmod_mode(0o644) or { panic('restore chmod') }
	assert file.write(unsafe { nil }, c'x', 5, 1) or { i64(-1) } == 1
	assert virtio_9p.host_size() == 6
	file.grow(unsafe { nil }, 2) or { panic('truncate') }
	assert virtio_9p.host_size() == 2
	mut new_file := backend.create(root, 'new'.clone(), stat.ifreg)
	assert new_file != unsafe { nil }
	before_create_gap := root.children.len
	dir.snapshot_permissions(mut acl) or { assert errno.get() == errno.ebusy }
	assert root.children.len == before_create_gap && ninep_resource(new_file).publication == 1
	new_file.resource.stat.mode |= 0o644
	mut new_res := ninep_resource(new_file)
	new_res.persist_metadata() or { panic('metadata') }
	publish_child(root, new_file.name, new_file)
	backend.rename(root, 'new', root, 'renamed', 0) or { panic('rename') }
	dir.snapshot_permissions(mut acl) or { assert errno.get() == errno.ebusy }
	assert lookup_child_synced(root, 'new') == new_file && !new_file.orphan
	// Actual VFS publishes the new key before adopt() changes node.name.
	remove_child(root, 'new')
	publish_child(root, 'renamed', new_file)
	dir.snapshot_permissions(mut acl) or { panic('map before adopt') }
	assert !new_file.orphan
	new_file.name = 'renamed'
	new_res.unlink(voidptr(new_file)) or { panic('unlink') }
	dir.snapshot_permissions(mut acl) or { assert errno.get() == errno.ebusy }
	assert lookup_child_synced(root, 'renamed') == new_file
	remove_child(root, 'renamed')
	new_file.orphan = true
	new_res.unref(unsafe { nil }) or { panic('unref') }
	mut new_dir := backend.create(root, 'directory'.clone(), stat.ifdir)
	assert new_dir != unsafe { nil }
	new_dir.resource.stat.mode |= 0o755
	mut new_dir_res := ninep_resource(new_dir)
	new_dir_res.persist_metadata() or { panic('directory metadata') }
	new_dir.create_dotentries(root)
	publish_child(root, 'directory', new_dir)
	dir.snapshot_permissions(mut acl) or { panic('refresh directory') }
	assert root.children.len == 4
	mut nested := backend.create(new_dir, 'child'.clone(), stat.ifreg)
	assert nested != unsafe { nil }
	publish_child(new_dir, 'child', nested)
	dir.snapshot_permissions(mut acl) or { panic('nested publication') }
	mut nested_res := ninep_resource(nested)
	nested_res.refcount++ // live descendant handle, retained across host removal
	virtio_9p.host_present('directory', false)
	dir.snapshot_permissions(mut acl) or { assert errno.get() == errno.ebusy }
	assert lookup_child_synced(root, 'directory') == new_dir
	assert lookup_child_synced(new_dir, 'child') == nested && !nested.orphan && !new_dir.removed
	assert backend.session.resources[nested_res.slot] == nested_res
	virtio_9p.host_present('directory', true)
	nested_res.refcount--
	nested_res.unlink(voidptr(nested)) or { panic('nested unlink') }
	remove_child(new_dir, 'child')
	nested.orphan = true
	nested_res.unref(unsafe { nil }) or { panic('nested unref') }
	new_dir_res.unlink(voidptr(new_dir)) or { panic('rmdir') }
	remove_child(root, 'directory')
	new_dir.removed = true
	new_dir_res.unref(unsafe { nil }) or { panic('unref directory') }
	before := virtio_9p.live_fids()
	for _ in 0 .. 100 {
		file.read(unsafe { nil }, &data[0], 0, 16) or { panic('repeat read') }
		dir.snapshot_permissions(mut acl) or { panic('repeat populate') }
	}
	assert virtio_9p.live_fids() == before
	mut borrowed := file.box
	ninep_refresh_stat(mut borrowed) or { panic('stat refresh API') }
	file.refcount++
	backend.check_unmount() or { panic('detach with retained superblock') }
	assert !backend.session.closed && virtio_9p.close_count() == 0
	file.refcount--
	mut foreign := &MountTable{}
	mut task_fs := &proc.ThreadFS{ mnt: &proc.Namespace{ data: voidptr(foreign) } }
	mut owner := &proc.Process{ threads: [&proc.Thread{ fs: task_fs }] }
	proc.set_owner(owner)
	foreign.mounts << &Mount{ root: root, detached: true }
	backend.check_unmount() or { panic('detach with foreign alias') }
	assert !backend.session.closed // detached alias in another thread's private table
	foreign.mounts.clear()
	task_fs.lock.acquire()
	backend.check_unmount() or { panic('detach never takes foreign locks') }
	assert !backend.session.closed
	task_fs.lock.release()
	owner.fs_lock.acquire()
	backend.check_unmount() or { panic('detach never takes owner locks') }
	assert !backend.session.closed
	owner.fs_lock.release()
	nsfs_dev_id = 1
	backend.check_unmount() or { panic('detach with nsfs retention') }
	assert !backend.session.closed
	nsfs_dev_id = 0
	proc.set_owner(unsafe { nil })
	backend.check_unmount() or { panic('unmount') }
	assert !backend.session.closed && virtio_9p.close_count() == 0
	mut remount_instance := template.instantiate()
	assert remount_instance != instance
	mut remount_backend := &NinePFS(unsafe { nil })
	if mut remount_instance is NinePFS { remount_backend = unsafe { remount_instance } }
	assert remount_backend != unsafe { nil }
	mut remounted := remount_backend.mount_specifier(parent, 'again', 'share', 0,
		'trans=virtio,version=9p2000.L,cache=none,msize=65536') or { panic('cached remount') }
	assert remounted != root && remounted.filesystem != root.filesystem
	assert remount_backend.session == backend.session
	mut remount_dir := ninep_resource(remounted)
	remount_dir.snapshot_permissions(mut acl) or { panic('fresh remount view') }
	assert lookup_child_synced(remounted, 'alpha') != unsafe { nil }
	backend.mount_specifier(parent, 'bad', 'different-tag', 0, '') or { assert errno.get() == errno.enodev }
	assert !backend.session.closed && virtio_9p.close_count() == 0
	assert file.read(unsafe { nil }, &data[0], 0, 1) or { i64(-1) } == 1
	check_exclusive_create_and_open_lifetime(mut backend, mut dir, root)
	backend.session.client.dead = true
	backend.session.client.tx = unsafe { nil }
	backend.session.client.rx = unsafe { nil }
	backend.mount_specifier(parent, 'dead', 'share', 0, '') or { assert errno.get() == errno.eio }
	_ = resource.o_path
}

fn check_exclusive_create_and_open_lifetime(mut backend NinePFS, mut dir NinePResource, root &VFSNode) {
	// Inject an independent host creation after the VFS's cached-name check.
	// The backend must return EEXIST without adopting or changing that file.
	before_race := virtio_9p.live_fids()
	virtio_9p.race_next_create()
	race_name := 'host-race'.clone()
	assert backend.create(root, race_name, stat.ifreg | 0o600) == unsafe { nil }
	assert errno.get() == errno.eexist && virtio_9p.host_file_mode('host-race') == 0o100640
	unsafe { race_name.free() }
	assert virtio_9p.live_fids() == before_race
	mut acl := []u8{}
	dir.snapshot_permissions(mut acl) or { panic('discover competing creator') }

	mut node := backend.create(root, 'opened-unlinked'.clone(), stat.ifreg | 0o644)
	assert node != unsafe { nil }
	publish_child(root, node.name, node)
	dir.snapshot_permissions(mut acl) or { panic('publish retained-open fixture') }
	mut res := ninep_resource(node)
	before := virtio_9p.live_fids()
	mut box := res.box
	for _ in 0 .. 2 {
		opened := resource.open_resource(mut box, resource.o_rdwr) or { panic('open read-write') }
		assert opened.owned && opened.resource == box
	}
	assert res.refcount == 3 && res.open_counts[2] == 2
	assert virtio_9p.live_fids() == before + 1
	virtio_9p.fail_next_open()
	mut refused_existing_mode := false
	resource.open_resource(mut box, resource.o_rdwr) or {
		refused_existing_mode = true
		assert errno.get() == errno.eacces
	}
	assert refused_existing_mode && res.refcount == 3 && res.open_counts[2] == 2
	assert virtio_9p.live_fids() == before + 1
	// A failed remote open must return its temporary FID and retain no ref.
	virtio_9p.fail_next_open()
	mut refused := false
	resource.open_resource(mut box, resource.o_rdonly) or {
		refused = true
		assert errno.get() == errno.eacces
	}
	assert refused && res.refcount == 3 && res.open_counts[0] == 0
	assert virtio_9p.live_fids() == before + 1
	resource.open_resource(mut box, resource.o_rdonly) or { panic('open read-only') }
	resource.open_resource(mut box, resource.o_wronly) or { panic('open write-only') }
	resource.open_resource(mut box, resource.o_path) or { panic('open path') }
	assert res.refcount == 6 && virtio_9p.live_fids() == before + 3
	mut readwrite := filemod.Handle{flags: resource.o_rdwr}
	mut readonly := filemod.Handle{flags: resource.o_rdonly}
	mut writeonly := filemod.Handle{flags: resource.o_wronly}
	mut pathonly := filemod.Handle{flags: resource.o_path}
	res.unref(voidptr(unsafe { &readwrite })) or { panic('close one shared-mode description') }
	assert res.open_counts[2] == 1 && virtio_9p.live_fids() == before + 3
	// This is also how FD construction failure returns an adopted reference:
	// a caller-stack Handle carries flags without publishing any descriptor.
	res.unref(voidptr(unsafe { &writeonly })) or { panic('rollback write-only description') }
	res.unref(voidptr(unsafe { &pathonly })) or { panic('close O_PATH') }
	assert res.refcount == 3 && virtio_9p.live_fids() == before + 2
	assert res.write(unsafe { nil }, c'live', 0, 4) or { i64(-1) } == 4
	res.unlink(voidptr(node)) or { panic('unlink open inode') }
	remove_child(root, node.name)
	node.orphan = true
	res.unref(unsafe { nil }) or { panic('release namespace reference') }
	assert res.refcount == 2 && res.open_counts[2] == 1 && res.open_counts[0] == 1
	mut data := [16]u8{}
	assert res.read(unsafe { nil }, &data[0], 0, 16) or { i64(-1) } == 4
	assert unsafe { tos(&data[0], 4) } == 'live'
	assert res.write(unsafe { nil }, c'!', 4, 1) or { i64(-1) } == 1
	res.sync(unsafe { nil }) or { panic('fsync unlinked inode') }
	snapshot := res.snapshot_stat() or { panic('stat unlinked inode') }
	assert snapshot.nlink == 0 && snapshot.size == 5
	res.unref(voidptr(unsafe { &readonly })) or { panic('close final read-only description') }
	assert virtio_9p.live_fids() == before + 1 && res.open_counts[0] == 0
	assert res.read(unsafe { nil }, &data[0], 0, 16) or { i64(-1) } == 5
	assert unsafe { tos(&data[0], 5) } == 'live!'
	res.sync(unsafe { nil }) or { panic('fsync through remaining read-write handle') }
	slot := res.slot
	assert res.refcount == 1 && res.open_counts[2] == 1
	assert backend.session == res.filesystem.session
	res.unref(voidptr(unsafe { &readwrite })) or { panic('final close after unlink') }
	assert backend.session.resources[slot] == unsafe { nil }
	assert virtio_9p.live_fids() == before - 1
	dir.snapshot_permissions(mut acl) or { panic('directory after final close') }
}
