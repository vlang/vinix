module fs

import errno
import stat

fn mounted(mut template NinePFS, parent &VFSNode, name string, tag string) &VFSNode {
	mut instance := template.instantiate()
	if mut instance is NinePFS {
		return instance.mount_specifier(parent, name, tag, 0, '') or { panic('mount ' + tag) }
	}
	panic('wrong filesystem')
}

fn read_text(mut file NinePResource, expected string) {
	mut bytes := [64]u8{}
	n := file.read(unsafe { nil }, &bytes[0], 0, 64) or { panic('read') }
	assert n == expected.len
	assert unsafe { tos(&bytes[0], int(n)) } == expected
}

fn test_independent_mounts_tags_remount_and_unknown() {
	initial_mount_table = &MountTable{}
	mut template := &NinePFS{}
	parent := create_node(template.as_filesystem(), unsafe { nil }, '/', true)
	a := mounted(mut template, parent, 'a', 'tag-a')
	b := mounted(mut template, parent, 'b', 'tag-b')
	assert voidptr(a.filesystem) != voidptr(b.filesystem)
	mut ar := ninep_resource(a)
	mut br := ninep_resource(b)
	assert voidptr(ar.filesystem) != voidptr(br.filesystem)
	assert voidptr(ar.filesystem.session.channel) != voidptr(br.filesystem.session.channel)
	assert ar.filesystem.session.dev != br.filesystem.session.dev
	assert ar.refcount == 1 && ar.box.refcount == 1
	assert voidptr(ar.box) == voidptr(unsafe { &ar.resource_value })
	mut acl := []u8{}
	ar.snapshot_permissions(mut acl) or { panic('populate a') }
	br.snapshot_permissions(mut acl) or { panic('populate b') }
	mut af := ninep_resource(lookup_child_synced(a, 'alpha'))
	mut bf := ninep_resource(lookup_child_synced(b, 'alpha'))
	assert af != unsafe { nil } && bf != unsafe { nil }
	assert af.write(unsafe { nil }, c'AAA', 0, 3) or { i64(-1) } == 3
	assert bf.write(unsafe { nil }, c'BBB', 0, 3) or { i64(-1) } == 3
	read_text(mut af, 'AAA')
	read_text(mut bf, 'BBB')
	// A second same-tag mount has its own adapter and namespace view while
	// retaining the original channel/FID owner across detach, like Path B.
	again := mounted(mut template, parent, 'again', 'tag-a')
	assert voidptr(again) != voidptr(a) && voidptr(again.filesystem) != voidptr(a.filesystem)
	mut again_res := ninep_resource(again)
	assert voidptr(again_res.filesystem.session) == voidptr(ar.filesystem.session)
	again_res.snapshot_permissions(mut acl) or { panic('populate remount') }
	mut again_file := ninep_resource(lookup_child_synced(again, 'alpha'))
	read_text(mut again_file, 'AAA')
	mut unknown := template.instantiate()
	mut refused := false
	if mut unknown is NinePFS {
		unknown.mount_specifier(parent, 'unknown', 'not-exported', 0, '') or {
			refused = true
			assert errno.get() == errno.enodev
		}
	}
	assert refused
	mut incompatible := template.instantiate()
	refused = false
	if mut incompatible is NinePFS {
		incompatible.mount_specifier(parent, 'bad-options', 'tag-a', 0, 'msize=8192') or {
			refused = true
			assert errno.get() == errno.ebusy
		}
	}
	assert refused
	read_text(mut af, 'AAA')
	// This is the actual backend detach callback; the guest probe exercises
	// the complete VFS umount syscall separately.
	ar.filesystem.check_unmount() or { panic('detach a') }
	read_text(mut bf, 'BBB')
	assert bf.write(unsafe { nil }, c'CCC', 0, 3) or { i64(-1) } == 3
	read_text(mut bf, 'CCC')
	// Namespace mutations are also confined to the corresponding tag.
	created := br.filesystem.create(b, 'only-b', stat.ifreg | 0o644)
	assert created != unsafe { nil }
	publish_child(b, 'only-b', created)
	ar.snapshot_permissions(mut acl) or { panic('refresh a') }
	assert lookup_child_synced(a, 'only-b') == unsafe { nil }
	mut created_res := ninep_resource(created)
	assert created_res.refcount == 1 && created_res.box.refcount == 1
	created_res.unlink(voidptr(created)) or { panic('unlink only-b') }
	remove_child(b, 'only-b')
	mut removed := unsafe { created }
	removed.orphan = true
	created_res.unref(unsafe { nil }) or { panic('free resource with interior adapter') }
	read_text(mut bf, 'CCC')
	println('MULTITAG-FACADE-PASS distinct adapters/channels/devices; independent IO; same-tag remount; ENODEV; detach isolation')
}
