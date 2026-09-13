// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Guest side of the AArch64 NUMA regression. Runs as PID 1 on a machine QEMU
// was told to build with two memory nodes, two CPUs each, and checks that the
// kernel reports that machine and honours a request to allocate from one node
// of it.
//
// Nothing here pins a thread to a particular CPU. Vinix on AArch64 schedules
// only on the boot CPU today -- see the comment in
// kernel/modules/aarch64/cpu/initialisation/initialisation.v -- so a thread
// asked to move would simply stop. What that leaves testable is every part of
// NUMA that does not need a second scheduling CPU: the topology the kernel
// read, the node a running thread is on, and where its pages come from both by
// default and under an explicit policy. The remote node in particular is
// reached the only way it can be, through mbind(2) and set_mempolicy(2).
//
// The runner boots with:
//   -smp 4
//   -numa node,nodeid=0,cpus=0-1,memdev=... (1 GiB)
//   -numa node,nodeid=1,cpus=2-3,memdev=... (1 GiB)
//   -numa dist,src=0,dst=1,val=20
// so every expectation below is a fact about that command line.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SYS_getcpu
#define SYS_getcpu 168
#endif
#ifndef SYS_mbind
#define SYS_mbind 235
#endif
#ifndef SYS_get_mempolicy
#define SYS_get_mempolicy 236
#endif
#ifndef SYS_set_mempolicy
#define SYS_set_mempolicy 237
#endif

#define MPOL_DEFAULT 0
#define MPOL_PREFERRED 1
#define MPOL_BIND 2
#define MPOL_INTERLEAVE 3
#define MPOL_LOCAL 4

#define MPOL_F_NODE 1
#define MPOL_F_ADDR 2
#define MPOL_F_MEMS_ALLOWED 4

static int failures;

static void fail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fputs("QEMU NUMA FAIL: ", stdout);
	vprintf(fmt, args);
	va_end(args);
	fputc('\n', stdout);
	fflush(stdout);
	failures++;
}

static void pass(const char *what) {
	printf("QEMU NUMA PASS: %s\n", what);
	fflush(stdout);
}

// Read a whole small sysfs file and strip the trailing newline.
static int read_line(const char *path, char *out, size_t size) {
	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		return -1;
	}
	ssize_t got = read(fd, out, size - 1);
	close(fd);
	if (got < 0) {
		return -1;
	}
	while (got > 0 && (out[got - 1] == '\n' || out[got - 1] == '\r')) {
		got--;
	}
	out[got] = '\0';
	return 0;
}

static void expect_file(const char *path, const char *want) {
	char got[256];
	if (read_line(path, got, sizeof(got)) != 0) {
		fail("cannot read %s: %s", path, strerror(errno));
		return;
	}
	if (strcmp(got, want) != 0) {
		fail("%s is \"%s\", expected \"%s\"", path, got, want);
	}
}

// "Node 1 MemFree:  1006284 kB" -> 1006284
static long read_node_free_kb(int node) {
	char path[128];
	snprintf(path, sizeof(path), "/sys/devices/system/node/node%d/meminfo", node);
	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		return -1;
	}
	char buffer[1024];
	ssize_t got = read(fd, buffer, sizeof(buffer) - 1);
	close(fd);
	if (got <= 0) {
		return -1;
	}
	buffer[got] = '\0';
	char *needle = strstr(buffer, "MemFree:");
	if (needle == NULL) {
		return -1;
	}
	return strtol(needle + strlen("MemFree:"), NULL, 10);
}

