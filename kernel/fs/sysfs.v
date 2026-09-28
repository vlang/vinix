// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A small sysfs: the part of /sys that describes the machine's CPUs and memory
// nodes.
//
// Linux publishes its NUMA topology nowhere else. libnuma, hwloc, numactl and
// glibc's sysconf(_SC_NPROCESSORS_ONLN) all read it out of
// /sys/devices/system/{cpu,node}, so a kernel that knows its topology and does
// not export it here has told userspace nothing. These are the same file names
// and the same formats, so a program that already knows how to read them needs
// no special case for Vinix.
//
// Everything here is decided at boot and never changes afterwards, apart from
// the per-node free-memory figures, which are generated when they are read. The
// tree is therefore built once at mount and left alone -- unlike procfs, which
// has to track a process table that moves under it.
@[has_globals]
module fs

import stat
import klock
import katomic
import errno
import numa
import memory
import resource
import event.eventstruct
import lib

// Vinix's scheduler carries 64-bit affinity masks, so this is the largest CPU
// number any of these files can name.
const sysfs_max_cpus = 64

enum SysFSKind {
	directory
	text
	node_meminfo
	node_numastat
}

@[heap]
struct SysFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	kind SysFSKind
	// Which node this file describes, for the generated ones.
	node int
	text string
}

struct SysFS {}

__global (
	sysfs_dev_id        u64
	sysfs_inode_counter u64
	sysfs_root          &VFSNode
)

fn (this SysFS) instantiate() &FileSystem {
	return &SysFS{}
}

fn (this SysFS) populate(_node &VFSNode) {}

fn (mut this SysFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	if sysfs_dev_id == 0 {
		sysfs_dev_id = resource.create_dev_id()
	}
	if unsafe { sysfs_root != 0 } {
		return sysfs_root
	}

	mut root := create_node(this, parent, name, true)
	root.resource = new_sysfs_resource(.directory, stat.ifdir | 0o555, 0)
	sysfs_root = root

	mut devices_dir := add_sysfs_directory(mut root, 'devices')
	mut system := add_sysfs_directory(mut devices_dir, 'system')
	build_cpu_tree(mut system)
	build_node_tree(mut system)

	// Where the cgroup v2 hierarchy is mounted.
	mut fs_dir := add_sysfs_directory(mut root, 'fs')
	add_sysfs_directory(mut fs_dir, 'cgroup')
	mut kernel_dir := add_sysfs_directory(mut root, 'kernel')
	add_sysfs_directory(mut kernel_dir, 'security')
	add_sysfs_directory(mut root, 'module')

	return root
}

fn (mut this SysFS) create(_parent &VFSNode, _name string, _mode u32) &VFSNode {
	return unsafe { nil }
}

fn (mut this SysFS) symlink(_parent &VFSNode, _dest string, _target string) &VFSNode {
	return unsafe { nil }
}

fn (mut this SysFS) link(_parent &VFSNode, _path string, mut _old_node VFSNode) ?&VFSNode {
	errno.set(errno.eperm)
	return none
}

fn (mut this SysFS) rename(_old_parent &VFSNode, _old_name string, _new_parent &VFSNode,
	_new_name string, _flags int) ? {
	errno.set(errno.eperm)
	return none
}

fn new_sysfs_resource(kind SysFSKind, mode u32, node int) &SysFSResource {
	mut new_resource := &SysFSResource{
		kind:     kind
		node:     node
		refcount: 1
	}
	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = sysfs_dev_id
	new_resource.stat.ino = sysfs_inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = if stat.isdir(mode) { u64(2) } else { u64(1) }
	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock
	return new_resource
}

fn add_sysfs_directory(mut parent VFSNode, name string) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, true)
	node.resource = new_sysfs_resource(.directory, stat.ifdir | 0o555, 0)
	node.create_dotentries(parent)
	unsafe {
		parent.children[name] = node
		parent.resource.stat.nlink++
	}
	return node
}

fn add_sysfs_text(mut parent VFSNode, name string, text string) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	mut file_resource := new_sysfs_resource(.text, stat.ifreg | 0o444, 0)
	file_resource.text = text
	file_resource.stat.size = u64(text.len)
	node.resource = file_resource
	unsafe {
		parent.children[name] = node
	}
	return node
}

