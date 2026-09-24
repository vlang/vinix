// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A cgroup v2 hierarchy: the single unified tree Linux mounts at
// /sys/fs/cgroup.
//
// A container runtime makes a cgroup by creating a directory, joins a process
// to it by writing the pid into cgroup.procs, and sets limits by writing the
// controller files. Vinix keeps the tree and the membership faithfully -- a
// process belongs to exactly one group, its children are born into it, and
// cgroup.procs and cgroup.events report who is there -- and cgroup.kill kills a
// group's processes, which is how a runtime tears a container down. Controller
// limits are stored as the text last written to them and read back, but are
// not enforced: the accounting a controller would need is not collected.
@[has_globals]
module fs

import stat
import klock
import katomic
import errno
import proc
import resource
import event.eventstruct

const cgroup_controllers = ['cpuset', 'cpu', 'io', 'memory', 'pids']

// The interface files every cgroup directory has. The generated ones are
// answered from the tree; the rest read back what was last written, starting
// from the value an unconfigured Linux cgroup shows.
const cgroup_default_files = {
	'cgroup.controllers':     ''
	'cgroup.subtree_control': ''
	'cgroup.procs':           ''
	'cgroup.threads':         ''
	'cgroup.events':          ''
	'cgroup.freeze':          '0'
	'cgroup.kill':            ''
	'cgroup.type':            'domain'
	'cgroup.max.depth':       'max'
	'cgroup.max.descendants': 'max'
	'cgroup.stat':            ''
	'memory.max':             'max'
	'memory.min':             '0'
	'memory.low':             '0'
	'memory.high':            'max'
	'memory.current':         '0'
	'memory.peak':            '0'
	'memory.swap.max':        'max'
	'memory.swap.current':    '0'
	'memory.events':          'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0'
	'memory.stat':            'anon 0\nfile 0\nkernel 0\nshmem 0'
	'memory.oom.group':       '0'
	'pids.max':               'max'
	'pids.current':           ''
	'pids.peak':              '0'
	'cpu.max':                'max 100000'
	'cpu.max.burst':          '0'
	'cpu.weight':             '100'
	'cpu.weight.nice':        '0'
	'cpu.idle':               '0'
	'cpu.stat':               'usage_usec 0\nuser_usec 0\nsystem_usec 0\nnr_periods 0\nnr_throttled 0\nthrottled_usec 0'
	'io.max':                 ''
	'io.stat':                ''
	'io.weight':              'default 100'
	'cpuset.cpus':            ''
	'cpuset.mems':            ''
	'cpuset.cpus.effective':  ''
	'cpuset.mems.effective':  ''
}

@[heap]
struct CGroupResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	// The group a file belongs to, and the interface file's name. A directory
	// has an empty name.
	group &CGroup = unsafe { nil }
	name  string
	text  string
}

@[heap]
pub struct CGroup {
pub mut:
	lock    klock.Lock
	node    &VFSNode = unsafe { nil }
	parent  &CGroup  = unsafe { nil }
	subtree []string
}

struct CGroupFS {}

__global (
	cgroup_dev_id        u64
	cgroup_inode_counter u64
	cgroup_root_node     &VFSNode
	cgroup_root          &CGroup
	// Set by userland: sends a signal to a process. fs cannot reach the
	// signal code itself, which sits above it.
	cgroup_signal_hook voidptr
)

type CGroupSignalHook = fn (int, int)

pub fn set_cgroup_signal_hook(hook voidptr) {
	cgroup_signal_hook = hook
}

fn (this CGroupFS) instantiate() &FileSystem {
	return &CGroupFS{}
}

fn (this CGroupFS) populate(_node &VFSNode) {}

fn (mut this CGroupFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	return cgroup_mount_root(parent, name)
}

// mkdir under the hierarchy makes a cgroup. A plain file cannot be created.
fn (mut this CGroupFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	if !stat.isdir(mode) || parent.resource == unsafe { nil } {
		errno.set(errno.eperm)
		return unsafe { nil }
	}
	parent_res := unsafe { &CGroupResource(parent.resource) }
	return create_cgroup_directory(parent, name, parent_res.group)
}

fn (mut this CGroupFS) symlink(_parent &VFSNode, _dest string, _target string) &VFSNode {
	errno.set(errno.eperm)
	return unsafe { nil }
}

