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
// group's processes, which is how a runtime tears a container down.
//
// Hierarchical task/kernel-memory admission and swap/I/O accounting share the
// cgcontrol lock. Scheduler boundaries enforce cpu.max, freeze, memory.high
// and completed disk service debt. Anonymous memory includes resident and
// paged backing; OOM recovery signals victims outside accounting locks.
// resource.pressure provides bounded independent pollable subscriptions.
// See docs/resource-groups.md for interface details and remaining limits.
@[has_globals]
module fs

import stat
import klock
import cgcontrol
import katomic
import errno
import lib
import proc
import resource
import event.eventstruct
import numa
import memory.mmap
import time
import kbudget

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
	'resource.pressure':      ''
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
	'pids.events':            'max 0'
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
	text_owned bool
	text_charge kbudget.Charge
	box &resource.Resource = unsafe { nil }
}

@[heap]
pub struct CGroup {
pub mut:
	kernel_charge kbudget.Charge
	depth int
	descendants u64
	max_depth u64 = ~u64(0)
	max_descendants u64 = ~u64(0)
	removed bool
	lock    klock.Lock
	node    &VFSNode = unsafe { nil }
	parent  &CGroup  = unsafe { nil }
	next_account &CGroup = unsafe { nil }
	subtree []string
	// What its limits are and what it has used; nil for the root, which has
	// no limits.
	account &proc.CGroupAccount = unsafe { nil }
}

struct CGroupFS {}

__global (
	cgroup_dev_id        u64
	cgroup_inode_counter u64
	cgroup_root_node     &VFSNode
	cgroup_root          &CGroup
	cgroup_hierarchy_lock klock.Lock
	cgroup_mount_lock klock.Lock
	cgroup_accounts &CGroup = unsafe { nil }
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
	res.stat.ino = cgroup_inode_counter++
	res.stat.mode = mode
	res.stat.blksize = 512
	res.stat.size = if stat.isdir(mode) { i64(0) } else { i64(4096) }
	res.stat.nlink = if stat.isdir(mode) { u64(2) } else { u64(1) }
	res.stat.atim = realtime_clock
	res.stat.ctim = realtime_clock
	res.stat.mtim = realtime_clock
	res.box = &resource.Resource(res)
	return res
}

// The root of the unified hierarchy. There is one; mounting cgroup2 again
// shows the same tree, or the part of it a cgroup namespace is rooted at.
pub fn cgroup_mount_root(parent &VFSNode, name string) ?&VFSNode {
	cgroup_mount_lock.acquire()
	defer { cgroup_mount_lock.release() }
	if unsafe { cgroup_root_node == 0 } {
		cgroup_root_node = create_cgroup_directory(parent, name, unsafe { nil })
		if cgroup_root_node == unsafe { nil } { return none }
		root_res := unsafe { &CGroupResource(cgroup_root_node.resource) }
		cgroup_root = root_res.group
		// The root delegates every controller, as a systemd-less Linux
		// system configured for containers does.
		cgroup_root.subtree = cgroup_controllers.clone()
		proc.set_cgroup_memory_hook(voidptr(cgroup_memory_check))
	}
	ns_root := cgroup_namespace_root(calling_process())
	if ns_root != unsafe { nil } && ns_root.node != unsafe { nil } {
		return ns_root.node
	}
	return cgroup_root_node
}