static void check_sysfs_topology(void) {
	int before = failures;

	expect_file("/sys/devices/system/node/possible", "0-1");
	expect_file("/sys/devices/system/node/online", "0-1");
	expect_file("/sys/devices/system/node/has_cpu", "0-1");
	expect_file("/sys/devices/system/node/has_memory", "0-1");

	expect_file("/sys/devices/system/node/node0/cpulist", "0-1");
	expect_file("/sys/devices/system/node/node1/cpulist", "2-3");
	expect_file("/sys/devices/system/node/node0/cpumap", "00000003");
	expect_file("/sys/devices/system/node/node1/cpumap", "0000000c");

	// -numa dist named one direction; a distance matrix is symmetric and a node
	// is always ten from itself.
	expect_file("/sys/devices/system/node/node0/distance", "10 20");
	expect_file("/sys/devices/system/node/node1/distance", "20 10");

	expect_file("/sys/devices/system/cpu/present", "0-3");
	expect_file("/sys/devices/system/cpu/online", "0-3");

	// Each node should report close to its gigabyte; the kernel's own pages come
	// off it, so this only checks the order of magnitude.
	for (int node = 0; node < 2; node++) {
		char path[128];
		char value[256];
		snprintf(path, sizeof(path), "/sys/devices/system/node/node%d/meminfo", node);
		if (read_line(path, value, sizeof(value)) != 0) {
			fail("cannot read %s", path);
			continue;
		}
		char *needle = strstr(value, "MemTotal:");
		long total_kb = needle != NULL ? strtol(needle + strlen("MemTotal:"), NULL, 10) : -1;
		if (total_kb < 768 * 1024 || total_kb > 1024 * 1024) {
			fail("node %d reports %ld kB total, expected about 1 GiB", node, total_kb);
		}
	}

	if (failures == before) {
		pass("sysfs reports two nodes, two CPUs each, 1 GiB each");
	}
}

static int current_cpu_and_node(unsigned *cpu, unsigned *node) {
	*cpu = (unsigned)-1;
	*node = (unsigned)-1;
	return (int)syscall(SYS_getcpu, cpu, node, NULL);
}

// Does the node a thread is told it is on agree with the node whose CPU list
// contains the CPU it is told it is on?
static void check_getcpu_agrees_with_sysfs(void) {
	int before = failures;

	unsigned cpu, node;
	if (current_cpu_and_node(&cpu, &node) != 0) {
		fail("getcpu: %s", strerror(errno));
		return;
	}
	if (cpu > 3) {
		fail("getcpu reports cpu %u on a four-CPU machine", cpu);
		return;
	}
	if (node > 1) {
		fail("getcpu reports node %u on a two-node machine", node);
		return;
	}

	char path[128];
	char list[256];
	snprintf(path, sizeof(path), "/sys/devices/system/node/node%u/cpulist", node);
	if (read_line(path, list, sizeof(list)) != 0) {
		fail("cannot read %s", path);
		return;
	}
	// The lists this machine produces are "0-1" and "2-3", so membership is
	// decided by the two endpoints.
	unsigned first = 0, last = 0;
	if (sscanf(list, "%u-%u", &first, &last) != 2) {
		fail("node %u cpulist is \"%s\", which is not a range", node, list);
		return;
	}
	if (cpu < first || cpu > last) {
		fail("getcpu says cpu %u node %u, but node %u holds cpus %s", cpu, node, node,
				list);
	}

	// The other node must not claim this CPU as well.
	snprintf(path, sizeof(path), "/sys/devices/system/node/node%u/cpulist", 1 - node);
	if (read_line(path, list, sizeof(list)) == 0
			&& sscanf(list, "%u-%u", &first, &last) == 2) {
		if (cpu >= first && cpu <= last) {
			fail("cpu %u is claimed by node %u as well", cpu, 1 - node);
		}
	}

	if (failures == before) {
		pass("getcpu names the node whose CPU list holds the running CPU");
	}
}