fn (mut this CGroupFS) link(_parent &VFSNode, _path string, mut _old VFSNode) ?&VFSNode {
	errno.set(errno.eperm)
	return none
}

fn (mut this CGroupFS) rename(_op &VFSNode, _on string, _np &VFSNode, _nn string, _f int) ? {
	errno.set(errno.eperm)
	return none
}

fn new_cgroup_resource(mode u32) &CGroupResource {
	if cgroup_dev_id == 0 {
		cgroup_dev_id = resource.create_dev_id()
	}
	mut res := &CGroupResource{
		refcount: 1
	}
	res.stat.dev = cgroup_dev_id
	res.stat.ino = cgroup_inode_counter
	cgroup_inode_counter++
	res.stat.mode = mode
	res.stat.blksize = 512
	res.stat.size = if stat.isdir(mode) { i64(0) } else { i64(4096) }
	res.stat.nlink = if stat.isdir(mode) { u64(2) } else { u64(1) }
	res.stat.atim = realtime_clock
	res.stat.ctim = realtime_clock
	res.stat.mtim = realtime_clock
	return res
}

// The root of the unified hierarchy. There is one; mounting cgroup2 again
// shows the same tree, or the part of it a cgroup namespace is rooted at.
pub fn cgroup_mount_root(parent &VFSNode, name string) ?&VFSNode {
	if unsafe { cgroup_root_node == 0 } {
		cgroup_root_node = create_cgroup_directory(parent, name, unsafe { nil })
		root_res := unsafe { &CGroupResource(cgroup_root_node.resource) }
		cgroup_root = root_res.group
		// The root delegates every controller, as a systemd-less Linux
		// system configured for containers does.
		cgroup_root.subtree = cgroup_controllers.clone()
	}
	ns_root := cgroup_namespace_root(calling_process())
	if ns_root != unsafe { nil } && ns_root.node != unsafe { nil } {
		return ns_root.node
	}
	return cgroup_root_node
}

fn create_cgroup_directory(parent &VFSNode, name string, parent_group &CGroup) &VFSNode {
	mut node := create_node(unsafe { filesystems['cgroup2'] }, parent, name, true)
	node.resource = new_cgroup_resource(stat.ifdir | 0o755)
	mut group := &CGroup{
		node:   node
		parent: unsafe { parent_group }
	}
	mut dir_res := unsafe { &CGroupResource(node.resource) }
	dir_res.group = group
	for file_name, default in cgroup_default_files {
		// The root has no limits of its own, so it has no controller files.
		if parent_group == unsafe { nil } && file_name.contains('.')
			&& !file_name.starts_with('cgroup.') && !file_name.ends_with('.stat')
			&& !file_name.ends_with('.current') && !file_name.ends_with('.pressure') {
			continue
		}
		mut child := create_node(node.filesystem, node, file_name, false)
		mut res := new_cgroup_resource(if file_name in ['cgroup.controllers', 'cgroup.events',
			'cgroup.stat', 'memory.current', 'memory.stat', 'memory.events', 'pids.current',
			'cpu.stat', 'io.stat', 'cpuset.cpus.effective', 'cpuset.mems.effective'] {
			stat.ifreg | 0o444
		} else if file_name == 'cgroup.kill' {
			stat.ifreg | 0o200
		} else {
			stat.ifreg | 0o644
		})
		res.group = group
		res.name = file_name
		res.text = default
		child.resource = res
		unsafe {
			node.children[file_name] = child
		}
	}
	return node
}

fn cgroup_of_process(process &proc.Process) &CGroup {
	if process == unsafe { nil } || process.cgroup == unsafe { nil } {
		return cgroup_root
	}
	return unsafe { &CGroup(process.cgroup) }
}

// The group a cgroup namespace is rooted at, nil for the initial one.
fn cgroup_namespace_root(process &proc.Process) &CGroup {
	if process == unsafe { nil } || process.ns.cgroup == unsafe { nil }
		|| process.ns.cgroup.data == unsafe { nil } {
		return unsafe { nil }
	}
	return unsafe { &CGroup(process.ns.cgroup.data) }
}

// A new cgroup namespace is rooted wherever its creator was.
pub fn cgroup_namespace_data(process &proc.Process) voidptr {
	group := cgroup_of_process(process)
	if group == cgroup_root {
		return unsafe { nil }
	}
	return voidptr(group)
}