fn create_cgroup_directory(parent &VFSNode, name string, parent_group &CGroup) &VFSNode {
	cgroup_hierarchy_lock.acquire()
	defer { cgroup_hierarchy_lock.release() }
	depth := if parent_group == unsafe { nil } { 0 } else { parent_group.depth + 1 }
	if depth > 64 || (parent_group != unsafe { nil } && parent_group.removed) {
		errno.set(errno.enospc)
		return unsafe { nil }
	}
	mut ancestor := unsafe { parent_group }
	for ancestor != unsafe { nil } {
		if u64(depth - ancestor.depth) > ancestor.max_depth || ancestor.descendants >= ancestor.max_descendants {
			errno.set(errno.enospc)
			return unsafe { nil }
		}
		ancestor = ancestor.parent
	}
	// These objects remain reachable through namespaces, stale directory
	// descriptors and asynchronous paging/writeback after rmdir. Charge that
	// existing mount lifetime in full, rather than only the outer VFS node.
	bytes := u64(sizeof(CGroup) + sizeof(proc.CGroupAccount)) * 2 + 16384
		+ u64(cgroup_default_files.len + 1) * (u64(sizeof(VFSNode) + sizeof(CGroupResource) + sizeof(resource.Resource)) * 2 + 512)
	charge := proc.reserve_kernel(.file, bytes) or { return unsafe { nil } }
	mut node := create_node(unsafe { filesystems['cgroup2'] }, parent, name, true)
	node.resource = new_cgroup_resource(stat.ifdir | 0o755).box
	mut group := &CGroup{
		kernel_charge: charge
		depth: depth
		node:   node
		parent: unsafe { parent_group }
	}
	if parent_group != unsafe { nil } {
		group.account = proc.new_cgroup_account(parent_group.account)
		group.account.group_data = voidptr(group)
	}
	mut dir_res := unsafe { &CGroupResource(node.resource) }
	dir_res.group = group
	for file_name, default in cgroup_default_files {
		if parent_group == unsafe { nil } && file_name == 'resource.pressure' { continue }
		// The root has no limits of its own, so it has no controller files.
		if parent_group == unsafe { nil } && file_name.contains('.')
			&& !file_name.starts_with('cgroup.') && !file_name.ends_with('.stat')
			&& !file_name.ends_with('.current') && !file_name.ends_with('.pressure')
			&& !file_name.ends_with('.effective') {
			continue
		}
		mut child := create_node(node.filesystem, node, file_name, false)
		mut res := new_cgroup_resource(if cgroup_read_only_file(file_name) {
			stat.ifreg | 0o444
		} else if file_name == 'cgroup.kill' {
			stat.ifreg | 0o200
		} else {
			stat.ifreg | 0o644
		})
		res.group = group
		res.name = file_name
		res.text = default
		child.resource = res.box
		unsafe {
			node.children[file_name] = child
		}
	}
	ancestor = unsafe { parent_group }
	for ancestor != unsafe { nil } { ancestor.descendants++; ancestor = ancestor.parent }
	group.next_account = cgroup_accounts
	cgroup_accounts = group
	return node
}

// The interface files that only report. A match rather than `in` an array
// literal, which was made for every file of every group.
fn cgroup_read_only_file(name string) bool {
	return match name {
		'cgroup.controllers', 'cgroup.events', 'cgroup.stat', 'memory.current', 'memory.stat',
		'memory.events', 'memory.peak', 'pids.current', 'pids.events', 'cpu.stat', 'io.stat',
		'cpuset.cpus.effective', 'cpuset.mems.effective', 'resource.pressure', 'pids.peak', 'memory.swap.current' {
			true
		}
		else {
			false
		}
	}
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

// The path of a group from `root`, as /proc/<pid>/cgroup shows it, added to
// `text`. The groups are collected rather than their names, which pushing
// would have copied, and the path is made in the one buffer.
fn add_cgroup_path(mut text lib.Text, group &CGroup, root &CGroup) {
	mut groups := []&CGroup{cap: 16} @[freed]
	groups.flags |= .noslices
	defer {
		unsafe { groups.free() }
	}
	mut current := unsafe { group }
	for current != unsafe { nil } && current.parent != unsafe { nil }
		&& voidptr(current) != voidptr(root) {
		groups << current
		current = current.parent
	}
	if voidptr(current) != voidptr(root) && root != unsafe { nil } && root != cgroup_root {
		// Outside the reader's namespace: Linux shows the path relative to the
		// namespace root with leading `..` components; the plain path will do.
		add_cgroup_path(mut text, group, cgroup_root)
		return
	}
	if groups.len == 0 {
		text.add_byte(`/`)
		return
	}
	for i := groups.len - 1; i >= 0; i-- {
		text.add_byte(`/`)
		text.add(groups[i].node.name)
	}
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
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(64) }
	text.add('0::')
	add_cgroup_path(mut text, group, root)
	text.add_byte(`\n`)
	return text.str()
}