static void check_mempolicy_interface(void) {
	int before = failures;

	int mode = -1;
	unsigned long mask = 0;
	if (syscall(SYS_get_mempolicy, &mode, &mask, 64, NULL, 0) != 0) {
		fail("get_mempolicy: %s", strerror(errno));
	} else if (mode != MPOL_DEFAULT) {
		fail("a fresh process has policy %d, expected MPOL_DEFAULT", mode);
	}

	// Which nodes this process may use at all.
	mask = 0;
	if (syscall(SYS_get_mempolicy, NULL, &mask, 64, NULL, MPOL_F_MEMS_ALLOWED) != 0) {
		fail("get_mempolicy(MPOL_F_MEMS_ALLOWED): %s", strerror(errno));
	} else if (mask != 0x3) {
		fail("allowed nodes are 0x%lx, expected 0x3", mask);
	}

	// With MPOL_F_NODE and no address, the mode slot receives the node the
	// caller is running on, which is the node getcpu names.
	unsigned cpu, node;
	if (current_cpu_and_node(&cpu, &node) != 0) {
		fail("getcpu before MPOL_F_NODE: %s", strerror(errno));
	} else {
		int reported = -1;
		if (syscall(SYS_get_mempolicy, &reported, NULL, 0, NULL, MPOL_F_NODE) != 0) {
			fail("get_mempolicy(MPOL_F_NODE): %s", strerror(errno));
		} else if (reported != (int)node) {
			fail("MPOL_F_NODE says node %d, getcpu says %u", reported, node);
		}
	}

	// A node this machine does not have, and a mode that does not exist.
	unsigned long absent = 1UL << 5;
	if (syscall(SYS_set_mempolicy, MPOL_BIND, &absent, 64) == 0) {
		fail("set_mempolicy accepted a binding to a node that does not exist");
	} else if (errno != EINVAL) {
		fail("binding to an absent node gave %s, expected EINVAL", strerror(errno));
	}
	unsigned long node0 = 1UL << 0;
	if (syscall(SYS_set_mempolicy, 99, &node0, 64) == 0) {
		fail("set_mempolicy accepted mode 99");
	} else if (errno != EINVAL) {
		fail("mode 99 gave %s, expected EINVAL", strerror(errno));
	}
	// MPOL_BIND needs somewhere to bind to.
	if (syscall(SYS_set_mempolicy, MPOL_BIND, NULL, 0) == 0) {
		fail("set_mempolicy accepted MPOL_BIND with an empty node set");
	}

	if (failures == before) {
		pass("mempolicy reports and validates what it is given");
	}
}

// Touch `bytes` of anonymous memory and report how much each node's free figure
// moved while it was mapped.
static void measure_allocation(size_t bytes, long *taken_from_node0, long *taken_from_node1) {
	long free0_before = read_node_free_kb(0);
	long free1_before = read_node_free_kb(1);

	void *region = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
			MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (region == MAP_FAILED) {
		fail("mmap of %zu bytes: %s", bytes, strerror(errno));
		*taken_from_node0 = 0;
		*taken_from_node1 = 0;
		return;
	}
	// Write to every page, so a kernel that faulted them in lazily would still
	// have to place them all.
	for (size_t offset = 0; offset < bytes; offset += 4096) {
		((volatile char *)region)[offset] = 1;
	}

	*taken_from_node0 = free0_before - read_node_free_kb(0);
	*taken_from_node1 = free1_before - read_node_free_kb(1);
	munmap(region, bytes);
}

static void check_binding_places_pages(void) {
	int before = failures;
	const size_t bytes = 192u * 1024u * 1024u;
	const long wanted_kb = (long)(bytes / 1024) * 3 / 4;

	for (int node = 1; node >= 0; node--) {
		unsigned long mask = 1UL << node;
		if (syscall(SYS_set_mempolicy, MPOL_BIND, &mask, 64) != 0) {
			fail("set_mempolicy(MPOL_BIND, node %d): %s", node, strerror(errno));
			continue;
		}

		int mode = -1;
		unsigned long read_back = 0;
		if (syscall(SYS_get_mempolicy, &mode, &read_back, 64, NULL, 0) != 0) {
			fail("get_mempolicy after binding to node %d: %s", node, strerror(errno));
		} else if (mode != MPOL_BIND || read_back != mask) {
			fail("bound to node %d, read back mode %d mask 0x%lx", node, mode, read_back);
		}

		long from0, from1;
		measure_allocation(bytes, &from0, &from1);
		long bound = node == 0 ? from0 : from1;
		long other = node == 0 ? from1 : from0;
		if (bound < wanted_kb) {
			fail("bound to node %d but only %ld kB of %zu came from it", node, bound,
					bytes / 1024);
		}
		if (other > wanted_kb / 4) {
			fail("bound to node %d yet node %d lost %ld kB", node, 1 - node, other);
		}
	}

	if (syscall(SYS_set_mempolicy, MPOL_DEFAULT, NULL, 0) != 0) {
		fail("set_mempolicy(MPOL_DEFAULT): %s", strerror(errno));
	}

	if (failures == before) {
		pass("a bound process takes its pages from the node it asked for");
	}
}