fn (group &CGroup) is_within(ancestor &CGroup) bool {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(ancestor) {
			return true
		}
		current = current.parent
	}
	return ancestor == unsafe { nil }
}

// The path of a group from `root`, as /proc/<pid>/cgroup shows it.
fn cgroup_path(group &CGroup, root &CGroup) string {
	mut names := []string{}
	mut current := unsafe { group }
	for current != unsafe { nil } && current.parent != unsafe { nil }
		&& voidptr(current) != voidptr(root) {
		names << current.node.name
		current = current.parent
	}
	if voidptr(current) != voidptr(root) && root != unsafe { nil } && root != cgroup_root {
		// Outside the reader's namespace: Linux shows the path relative to the
		// namespace root with leading `..` components; the plain path will do.
		return cgroup_path(group, cgroup_root)
	}
	mut path := ''
	for i := names.len - 1; i >= 0; i-- {
		path += '/' + names[i]
	}
	return if path.len == 0 { '/' } else { path }
}

// /proc/<pid>/cgroup.
pub fn process_cgroup_text(pid int) string {
	proc.lock_table()
	process := proc.process_at(pid)
	proc.unlock_table()
	if process == unsafe { nil } {
		return ''
	}
	group := cgroup_of_process(process)
	root := cgroup_namespace_root(calling_process())
	return '0::${cgroup_path(group, root)}\n'
}

// The pids whose group is `group`, or any group below it with `recursive`.
fn cgroup_members(group &CGroup, recursive bool) []int {
	mut members := []int{}
	proc.lock_table()
	defer { proc.unlock_table() }
	for pid := 1; pid < proc.max_pid; pid++ {
		process := proc.process_at(pid)
		if process == unsafe { nil } || process.exiting || unsafe { process.pagemap == nil } {
			continue
		}
		member_of := cgroup_of_process(process)
		if voidptr(member_of) == voidptr(group) || (recursive && member_of.is_within(group)) {
			members << pid
		}
	}
	return members
}

fn cgroup_has_children(group &CGroup) bool {
	for name in group.node.children.keys() {
		if is_dot_name(name) {
			continue
		}
		child := unsafe { group.node.children[name] }
		if child.resource != unsafe { nil } && stat.isdir(child.resource.stat.mode) {
			return true
		}
	}
	return false
}

fn (mut this CGroupResource) contents() string {
	mut group := this.group
	match this.name {
		'cgroup.procs', 'cgroup.threads' {
			mut text := ''
			for pid in cgroup_members(group, false) {
				text += '${pid}\n'
			}
			return text
		}
		'cgroup.events' {
			populated := if cgroup_members(group, true).len > 0 { 1 } else { 0 }
			frozen := if group.node != unsafe { nil } && unsafe { 'cgroup.freeze' in *group.node.children } {
				freeze_res := unsafe { &CGroupResource(group.node.children['cgroup.freeze'].resource) }
				freeze_res.text.trim_space()
			} else {
				'0'
			}
			return 'populated ${populated}\nfrozen ${frozen}\n'
		}
		'cgroup.controllers' {
			available := if group.parent == unsafe { nil } {
				cgroup_controllers
			} else {
				group.parent.subtree
			}
			return available.join(' ') + '\n'
		}
		'cgroup.subtree_control' {
			group.lock.acquire()
			defer { group.lock.release() }
			return group.subtree.join(' ') + '\n'
		}
		'pids.current' {
			return '${cgroup_members(group, true).len}\n'
		}
		'cgroup.stat' {
			mut descendants := 0
			for name in group.node.children.keys() {
				if is_dot_name(name) { continue }
				child := unsafe { group.node.children[name] }
				if child.resource != unsafe { nil } && stat.isdir(child.resource.stat.mode) {
					descendants++
				}
			}
			return 'nr_descendants ${descendants}\nnr_dying_descendants 0\n'
		}
		else {}
	}
	if this.text.len == 0 {
		return ''
	}
	return this.text + '\n'
}

fn (mut this CGroupResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	text := this.contents()
	if loc >= u64(text.len) {
		return i64(0)
	}
	mut actual := count
	if loc + actual > u64(text.len) {
		actual = u64(text.len) - loc
	}
	unsafe { C.memcpy(buf, &u8(text.str) + loc, actual) }
	return i64(actual)
}