// The pids whose group is `group`, or any group below it with `recursive`.
fn cgroup_members(group &CGroup, recursive bool) []int {
	mut members := []int{} @[freed]
	members.flags |= .noslices
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

fn append_decimal(mut text []u8, value int) {
	mut digits := [12]u8{}
	mut n := 0
	mut rest := value
	for {
		digits[n] = u8(`0` + rest % 10)
		n++
		rest /= 10
		if rest == 0 || n == digits.len {
			break
		}
	}
	for n > 0 {
		n--
		text << digits[n]
	}
}

// Logical committed anonymous memory, including nonresident backing.
fn anonymous_bytes_of(pid int) u64 {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	mut process := proc.process_at(pid)
	return anonymous_bytes_locked(mut process)
}

// pid_lock keeps membership and map lifetime stable until the aggregate is
// published. A busy map retains its previous count rather than admitting zero.
fn anonymous_bytes_locked(mut process proc.Process) u64 {
	if process == unsafe { nil } || process.exiting || unsafe { process.pagemap == nil } {
		return 0
	}
	usage := mmap.anonymous_usage(process.pagemap) or {
		return process.cgroup_anonymous_bytes
	}
	process.cgroup_anonymous_bytes = usage.resident + usage.paged
	process.cgroup_paged_bytes = usage.paged
	return process.cgroup_anonymous_bytes
}

fn cgroup_memory_bytes(group &CGroup) u64 {
	proc.lock_table()
	defer { proc.unlock_table() }
	mut total := u64(0)
	for pid := 1; pid < proc.max_pid; pid++ {
		mut process := proc.process_at(pid)
		if process == unsafe { nil } || process.exiting { continue }
		if cgroup_of_process(process).is_within(group) { total += anonymous_bytes_locked(mut process) }
	}
	if group.account != unsafe { nil } {
		mut account := group.account
		cgcontrol.sample_memory(mut account.control, total)
		return total + cgcontrol.snapshot(proc.cgroup_control(account)).kernel
	}
	return total + kbudget.snapshot().bytes
}

// The CPUs or memory nodes a group may use: the ones its cpuset names, or
// failing that its parent's, and at the root every one there is: `last` and
// all below it. Vinix does not confine a group to them.
fn cgroup_cpuset_effective(group &CGroup, file_name string, last int) string {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if current.node != unsafe { nil } && file_name in current.node.children {
			res := unsafe { &CGroupResource(current.node.children[file_name].resource) }
			if res.text.len > 0 {
				return text_line(res.text)
			}
		}
		current = current.parent
	}
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(24) }
	text.add_byte(`0`)
	if last > 0 {
		text.add_byte(`-`)
		text.add_decimal(i64(last))
	}
	text.add_byte(`\n`)
	return text.str()
}

// `line` and a newline, as a new string.
fn text_line(line string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(line.len + 1) }
	text.add(line)
	text.add_byte(`\n`)
	return text.str()
}

// `value` in decimal after `label`, and a newline, as a new string.
fn labelled_decimal(label string, value u64) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(label.len + 24) }
	text.add(label)
	text.add_unsigned(value)
	text.add_byte(`\n`)
	return text.str()
}

// The names in `names`, space separated, and a newline.
fn joined_line(names []string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(names.len * 8 + 1) }
	for i, name in names {
		if i > 0 {
			text.add_byte(` `)
		}
		text.add(name)
	}
	text.add_byte(`\n`)
	return text.str()
}

// The processes in `account` and the groups below it.
fn account_members(account &proc.CGroupAccount) []int {
	mut members := []int{} @[freed]
	members.flags |= .noslices
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	for pid := 1; pid < proc.max_pid; pid++ {
		process := proc.process_at(pid)
		if process == unsafe { nil } || process.exiting || unsafe { process.pagemap == nil } {
			continue
		}
		if proc.process_in_account(process, account) {
			members << pid
		}
	}
	return members
}

fn process_alive(pid int) bool {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	process := proc.process_at(pid)
	return process != unsafe { nil } && !process.exiting
}

// How long a counted usage stays good enough for an allocation that fits under
// the limit with room to spare, and how long a process killed for going over is
// given to exit before another is chosen.
const memory_count_valid_ns = u64(50000000)

const oom_victim_grace_ns = u64(500000000)

// proc.cgroup_charge_memory calls this as `process` commits about `bytes` more.
// Each group above it with a memory.max is checked; false means the caller
// was the one killed.
fn cgroup_memory_check(process &proc.Process, bytes u64) bool {
	now := time.monotonic_ns()
	mut current := process.cgroup_account
	for current != unsafe { nil } {
		limit := katomic.load(&current.memory_max)
		if limit != 0 && !enforce_memory_max(mut current, bytes, limit, now, process.pid) { return false }
		mut sample := cgcontrol.snapshot(proc.cgroup_control(current))
		if sample.memory_high != ~u64(0) {
			if limit == 0 { enforce_memory_max(mut current, bytes, ~u64(0), now, process.pid) }
			sample = cgcontrol.snapshot(proc.cgroup_control(current))
			if sample.anonymous + sample.kernel > sample.memory_high {
				cgcontrol.note_memory(mut current.control, true)
				mut caller_thread := proc.current_thread()
				if caller_thread != unsafe { nil } && voidptr(caller_thread.process) == voidptr(process) { caller_thread.memory_until_ns = now + 10000000 }
			}
		}
		current = current.parent
	}
	return true
}