static void check_mbind_places_pages(void) {
	int before = failures;
	const size_t bytes = 96u * 1024u * 1024u;
	const long wanted_kb = (long)(bytes / 1024) * 3 / 4;

	// A mapping this large is committed on demand, so the policy mbind installs
	// below is the one in force when its pages are actually placed.
	char *region = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
			MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (region == MAP_FAILED) {
		fail("mmap before mbind: %s", strerror(errno));
		return;
	}

	unsigned long mask = 1UL << 1;
	if (syscall(SYS_mbind, region, bytes, MPOL_BIND, &mask, 64, 0) != 0) {
		fail("mbind to node 1: %s", strerror(errno));
		munmap(region, bytes);
		return;
	}

	long free0_before = read_node_free_kb(0);
	long free1_before = read_node_free_kb(1);
	for (size_t offset = 0; offset < bytes; offset += 4096) {
		((volatile char *)region)[offset] = 1;
	}
	long from0 = free0_before - read_node_free_kb(0);
	long from1 = free1_before - read_node_free_kb(1);

	if (from1 < wanted_kb) {
		fail("mbind named node 1 but only %ld kB of %zu came from it", from1, bytes / 1024);
	}
	if (from0 > wanted_kb / 4) {
		fail("mbind named node 1 yet node 0 lost %ld kB", from0);
	}

	// An unaligned address is not the start of a range.
	if (syscall(SYS_mbind, region + 1, bytes, MPOL_BIND, &mask, 64, 0) == 0) {
		fail("mbind accepted an unaligned address");
	} else if (errno != EINVAL) {
		fail("unaligned mbind gave %s, expected EINVAL", strerror(errno));
	}

	munmap(region, bytes);
	if (syscall(SYS_mbind, NULL, 0, MPOL_DEFAULT, NULL, 0, 0) != 0) {
		fail("mbind back to MPOL_DEFAULT: %s", strerror(errno));
	}

	if (failures == before) {
		pass("mbind places the pages of the range it named");
	}
}

// Without a policy, a page comes from the node running the thread that faulted
// it -- Linux's first-touch rule. Check the allocation against the node the
// kernel says this thread is on, whichever one that turns out to be.
static void check_first_touch_follows_the_cpu(void) {
	int before = failures;
	const size_t bytes = 128u * 1024u * 1024u;
	const long wanted_kb = (long)(bytes / 1024) * 3 / 4;

	unsigned cpu, node;
	if (current_cpu_and_node(&cpu, &node) != 0) {
		fail("getcpu before first touch: %s", strerror(errno));
		return;
	}
	if (node > 1) {
		fail("getcpu reports node %u on a two-node machine", node);
		return;
	}

	long from0, from1;
	measure_allocation(bytes, &from0, &from1);
	long local = node == 0 ? from0 : from1;
	long remote = node == 0 ? from1 : from0;
	if (local < wanted_kb) {
		fail("running on node %u, but only %ld kB of %zu came from it", node, local,
				bytes / 1024);
	}
	if (remote > wanted_kb / 4) {
		fail("running on node %u, yet node %u lost %ld kB", node, 1 - node, remote);
	}

	if (failures == before) {
		pass("first touch takes pages from the node that faulted them");
	}
}

int main(void) {
	printf("QEMU NUMA: start\n");
	fflush(stdout);

	check_sysfs_topology();
	check_getcpu_agrees_with_sysfs();
	check_mempolicy_interface();
	check_binding_places_pages();
	check_mbind_places_pages();
	check_first_touch_follows_the_cpu();

	if (failures == 0) {
		printf("VINIX QEMU NUMA: PASS\n");
	} else {
		printf("VINIX QEMU NUMA: FAIL (%d)\n", failures);
	}
	fflush(stdout);

	// PID 1 must not return; the runner stops the machine once it has read the
	// verdict above.
	for (;;) {
		pause();
	}
	return 0;
}