fn (mut this CGroupResource) write(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	if count == 0 {
		return 0
	}
	mut incoming := []u8{len: int(count)}
	unsafe { C.memcpy(&incoming[0], buf, count) }
	value := incoming.bytestr().trim_space()
	mut group := this.group

	match this.name {
		'cgroup.procs', 'cgroup.threads' {
			pid := value.int()
			if pid < 0 || (pid == 0 && value != '0') {
				errno.set(errno.einval)
				return none
			}
			target := if pid == 0 { calling_process().pid } else { pid }
			if !move_to_cgroup(mut group, target) {
				errno.set(errno.esrch)
				return none
			}
			return i64(count)
		}
		'cgroup.subtree_control' {
			available := if group.parent == unsafe { nil } {
				cgroup_controllers
			} else {
				group.parent.subtree
			}
			group.lock.acquire()
			defer { group.lock.release() }
			for token in value.fields() {
				if token.len < 2 || (token[0] != `+` && token[0] != `-`) {
					errno.set(errno.einval)
					return none
				}
				name := token[1..]
				if name !in available {
					errno.set(errno.enoent)
					return none
				}
				index := group.subtree.index(name)
				if token[0] == `+` && index < 0 {
					group.subtree << name
				} else if token[0] == `-` && index >= 0 {
					group.subtree.delete(index)
				}
			}
			return i64(count)
		}
		'cgroup.kill' {
			if value != '1' {
				errno.set(errno.einval)
				return none
			}
			kill_cgroup(group)
			return i64(count)
		}
		'cgroup.freeze' {
			if value != '0' && value != '1' {
				errno.set(errno.einval)
				return none
			}
			this.text = value
			return i64(count)
		}
		else {}
	}
	if this.stat.mode & 0o222 == 0 {
		errno.set(errno.eacces)
		return none
	}
	// Limits are recorded so a runtime reads back what it set.
	this.text = value
	return i64(count)
}

fn move_to_cgroup(mut group CGroup, pid int) bool {
	proc.lock_table()
	defer { proc.unlock_table() }
	mut process := proc.process_at(pid)
	if process == unsafe { nil } {
		return false
	}
	process.cgroup = if voidptr(group) == voidptr(cgroup_root) { unsafe { nil } } else { voidptr(group) }
	return true
}

// CLONE_INTO_CGROUP: the group a directory descriptor names, or none.
pub fn cgroup_from_node(node &VFSNode) ?voidptr {
	if node == unsafe { nil } || node.resource == unsafe { nil }
		|| !is_cgroup_resource(node.resource) || !stat.isdir(node.resource.stat.mode) {
		return none
	}
	res := unsafe { &CGroupResource(node.resource) }
	if voidptr(res.group) == voidptr(cgroup_root) {
		return unsafe { nil }
	}
	return voidptr(res.group)
}

fn kill_cgroup(group &CGroup) {
	if cgroup_signal_hook == unsafe { nil } {
		return
	}
	hook := unsafe { CGroupSignalHook(cgroup_signal_hook) }
	for pid in cgroup_members(group, true) {
		hook(pid, 9)
	}
}

// rmdir(2) of a cgroup: allowed once it has no processes and no child
// groups, and it takes its interface files with it.
pub fn cgroup_may_remove(node &VFSNode) ?bool {
	if node.resource == unsafe { nil } || !is_cgroup_resource(node.resource)
		|| !stat.isdir(node.resource.stat.mode) {
		return false
	}
	res := unsafe { &CGroupResource(node.resource) }
	group := res.group
	if group == unsafe { nil } || group.parent == unsafe { nil } {
		errno.set(errno.ebusy)
		return none
	}
	if cgroup_has_children(group) || cgroup_members(group, true).len > 0 {
		errno.set(errno.ebusy)
		return none
	}
	mut dir := unsafe { node }
	mut names := []string{}
	for name in dir.children.keys() {
		if !is_dot_name(name) {
			names << name
		}
	}
	for name in names {
		dir.children.delete(name)
	}
	return true
}

fn (mut this CGroupResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this CGroupResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this CGroupResource) grow(_handle voidptr, _new_size u64) ? {
	return
}

fn (mut this CGroupResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this CGroupResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this CGroupResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this CGroupResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type:   0x63677270 // CGROUP2_SUPER_MAGIC
		bsize:   page_size
		namelen: 255
		frsize:  page_size
	}
}

fn is_cgroup_resource(res &resource.Resource) bool {
	return res.stat.dev == cgroup_dev_id && cgroup_dev_id != 0
}