// Keep `account` within `limit` now that process `caller` has committed about
// `bytes` more (0 for none, when the limit itself was just lowered). Returns
// false only when the caller was killed.
//
// Counting a group means walking its processes' page tables, so growth that
// keeps under the limit on a recent count is added to that count instead. Once
// the count is stale or says the group is over, it is counted afresh, and a
// group still over has its largest process killed, as Linux's OOM killer
// would, or every process with memory.oom.group.
fn enforce_memory_max(mut account proc.CGroupAccount, bytes u64, limit u64, now u64, caller int) bool {
	proc.lock_table()
	account.lock.acquire()
	fresh := account.memory_counted_ns != 0 && now - account.memory_counted_ns < memory_count_valid_ns
	kernel := cgcontrol.snapshot(proc.cgroup_control(account)).kernel
	if fresh && account.memory_counted_bytes + bytes + kernel <= limit {
		account.memory_counted_bytes += bytes
		cgcontrol.sample_memory(mut account.control, account.memory_counted_bytes)
		account.lock.release()
		proc.unlock_table()
		return true
	}
	account.lock.release()

	mut members := []int{} @[freed]
	members.flags |= .noslices
	defer {
		unsafe { members.free() }
	}
	mut usage := u64(0)
	mut largest_pid := 0
	mut largest := u64(0)
	for pid := 1; pid < proc.max_pid; pid++ {
		mut process := proc.process_at(pid)
		if process == unsafe { nil } || process.exiting || process.pagemap == unsafe { nil }
			|| !proc.process_in_account(process, &account) { continue }
		members << pid
		used := anonymous_bytes_locked(mut process)
		usage += used
		if used > largest || largest_pid == 0 {
			largest = used
			largest_pid = pid
		}
	}

	account.lock.acquire()
	cgcontrol.sample_memory(mut account.control, usage)
	account.memory_counted_bytes = usage
	usage += cgcontrol.snapshot(proc.cgroup_control(account)).kernel
	account.memory_counted_ns = now
	if usage > account.memory_peak {
		account.memory_peak = usage
	}
	if usage <= limit {
		account.lock.release()
		proc.unlock_table()
		return true
	}
	account.memory_events_max++
	cgcontrol.note_memory(mut account.control, false)
	// The last victim may still be on its way out, and what it frees has not
	// come back yet. Killing another now would take two for one excess.
	if account.oom_victim_pid != 0 && now - account.oom_victim_ns < oom_victim_grace_ns
		 {
		victim := account.oom_victim_pid
		account.lock.release()
		proc.unlock_table()
		return caller != victim
	}
	if largest_pid == 0 {
		account.lock.release()
		proc.unlock_table()
		return true
	}
	account.memory_events_oom++
	whole_group := account.memory_oom_group
	account.oom_victim_pid = largest_pid
	account.oom_victim_ns = now
	account.memory_events_oom_kill += if whole_group { u64(members.len) } else { u64(1) }
	account.lock.release()
	proc.unlock_table()

	if cgroup_signal_hook == unsafe { nil } {
		return true
	}
	hook := unsafe { CGroupSignalHook(cgroup_signal_hook) }
	if whole_group {
		for pid in members {
			hook(pid, 9)
		}
		return caller == 0 || caller !in members
	}
	hook(largest_pid, 9)
	return caller != largest_pid
}

