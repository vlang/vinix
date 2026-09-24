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
// Four controls are enforced, through the group's proc.CGroupAccount (see
// proc/cgroup_account.v), since the code that acts on them cannot import fs:
// - cpu.max: the scheduler charges each group the CPU its threads use and
//   stops running them once the period's quota is spent.
// - cgroup.freeze: the scheduler stops running the group's threads, which is
//   what docker pause does.
// - pids.max: clone fails with EAGAIN once the group has that many tasks.
// - memory.max: the anonymous memory the group has resident is counted as it
//   faults in, and going over the limit kills the group's largest process, or
//   all of them with memory.oom.group, as Linux's OOM killer does.
// The other controller files are stored as written and read back.
@[has_globals]
module fs

import stat
import klock
import katomic
import errno
import proc
import resource
import event.eventstruct
import numa
import memory.mmap
import time

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
}

@[heap]
pub struct CGroup {
pub mut:
	lock    klock.Lock
	node    &VFSNode = unsafe { nil }
	parent  &CGroup  = unsafe { nil }
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
		proc.set_cgroup_memory_hook(voidptr(cgroup_memory_check))
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
	if parent_group != unsafe { nil } {
		group.account = proc.new_cgroup_account(parent_group.account)
	}
	mut dir_res := unsafe { &CGroupResource(node.resource) }
	dir_res.group = group
	for file_name, default in cgroup_default_files {
		// The root has no limits of its own, so it has no controller files.
		if parent_group == unsafe { nil } && file_name.contains('.')
			&& !file_name.starts_with('cgroup.') && !file_name.ends_with('.stat')
			&& !file_name.ends_with('.current') && !file_name.ends_with('.pressure')
			&& !file_name.ends_with('.effective') {
			continue
		}
		mut child := create_node(node.filesystem, node, file_name, false)
		mut res := new_cgroup_resource(if file_name in ['cgroup.controllers', 'cgroup.events',
			'cgroup.stat', 'memory.current', 'memory.stat', 'memory.events', 'memory.peak',
			'pids.current', 'pids.events',
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

// The anonymous memory process `pid` has resident; see
// mmap.anonymous_resident_bytes.
fn anonymous_bytes_of(pid int) u64 {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	process := proc.process_at(pid)
	if process == unsafe { nil } || process.exiting || unsafe { process.pagemap == nil } {
		return 0
	}
	return mmap.anonymous_resident_bytes(process.pagemap)
}

fn cgroup_memory_bytes(group &CGroup) u64 {
	members := cgroup_members(group, true)
	defer {
		unsafe { members.free() }
	}
	mut total := u64(0)
	for pid in members {
		total += anonymous_bytes_of(pid)
	}
	if group.account != unsafe { nil } {
		mut account := group.account
		if total > account.memory_peak {
			account.memory_peak = total
		}
	}
	return total
}

// The CPUs or memory nodes a group may use: the ones its cpuset names, or
// failing that its parent's, and at the root `everything`. Vinix does not
// confine a group to them.
fn cgroup_cpuset_effective(group &CGroup, file_name string, everything string) string {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if current.node != unsafe { nil } && file_name in current.node.children {
			res := unsafe { &CGroupResource(current.node.children[file_name].resource) }
			if res.text.len > 0 {
				return res.text + '\n'
			}
		}
		current = current.parent
	}
	return everything + '\n'
}

// The processes in `account` and the groups below it.
fn account_members(account &proc.CGroupAccount) []int {
	mut members := []int{}
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
		if limit != 0 && !enforce_memory_max(mut current, bytes, limit, now, process.pid) {
			return false
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
	account.lock.acquire()
	fresh := account.memory_counted_ns != 0 && now - account.memory_counted_ns < memory_count_valid_ns
	if fresh && account.memory_counted_bytes + bytes <= limit {
		account.memory_counted_bytes += bytes
		if account.memory_counted_bytes > account.memory_peak {
			account.memory_peak = account.memory_counted_bytes
		}
		account.lock.release()
		return true
	}
	account.lock.release()

	members := account_members(account)
	defer {
		unsafe { members.free() }
	}
	mut usage := u64(0)
	mut largest_pid := 0
	mut largest := u64(0)
	for pid in members {
		used := anonymous_bytes_of(pid)
		usage += used
		if used > largest || largest_pid == 0 {
			largest = used
			largest_pid = pid
		}
	}

	account.lock.acquire()
	account.memory_counted_bytes = usage + bytes
	account.memory_counted_ns = now
	if usage + bytes > account.memory_peak {
		account.memory_peak = usage + bytes
	}
	if usage + bytes <= limit {
		account.lock.release()
		return true
	}
	account.memory_events_max++
	// The last victim may still be on its way out, and what it frees has not
	// come back yet. Killing another now would take two for one excess.
	if account.oom_victim_pid != 0 && now - account.oom_victim_ns < oom_victim_grace_ns
		&& process_alive(account.oom_victim_pid) {
		victim := account.oom_victim_pid
		account.lock.release()
		return caller != victim
	}
	if largest_pid == 0 {
		account.lock.release()
		return true
	}
	account.memory_events_oom++
	whole_group := account.memory_oom_group
	account.oom_victim_pid = largest_pid
	account.oom_victim_ns = now
	account.memory_events_oom_kill += if whole_group { u64(members.len) } else { u64(1) }
	account.lock.release()

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
			members := cgroup_members(group, false)
			defer {
				unsafe { members.free() }
			}
			mut text := []u8{cap: members.len * 8}
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
		// Tasks, which is to say threads, as Linux counts them.
		'pids.current' {
			return '${cgroup_task_count(group)}\n'
		}
		'pids.events' {
			if group.account == unsafe { nil } {
				return 'max 0\n'
			}
			return 'max ${katomic.load(&group.account.pids_max_events)}\n'
		}
		'cpu.stat' {
			if group.account == unsafe { nil } {
				return this.text + '\n'
			}
			mut account := group.account
			return account.cpu_stat_text()
		}
		'memory.events' {
			if group.account == unsafe { nil } {
				return this.text + '\n'
			}
			account := group.account
			return 'low 0\nhigh 0\nmax ${account.memory_events_max}\noom ${account.memory_events_oom}\noom_kill ${account.memory_events_oom_kill}\noom_group_kill 0\n'
		}
		'memory.peak' {
			cgroup_memory_bytes(group)
			if group.account == unsafe { nil } {
				return '0\n'
			}
			return '${group.account.memory_peak}\n'
		}
		// The anonymous memory the group's processes have resident, the same
		// figure memory.max is held to. docker stats reads this.
		'memory.current' {
			return '${cgroup_memory_bytes(group)}\n'
		}
		'memory.stat' {
			return 'anon ${cgroup_memory_bytes(group)}\nfile 0\nkernel 0\nshmem 0\n'
		}
		// Docker checks --cpuset-cpus against the root's before it makes a
		// container.
		'cpuset.cpus.effective' {
			return cgroup_cpuset_effective(group, 'cpuset.cpus', if numa.cpu_count() > 1 {
				'0-${numa.cpu_count() - 1}'
			} else {
				'0'
			})
		}
		'cpuset.mems.effective' {
			return cgroup_cpuset_effective(group, 'cpuset.mems', '0')
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
			target := if pid == 0 { calling_process().pid } else { proc.kernel_id(pid) }
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
			if value != '0' && value != '1' || group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			katomic.store(mut &account.freeze, if value == '1' { u32(1) } else { u32(0) })
			this.text = value
			return i64(count)
		}
		'cpu.max' {
			quota_us, period_us := parse_cpu_max(value, group.account) or {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			account.set_cpu_max(quota_us * 1000, period_us * 1000)
			this.text = if quota_us == 0 { 'max ${period_us}' } else { '${quota_us} ${period_us}' }
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
			this.text = if limit < 0 { 'max' } else { '${limit}' }
			return i64(count)
		}
		'memory.max' {
			limit := parse_memory_amount(value) or {
				errno.set(errno.einval)
				return none
			}
			if group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			katomic.store(mut &account.memory_max, limit)
			this.text = if limit == 0 { 'max' } else { '${limit}' }
			// A limit lowered below what the group already uses is enforced
			// straight away, as Linux does after it fails to reclaim.
			if limit != 0 {
				enforce_memory_max(mut account, 0, limit, time.monotonic_ns(), 0)
			}
			return i64(count)
		}
		'memory.oom.group' {
			if value != '0' && value != '1' || group.account == unsafe { nil } {
				errno.set(errno.einval)
				return none
			}
			mut account := group.account
			account.memory_oom_group = value == '1'
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
	process.cgroup_account = group.account
	return true
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
	fields := value.fields()
	if fields.len == 0 || fields.len > 2 {
		return none
	}
	mut period := account.cpu_period_ns / 1000
	if fields.len == 2 {
		if !all_digits(fields[1]) {
			return none
		}
		period = fields[1].u64()
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
	quota := fields[0].u64()
	if quota < 1000 {
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
	return i64(value.u64())
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
			number = number[..number.len - 1]
		}
	}
	if !all_digits(number) {
		return none
	}
	amount := number.u64() * scale
	return if amount == 0 { u64(1) } else { amount }
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
