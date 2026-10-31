module fs

import dev.virtio_9p
import errno
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
	assert file.open(0) or { panic('real open callback') } == file.box
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
	assert backend.resources[nested_res.slot] == nested_res
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
	assert !backend.closed && virtio_9p.close_count() == 0
	file.refcount--
	mut foreign := &MountTable{}
	mut task_fs := &proc.ThreadFS{ mnt: &proc.Namespace{ data: voidptr(foreign) } }
	mut owner := &proc.Process{ threads: [&proc.Thread{ fs: task_fs }] }
	proc.set_owner(owner)
	foreign.mounts << &Mount{ root: root, detached: true }
	backend.check_unmount() or { panic('detach with foreign alias') }
	assert !backend.closed // detached alias in another thread's private table
	foreign.mounts.clear()
	task_fs.lock.acquire()
	backend.check_unmount() or { panic('detach never takes foreign locks') }
	assert !backend.closed
	task_fs.lock.release()
	owner.fs_lock.acquire()
	backend.check_unmount() or { panic('detach never takes owner locks') }
	assert !backend.closed
	owner.fs_lock.release()
	nsfs_dev_id = 1
	backend.check_unmount() or { panic('detach with nsfs retention') }
	assert !backend.closed
	nsfs_dev_id = 0
	proc.set_owner(unsafe { nil })
	backend.check_unmount() or { panic('unmount') }
	assert !backend.closed && virtio_9p.close_count() == 0
	mut remount_instance := template.instantiate()
	assert remount_instance == instance
	mut remounted := backend.mount_specifier(parent, 'again', 'share', 0,
		'trans=virtio,version=9p2000.L,cache=none,msize=65536') or { panic('cached remount') }
	assert remounted != root && remounted.filesystem == root.filesystem
	mut remount_dir := ninep_resource(remounted)
	remount_dir.snapshot_permissions(mut acl) or { panic('fresh remount view') }
	assert lookup_child_synced(remounted, 'alpha') != unsafe { nil }
	backend.mount_specifier(parent, 'bad', 'different-tag', 0, '') or { assert errno.get() == errno.enodev }
	assert !backend.closed && virtio_9p.close_count() == 0
	assert file.read(unsafe { nil }, &data[0], 0, 1) or { i64(-1) } == 1
	backend.client.dead = true
	backend.client.tx = unsafe { nil }
	backend.client.rx = unsafe { nil }
	backend.mount_specifier(parent, 'dead', 'share', 0, '') or { assert errno.get() == errno.eio }
	_ = resource.o_path
}