// Gone through by value: keys() copied every name, and nothing freed them.
fn cgroup_has_children(group &CGroup) bool {
	for _, child in group.node.children {
		if child == unsafe { nil } || is_dot_name(child.name) {
			continue
		}
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
			members := cgroup_members(group, false)
			defer {
				unsafe { members.free() }
			}
			mut text := []u8{cap: members.len * 8} @[freed]
			defer {
				unsafe { text.free() }
			}
			// As the reader's pid namespace numbers them; a container sees its
			// own.
			for pid in members {
				number := proc.pid_seen_by_caller(pid)
				if number <= 0 {
					continue
				}
				append_decimal(mut text, number)
				text << `\n`
			}
			return text.bytestr()
		}
		'cgroup.events' {
			members := cgroup_members(group, true)
			populated := if members.len > 0 { 1 } else { 0 }
			unsafe { members.free() }
			// Frozen by its own cgroup.freeze or an ancestor's. runc pause polls
			// for this once it has written cgroup.freeze.
			frozen := if group.account != unsafe { nil } && group.account.is_frozen() { 1 } else { 0 }
			mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
			unsafe { *text = lib.new_text(32) }
			text.add('populated ')
			text.add_decimal(i64(populated))
			text.add('\nfrozen ')
			text.add_decimal(i64(frozen))
			text.add_byte(`\n`)
			return text.str()
		}
		// These are made for every read and freed by it, so each is built
		// without the strings an interpolated number or a join leaves behind.
		'cgroup.controllers' {
			if group.parent != unsafe { nil } { group.parent.lock.acquire() }
			defer { if group.parent != unsafe { nil } { group.parent.lock.release() } }
			available := if group.parent == unsafe { nil } {
				cgroup_controllers
			} else {
				group.parent.subtree
			}
			return joined_line(available)
		}
		'cgroup.subtree_control' {
			group.lock.acquire()
			defer { group.lock.release() }
			return joined_line(group.subtree)
		}
		// Tasks, which is to say threads, as Linux counts them.
		'pids.current' {
			return labelled_decimal('', u64(cgroup_task_count(group)))
		}
		'pids.events' {
			if group.account == unsafe { nil } {
				return 'max 0\n'
			}
			return labelled_decimal('max ', cgcontrol.snapshot(proc.cgroup_control(group.account)).pids_events)
		}
		'pids.peak' {
			return labelled_decimal('', cgcontrol.snapshot(proc.cgroup_control(group.account)).pids_peak)
		}
		'io.max', 'io.stat' {
			return cgroup_io_text(group.account, this.name == 'io.max')
		}
		'memory.swap.current' {
			return labelled_decimal('', if group.account == unsafe { nil } { cgroup_paged_bytes(group) } else { cgcontrol.snapshot(proc.cgroup_control(group.account)).swap })
		}
		'cpu.stat' {
			if group.account == unsafe { nil } {
				return text_line(this.text)
			}
			mut account := group.account
			return account.cpu_stat_text()
		}
		'memory.events' {
			if group.account == unsafe { nil } {
				return text_line(this.text)
			}
			account := group.account
			mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
			unsafe { *text = lib.new_text(96) }
			sample := cgcontrol.snapshot(proc.cgroup_control(account))
			text.add('low 0\nhigh ')
			text.add_unsigned(sample.high_events)
			text.add('\nmax ')
			text.add_unsigned(sample.memory_events)
			text.add('\noom ')
			text.add_unsigned(account.memory_events_oom)
			text.add('\noom_kill ')
			text.add_unsigned(account.memory_events_oom_kill)
			text.add('\noom_group_kill 0\n')
			return text.str()
		}
		'memory.peak' {
			cgroup_memory_bytes(group)
			if group.account == unsafe { nil } {
				return '0\n'
			}
			return labelled_decimal('', cgcontrol.snapshot(proc.cgroup_control(group.account)).memory_peak)
		}
		// The anonymous memory the group's processes have resident, the same
		// figure memory.max is held to. docker stats reads this.
		'memory.current' {
			return labelled_decimal('', cgroup_memory_bytes(group))
		}
		'memory.stat' {
			mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
			unsafe { *text = lib.new_text(64) }
			text.add('anon ')
			current := cgroup_memory_bytes(group)
			sample := cgcontrol.snapshot(proc.cgroup_control(group.account))
			kernel := if group.account == unsafe { nil } { kbudget.snapshot().bytes } else { sample.kernel }
			text.add_unsigned(if group.account == unsafe { nil } { if current > kernel { current - kernel } else { u64(0) } } else { sample.anonymous })
			text.add('\nfile 0\nkernel ')
			text.add_unsigned(kernel)
			text.add('\nshmem 0\nanon_paged ')
			text.add_unsigned(cgroup_paged_bytes(group))
			text.add_byte(`\n`)
			return text.str()
		}
		// Docker checks --cpuset-cpus against the root's before it makes a
		// container.
		'cpuset.cpus.effective' {
			return cgroup_cpuset_effective(group, 'cpuset.cpus', numa.cpu_count() - 1)
		}
		'cpuset.mems.effective' {
			return cgroup_cpuset_effective(group, 'cpuset.mems', 0)
		}
		'cgroup.stat' {
			cgroup_hierarchy_lock.acquire()
			descendants := group.descendants
			cgroup_hierarchy_lock.release()
			mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
			unsafe { *text = lib.new_text(48) }
			text.add('nr_descendants ')
			text.add_decimal(i64(descendants))
			text.add('\nnr_dying_descendants 0\n')
			return text.str()
		}
		else {}
	}
	if this.text.len == 0 {
		return ''
	}
	return text_line(this.text)
}

