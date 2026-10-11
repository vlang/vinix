// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import desktop.workflowcore

struct FilesVolume {
	path string
	label string
	action string
	device u64
	inode u64
	network bool
	removable bool
}

fn (mut a FilesContextApp) clear_volumes() {
	for volume in a.volumes { unsafe { volume.path.free(); volume.label.free(); volume.action.free() } }
	a.volumes.clear()
}

fn (mut a FilesContextApp) refresh_volumes() {
	a.clear_volumes()
	mut inventory := DiskUtilityApp{}
	inventory.collect_mounts('/proc/mounts')
	defer { inventory.close_app() }
	for mount in inventory.mounts {
		if mount.filesystem in ['proc', 'sysfs', 'devtmpfs', 'devpts', 'cgroup', 'cgroup2'] { continue }
		info := workflowcore.identify(mount.target) or { continue }
		if !info.directory() { continue }
		network := mount.filesystem in ['nfs', 'nfs4', 'cifs', 'smb3', 'sshfs', 'fuse.sshfs', '9p']
		removable := mount.target.starts_with('/media/') || mount.target.starts_with('/mnt/') || mount.target.starts_with('/run/media/')
		index := a.volumes.len.str()
		kind := if network { 'Network' } else if removable { 'Removable' } else { 'Local' }
		a.volumes << FilesVolume{path: mount.target.clone(), label: '${mount.target} (${kind}, ${mount.filesystem})', action: 'files.volume.${index}', device: info.device, inode: info.inode, network: network, removable: removable}
		unsafe { index.free() }
	}
}

fn files_volume_trash(root string) FilesTrash {
	mut trash := FilesTrash{home: reminders_canonical_home(root), home_alias: root.clone()}
	uid := C.getuid().str()
	trash.store_name = '.vinix-trash-${uid}'
	unsafe { uid.free() }
	trash.home_fd = C.open(&char(trash.home.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if trash.home_fd < 0 { trash.status = 'files.trash.unavailable' }
	return trash
}

// Choose the longest live mount root, so nested/remounted devices never fall
// back to a different volume's Trash. Home remains compatible with old records.
fn (mut a FilesContextApp) trash_for_path(path string) {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	mut root := home
	if !file_context_path_inside(path, home) {
		a.refresh_volumes()
		root = ''
		for volume in a.volumes {
			if file_context_path_inside(path, volume.path) && volume.path.len > root.len { root = volume.path }
		}
		if root == '' { a.trash.status = 'files.trash.unavailable'; return }
	} else {
		// A removable mount beneath Home still owns its own Trash.
		a.refresh_volumes()
		for volume in a.volumes {
			if volume.path.len > home.len && file_context_path_inside(path, volume.path) && volume.path.len > root.len { root = volume.path }
		}
	}
	if a.trash.home_alias == root && a.trash.home_fd >= 0 { return }
	owned := root.clone()
	a.trash.close()
	a.trash = if owned == home { files_trash_new(owned) } else { files_volume_trash(owned) }
	unsafe { owned.free() }
}

fn (a &FilesContextApp) volumes_panel(size ui2.Rect) ui2.Element {
	mut rows := frame_elements(a.volumes.len + 3)
	rows << ui2.button('files.volumes.close', 'Close', ui2.rect(8, 8, 100, 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
	rows << ui2.button('files.volumes.refresh', 'Refresh volumes', ui2.rect(116, 8, 160, 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
	for i, volume in a.volumes {
		if 44 + (i + 1) * 32 > int(size.height) { break }
		rows << ui2.button(volume.action, volume.label, ui2.rect(8, f64(44 + i * 32), size.width - 16, 30), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12, align: .left})
	}
	return ui2.screen(app_surface, rows)
}

fn (mut a FilesContextApp) volume_action(event string) bool {
	if event == 'files.volumes.open' || event == 'files.volumes.refresh' { a.refresh_volumes(); a.volumes_open = true; return true }
	if event == 'files.volumes.close' { a.volumes_open = false; return true }
	if !event.starts_with('files.volume.') { return false }
	index := event['files.volume.'.len..].int()
	if index < 0 || index >= a.volumes.len { return true }
	volume := a.volumes[index]
	current := workflowcore.identify(volume.path) or { a.trash.status = 'files.trash.unavailable'; return true }
	if current.device != volume.device || current.inode != volume.inode || !current.directory() {
		a.trash.status = 'files.trash.unavailable'
		return true
	}
	a.files.navigate_to(volume.path)
	a.volumes_open = false
	a.clear_context_path()
	return true
}