fn add_sysfs_generated(mut parent VFSNode, name string, kind SysFSKind, node_id int) &VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_sysfs_resource(kind, stat.ifreg | 0o444, node_id)
	unsafe {
		parent.children[name] = node
	}
	return node
}

// ── The trees ───────────────────────────────────────────────────────────────

// The tree is made once and kept, so its texts and names are too. They are
// built in lib.Text all the same, which leaves nothing else behind.

// `prefix` then `value` in decimal: a name such as cpu0.
fn sysfs_numbered(prefix string, value int) string {
	mut text := lib.new_text(prefix.len + 20)
	text.add(prefix)
	text.add_decimal(i64(value))
	return text.str()
}

// `value` in decimal and a newline.
fn sysfs_decimal_line(value i64) string {
	mut text := lib.new_text(24)
	text.add_decimal(value)
	text.add_byte(`\n`)
	return text.str()
}

// A cpulist and a newline.
fn sysfs_list_line(mask u64) string {
	mut text := lib.new_text(64)
	add_cpu_list(mut text, mask)
	text.add_byte(`\n`)
	return text.str()
}

fn build_cpu_tree(mut system VFSNode) {
	mut cpus := add_sysfs_directory(mut system, 'cpu')
	count := numa.cpu_count()
	present := if count > 0 { all_cpus_mask(count) } else { u64(0) }
	// glibc reads `online` for sysconf(_SC_NPROCESSORS_ONLN), and every CPU
	// Vinix starts stays started, so the three lists are the same list.
	add_sysfs_text(mut cpus, 'possible', sysfs_list_line(present))
	add_sysfs_text(mut cpus, 'present', sysfs_list_line(present))
	add_sysfs_text(mut cpus, 'online', sysfs_list_line(present))
	add_sysfs_text(mut cpus, 'offline', '\n')
	add_sysfs_text(mut cpus, 'kernel_max', sysfs_decimal_line(sysfs_max_cpus - 1))

	for i := 0; i < count && i < sysfs_max_cpus; i++ {
		mut entry := add_sysfs_directory(mut cpus, sysfs_numbered('cpu', i))
		mut topology := add_sysfs_directory(mut entry, 'topology')
		// A logical CPU is its own core and its own package here: Vinix does not
		// read the sibling maps that would say otherwise, and inventing them
		// would mislead a program that schedules by them.
		add_sysfs_text(mut topology, 'core_id', sysfs_decimal_line(i64(i)))
		add_sysfs_text(mut topology, 'physical_package_id', sysfs_decimal_line(i64(numa.node_of_cpu(i))))
		add_sysfs_text(mut topology, 'core_siblings_list', sysfs_decimal_line(i64(i)))
		add_sysfs_text(mut topology, 'thread_siblings_list', sysfs_decimal_line(i64(i)))
	}
}

fn build_node_tree(mut system VFSNode) {
	mut nodes := add_sysfs_directory(mut system, 'node')
	count := numa.node_count()

	mut declared := u64(0)
	mut with_cpus := u64(0)
	mut with_memory := u64(0)
	for id := 0; id < count && id < 64; id++ {
		declared |= u64(1) << u64(id)
		if numa.node_cpu_mask(id) != 0 {
			with_cpus |= u64(1) << u64(id)
		}
		if memory.pmm_node_total_pages(id) != 0 {
			with_memory |= u64(1) << u64(id)
		}
	}
	add_sysfs_text(mut nodes, 'possible', sysfs_list_line(declared))
	add_sysfs_text(mut nodes, 'online', sysfs_list_line(declared))
	add_sysfs_text(mut nodes, 'has_cpu', sysfs_list_line(with_cpus))
	add_sysfs_text(mut nodes, 'has_memory', sysfs_list_line(with_memory))
	add_sysfs_text(mut nodes, 'has_normal_memory', sysfs_list_line(with_memory))

	for id := 0; id < count && id < 64; id++ {
		mut entry := add_sysfs_directory(mut nodes, sysfs_numbered('node', id))
		mask := numa.node_cpu_mask(id)
		mut cpumap := lib.new_text(24)
		add_cpu_map(mut cpumap, mask)
		cpumap.add_byte(`\n`)
		add_sysfs_text(mut entry, 'cpumap', cpumap.str())
		add_sysfs_text(mut entry, 'cpulist', sysfs_list_line(mask))
		mut distances := lib.new_text(count * 4 + 1)
		for other := 0; other < count; other++ {
			if other != 0 {
				distances.add_byte(` `)
			}
			distances.add_decimal(i64(numa.distance(id, other)))
		}
		distances.add_byte(`\n`)
		add_sysfs_text(mut entry, 'distance', distances.str())
		add_sysfs_generated(mut entry, 'meminfo', .node_meminfo, id)
		add_sysfs_generated(mut entry, 'numastat', .node_numastat, id)
	}
}