fn (mut this CGroupResource) replace_text(value string, owned bool, charge kbudget.Charge) bool {
	if this.text_owned { free_charged_after_grace(voidptr(this.text.str), this.text_charge) }
	this.text = value
	this.text_owned = owned && value.len != 0
	this.text_charge = if this.text_owned { charge } else { kbudget.Charge{} }
	return this.text_owned
}

fn (mut this CGroupResource) open(flags int) ?&resource.Resource {
	if this.name != 'resource.pressure' || flags & resource.o_path != 0 { return this.box }
	if flags & resource.o_accmode != resource.o_rdonly { errno.set(errno.eacces); return none }
	return open_cgroup_pressure(this.group, this.stat)
}

fn (mut this CGroupResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	this.l.acquire()
	defer { this.l.release() }
	// Every read makes the text afresh, and it is only needed until copied.
	text := this.contents()
	defer {
		unsafe { text.free() }
	}
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
	if count > 4096 { errno.set(errno.e2big); return none }
	this.l.acquire()
	defer { this.l.release() }
	// Trimmed straight from the buffer: a copy of the bytes and a string of
	// them were left behind by every write. The trimmed value is freed on the
	// way out unless the file keeps it as its text.
	text_charge := proc.reserve_kernel(.file, count * 2 + 512) or { return none }
	mut text_kept := false
	defer { if !text_kept { kbudget.release(text_charge) } }
	written := unsafe { tos(&u8(buf), int(count)) }
	value := written.trim_space()
	mut kept := false
	defer {
		if !kept {
			unsafe { value.free() }
		}
	}
	mut group := this.group

	match this.name {
		'cgroup.max.depth', 'cgroup.max.descendants' {
			limit := if value == 'max' { ~u64(0) } else { cgcontrol.decimal(value) or { errno.set(errno.einval); return none } }
			cgroup_hierarchy_lock.acquire()
			if this.name == 'cgroup.max.depth' { group.max_depth = limit } else { group.max_descendants = limit }
			cgroup_hierarchy_lock.release()
			text_kept = this.replace_text(value, true, text_charge)
			kept = true
			return i64(count)
		}
		'cgroup.procs', 'cgroup.threads' {
			parsed := cgcontrol.decimal(value) or { errno.set(errno.einval); return none }
			if parsed > u64(0x7fffffff) { errno.set(errno.einval); return none }
			pid := int(parsed)
			target := if pid == 0 { calling_process().pid } else { proc.kernel_id(pid) }
			move_to_cgroup(mut group, target)?
			return i64(count)
		}
		'cgroup.subtree_control' {
			if group.parent != unsafe { nil } { group.parent.lock.acquire() }
			defer { if group.parent != unsafe { nil } { group.parent.lock.release() } }
			available := if group.parent == unsafe { nil } {
				cgroup_controllers
			} else {
				group.parent.subtree
			}
			group.lock.acquire()
			defer { group.lock.release() }
			mut tokens := [8]string{}
			n := cgroup_fields(value, unsafe { &tokens })
			if n < 0 { errno.set(errno.einval); return none }
			group.subtree.flags |= .noslices
			for i in 0 .. n {
				token := tokens[i]
				if token.len < 2 || (token[0] != `+` && token[0] != `-`) {
					errno.set(errno.einval)
					return none
				}
				// A view into the token; the list keeps a copy of a name added.
				name := unsafe { tos(token.str + 1, token.len - 1) }
				if name !in available {
					errno.set(errno.enoent)
					return none
				}
				index := group.subtree.index(name)
				if token[0] == `+` && index < 0 {
					group.subtree << cgroup_controllers[cgroup_controllers.index(name)]
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
			if (value != '0' && value != '1') || group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			katomic.store(mut &account.freeze, if value == '1' { u32(1) } else { u32(0) })
			cgcontrol.reconfigured(mut account.control)
			// The text replaced stays: a read may be copying it.
			text_kept = this.replace_text(value, true, text_charge)
			kept = true
			return i64(count)
		}
		'cpu.max' {
			quota_us, period_us := parse_cpu_max(value, group.account) or {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			account.set_cpu_max(quota_us * 1000, period_us * 1000)
			mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
			unsafe { *text = lib.new_text(48) }
			if quota_us == 0 {
				text.add('max')
			} else {
				text.add_unsigned(quota_us)
			}
			text.add_byte(` `)
			text.add_unsigned(period_us)
			text_kept = this.replace_text(text.str(), true, text_charge)
			return i64(count)
		}
		'pids.max' {
			limit := parse_pids_max(value) or {
				errno.set(errno.einval)
				return none
			}
			if group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			katomic.store(mut &account.pids_max, limit)
			text_kept = this.replace_text(if limit < 0 { 'max' } else { decimal_text(u64(limit)) }, limit >= 0, text_charge)
			cgcontrol.set_pids_max(mut account.control, if limit < 0 { ~u64(0) } else { u64(limit) })
			return i64(count)
		}
		'memory.max', 'memory.high' {
			limit := parse_memory_amount(value) or {
				errno.set(errno.einval)
				return none
			}
			if group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			if this.name == 'memory.max' { katomic.store(mut &account.memory_max, limit) }
			cgcontrol.set_memory_limits(mut account.control, if limit == 0 { ~u64(0) } else { limit }, this.name == 'memory.high')
			text_kept = this.replace_text(if limit == 0 { 'max' } else { decimal_text(limit) }, limit != 0, text_charge)
			// A limit lowered below what the group already uses is enforced
			// straight away, as Linux does after it fails to reclaim.
			if limit != 0 && this.name == 'memory.max' {
				enforce_memory_max(mut account, 0, limit, time.monotonic_ns(), 0)
			}
			return i64(count)
		}
		'io.max' {
			if group.account == unsafe { nil } { errno.set(errno.einval); return none }
			limits := parse_io_max(value, group.account) or { errno.set(errno.einval); return none }
			mut account := group.account
			if !cgcontrol.set_io(mut account.control, limits) { errno.set(errno.enospc); return none }
			return i64(count)
		}
		'memory.swap.max' {
			if group.account == unsafe { nil } { errno.set(errno.einval); return none }
			limit := if value == 'max' { ~u64(0) } else { cgcontrol.decimal(value) or { errno.set(errno.einval); return none } }
			mut account := group.account
			cgcontrol.set_swap_max(mut account.control, limit)
			text_kept = this.replace_text(value, true, text_charge)
			kept = true
			return i64(count)
		}
		'memory.oom.group' {
			if (value != '0' && value != '1') || group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			account.memory_oom_group = value == '1'
			text_kept = this.replace_text(value, true, text_charge)
			kept = true
			return i64(count)
		}
		else {}
	}
	if this.stat.mode & 0o222 == 0 {
		errno.set(errno.eacces)
		return none
	}
	// Limits are recorded so a runtime reads back what it set.
	text_kept = this.replace_text(value, true, text_charge)
	kept = true
	return i64(count)
}

// `value` in decimal, as a new string.
fn decimal_text(value u64) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(24) }
	text.add_unsigned(value)
	return text.str()
}

fn move_to_cgroup(mut group CGroup, pid int) ? {
	cgroup_hierarchy_lock.acquire()
	defer { cgroup_hierarchy_lock.release() }
	if group.removed { errno.set(errno.enoent); return none }
	cgroup_memory_bytes(&group)
	proc.lock_table()
	defer { proc.unlock_table() }
	mut process := proc.process_at(pid)
	if process == unsafe { nil } || process.exiting { errno.set(errno.esrch); return none }
	if process.pagemap != unsafe { nil } {
		if usage := mmap.anonymous_usage(process.pagemap) {
			process.cgroup_anonymous_bytes = usage.resident + usage.paged
			process.cgroup_paged_bytes = usage.paged
		}
	}
	if !proc.move_cgroup_locked(mut process, group.account, if voidptr(group) == voidptr(cgroup_root) { unsafe { nil } } else { voidptr(group) }) {
		errno.set(errno.eagain)
		return none
	}
}

// The controller state of the group a CLONE_INTO_CGROUP descriptor named; nil
// for the root.
pub fn cgroup_account_of(group voidptr) &proc.CGroupAccount {
	if group == unsafe { nil } {
		return unsafe { nil }
	}
	return unsafe { &CGroup(group) }.account
}

// Threads in `group` and the groups below it.
fn cgroup_task_count(group &CGroup) int {
	if group.account != unsafe { nil } {
		return proc.cgroup_task_count(group.account)
	}
	mut count := 0
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	for pid := 1; pid < proc.max_pid; pid++ {
		process := proc.process_at(pid)
		if process != unsafe { nil } && !process.exiting {
			count += process.threads.len
		}
	}
	return count
}

fn all_digits(text string) bool {
	if text.len == 0 {
		return false
	}
	for c in text {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}

// cpu.max: "<quota|max> [period]", both in microseconds, as Linux takes them.
// The period is kept when only the quota is given. A quota of 0 is returned for
// max.
fn parse_cpu_max(value string, account &proc.CGroupAccount) ?(u64, u64) {
	if account == unsafe { nil } {
		return none
	}
	mut fields := [8]string{}
	n := cgroup_fields(value, unsafe { &fields })
	if n < 1 || n > 2 {
		return none
	}
	mut period := account.cpu_period_ns / 1000
	if n == 2 {
		if !all_digits(fields[1]) {
			return none
		}
		period = cgcontrol.decimal(fields[1])?
	}
	if period < 1000 || period > 1000000 {
		return none
	}
	if fields[0] == 'max' {
		return u64(0), period
	}
	if !all_digits(fields[0]) {
		return none
	}
	quota := cgcontrol.decimal(fields[0])?
	if quota < 1000 || quota > (~u64(0)) / 1000 {
		return none
	}
	return quota, period
}

// pids.max: "max" (-1) or a count.
fn parse_pids_max(value string) ?i64 {
	if value == 'max' {
		return -1
	}
	if !all_digits(value) {
		return none
	}
	limit := cgcontrol.decimal(value)?
	if limit > u64(0x7fffffffffffffff) { return none }
	return i64(limit)
}

// memory.max: "max" (0, no limit) or bytes, with an optional K, M, G or T
// suffix as Linux accepts. A limit of 0 bytes is kept as 1, since 0 means none.
fn parse_memory_amount(value string) ?u64 {
	if value == 'max' {
		return u64(0)
	}
	mut number := value
	mut scale := u64(1)
	if number.len > 1 {
		match number[number.len - 1] {
			`k`, `K` { scale = u64(1) << 10 }
			`m`, `M` { scale = u64(1) << 20 }
			`g`, `G` { scale = u64(1) << 30 }
			`t`, `T` { scale = u64(1) << 40 }
			else {}
		}
		if scale != 1 {
			// A view: slicing a string copies it.
			number = unsafe { tos(number.str, number.len - 1) }
		}
	}
	if !all_digits(number) {
		return none
	}
	parsed := cgcontrol.decimal(number)?
	if parsed > ~u64(0) / scale { return none }
	amount := parsed * scale
	return if amount == 0 { u64(1) } else { amount }
}

// CLONE_INTO_CGROUP: the group a directory descriptor names, or none.
pub fn cgroup_from_node(node &VFSNode) ?voidptr {
	if node == unsafe { nil } || node.resource == unsafe { nil }
		|| !is_cgroup_resource(node.resource) || !stat.isdir(node.resource.stat.mode) {
		return none
	}
	res := unsafe { &CGroupResource(node.resource) }
	if res.group.removed { return none }
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
	members := cgroup_members(group, true)
	defer {
		unsafe { members.free() }
	}
	for pid in members {
		hook(pid, 9)
	}
}

// rmdir(2) of a cgroup: allowed once it has no processes and no child
// groups, and it takes its interface files with it.
pub fn cgroup_may_remove(node &VFSNode) ?bool {
	cgroup_hierarchy_lock.acquire()
	defer { cgroup_hierarchy_lock.release() }
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
	if cgroup_has_children(group) {
		errno.set(errno.ebusy)
		return none
	}
	members := cgroup_members(group, true)
	populated := members.len > 0
	unsafe { members.free() }
	if populated {
		errno.set(errno.ebusy)
		return none
	}
	mut account := group.account
	if !cgcontrol.retire(mut account.control) { errno.set(errno.ebusy); return none }
	mut dir := unsafe { node }
	mut names := dir.children.keys()
	defer {
		unsafe { names.free() }
	}
	for name in names {
		if !is_dot_name(name) {
			dir.children.delete(name)
		}
	}
	mut removed := unsafe { group }
	removed.removed = true
	mut ancestor := group.parent
	for ancestor != unsafe { nil } { ancestor.descendants--; ancestor = ancestor.parent }
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
	if stat.isdir(this.stat.mode) && this.group.parent != unsafe { nil } {
		cgroup_hierarchy_lock.acquire()
		if !this.group.removed {
			// Generic ACL/MAC admission can reject a freshly created node
			// before publication. Undo its live descendant entitlement too.
			mut account := this.group.account
			if cgcontrol.retire(mut account.control) {
				this.group.removed = true
				mut ancestor := this.group.parent
				for ancestor != unsafe { nil } { ancestor.descendants--; ancestor = ancestor.parent }
			}
		}
		cgroup_hierarchy_lock.release()
	}
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