fn all_cpus_mask(count int) u64 {
	mut mask := u64(0)
	for i := 0; i < count && i < sysfs_max_cpus; i++ {
		mask |= u64(1) << u64(i)
	}
	return mask
}

// The comma-separated ranges Linux calls a "cpulist": "0-1", "0,2-3", or
// nothing at all for no CPUs.
fn add_cpu_list(mut text lib.Text, mask u64) {
	start := text.len()
	mut i := 0
	for i < sysfs_max_cpus {
		if mask & (u64(1) << u64(i)) == 0 {
			i++
			continue
		}
		mut last := i
		for last + 1 < sysfs_max_cpus && mask & (u64(1) << u64(last + 1)) != 0 {
			last++
		}
		if text.len() != start {
			text.add_byte(`,`)
		}
		text.add_decimal(i64(i))
		if last != i {
			text.add_byte(`-`)
			text.add_decimal(i64(last))
		}
		i = last + 1
	}
}

// The "cpumap" spelling of the same set: 32-bit hex groups, most significant
// first, comma separated. Trailing empty groups are not printed, so a machine
// with four CPUs reports one group.
fn add_cpu_map(mut text lib.Text, mask u64) {
	high := u32(mask >> 32)
	low := u32(mask)
	if high != 0 {
		text.add_radix(u64(high), 16, 8)
		text.add_byte(`,`)
	}
	text.add_radix(u64(low), 16, 8)
}

// ── Generated file contents ─────────────────────────────────────────────────

fn (this &SysFSResource) contents() string {
	match this.kind {
		.text {
			return this.text
		}
		.node_meminfo {
			total_kb := memory.pmm_node_total_pages(this.node) * page_size / 1024
			free_kb := memory.pmm_node_free_pages(this.node) * page_size / 1024
			used_kb := if total_kb > free_kb { total_kb - free_kb } else { u64(0) }
			mut text := lib.new_text(160)
			add_node_meminfo_line(mut text, this.node, ' MemTotal:       ', total_kb)
			add_node_meminfo_line(mut text, this.node, ' MemFree:        ', free_kb)
			add_node_meminfo_line(mut text, this.node, ' MemUsed:        ', used_kb)
			return text.str()
		}
		.node_numastat {
			// Vinix does not count the faults that missed their preferred node,
			// so the only honest figures here are the two that are definitional
			// for a kernel which never migrates a page after the fact.
			return 'numa_hit 0\nnuma_miss 0\nnuma_foreign 0\ninterleave_hit 0\nlocal_node 0\nother_node 0\n'
		}
		else {
			return ''
		}
	}
}

fn add_node_meminfo_line(mut text lib.Text, node int, label string, kb u64) {
	text.add('Node ')
	text.add_decimal(i64(node))
	text.add(label)
	text.add_unsigned(kb)
	text.add(' kB\n')
}

fn (mut this SysFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}

	text := this.contents()
	// The generated kinds make their text afresh for every read.
	defer {
		if this.kind != .text {
			unsafe { text.free() }
		}
	}
	if loc >= u64(text.len) {
		return i64(0)
	}
	mut actual_count := count
	if loc + actual_count > u64(text.len) {
		actual_count = u64(text.len) - loc
	}
	unsafe { C.memcpy(buf, &u8(text.str) + loc, actual_count) }
	return i64(actual_count)
}

fn (mut this SysFSResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.eperm)
	return none
}

fn (mut this SysFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this SysFSResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this SysFSResource) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut this SysFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this SysFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this SysFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this SysFSResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type:   0x62656572 // SYSFS_MAGIC
		bsize:   page_size
		blocks:  0
		bfree:   0
		bavail:  0
		files:   0
		ffree:   0
		namelen: 255
		frsize:  page_size
	}
}
