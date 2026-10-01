/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Host tests of kernel/c/net_random.c; see run.sh. */
#include "net_random.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The kernel generator's stand-in: SplitMix64, so that a failure repeats. */
static uint64_t generator_state = 0x243f6a8885a308d3ULL;
static uint64_t requests;

bool krandom__fill(void *buf, uint64_t count, bool allow_insecure)
{
	uint8_t *out = buf;

	(void)allow_insecure;
	++requests;
	while (count != 0) {
		uint64_t z = (generator_state += 0x9e3779b97f4a7c15ULL);
		z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
		z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
		z ^= z >> 31;
		size_t take = count < 8 ? count : 8;
		memcpy(out, &z, take);
		out += take;
		count -= take;
	}
	return true;
}

uint64_t time__monotonic_ns(void)
{
	return 0;
}

static int failures;

static void check(bool ok, const char *what)
{
	if (!ok) {
		printf("FAIL: %s\n", what);
		++failures;
	}
}

static void test_siphash(void)
{
	uint8_t key[16], message[15];

	for (int i = 0; i < 16; ++i)
		key[i] = (uint8_t)i;
	for (int i = 0; i < 15; ++i)
		message[i] = (uint8_t)i;
	/* The SipHash paper's example, and the first of its reference vectors. */
	check(vinix_siphash24(key, message, 15) == 0xa129ca6149be45e5ULL, "siphash: 15 bytes");
	check(vinix_siphash24(key, message, 0) == 0x726fdb47dd0e0e31ULL, "siphash: empty");
}

static void test_ids(void)
{
	enum { draws = 4 * 65536 };
	static int32_t last_seen[65536];
	int consecutive = 0;
	int closest = draws;
	uint16_t previous = 0;

	for (int i = 0; i < 65536; ++i)
		last_seen[i] = -1;
	for (int i = 0; i < draws; ++i) {
		uint16_t id = vinix_ip_randomid();
		check(id != 0, "ip id: 0 handed out");
		if (last_seen[id] >= 0 && i - last_seen[id] < closest)
			closest = i - last_seen[id];
		last_seen[id] = i;
		if (i > 0 && id == (uint16_t)(previous + 1))
			++consecutive;
		previous = id;
	}
	/* OpenBSD's guarantee: no ID twice within 32768 datagrams. */
	check(closest >= 32768, "ip id: reused within 32768 datagrams");
	/* Counting up, every one would be; at random, about four. */
	check(consecutive < 32, "ip id: in sequence");
	printf("ip id: closest reuse after %d, %d in sequence of %d\n", closest, consecutive, draws);
}

static uint32_t isn(uint64_t now_ns, uint16_t local_port)
{
	return vinix_tcp_isn_at(now_ns, 0x0f02000a, local_port, 0x0202000a, 80);
}

static void test_isn(void)
{
	int close = 0;

	/* M: the same connection's ISN advances one every 4 microseconds. */
	check(isn(4000 * 1000, 50000) - isn(0, 50000) == 1000, "isn: 4 microsecond clock");
	check(isn(4000, 50000) == isn(7999, 50000), "isn: clock granularity");
	/* F: another connection's, even the next port's, tells nothing. */
	for (uint16_t port = 49152; port < 50152; ++port) {
		uint32_t gap = isn(0, port + 1) - isn(0, port);
		if (gap < (1u << 24) || gap > ~(1u << 24))
			++close;
	}
	check(close < 40, "isn: neighbouring ports start close together");
	check(vinix_tcp_isn_at(0, 0x0f02000a, 50000, 0x0302000a, 80) != isn(0, 50000),
	      "isn: remote address left out");
	check(vinix_tcp_isn_at(0, 0x0f02000a, 50000, 0x0202000a, 443) != isn(0, 50000),
	      "isn: remote port left out");
	printf("isn: %d of 1000 neighbouring ports within 2^24\n", close);
}

static bool taken[65536];

static int port_taken(uint16_t port, void *context)
{
	(void)context;
	return taken[port];
}

static void test_ports(void)
{
	enum { picks = 2000 };
	int consecutive = 0;
	uint16_t previous = 0;

	for (int i = 0; i < picks; ++i) {
		uint16_t port = vinix_pick_port(VINIX_EPHEMERAL_FIRST, VINIX_EPHEMERAL_LAST,
						port_taken, NULL);
		check(port >= VINIX_EPHEMERAL_FIRST, "ports: below the range");
		if (i > 0 && (port == previous + 1 || port == previous))
			++consecutive;
		previous = port;
	}
	check(consecutive < 10, "ports: in sequence");
	/* Every port but one taken: that one, wherever the search starts. */
	for (uint32_t port = VINIX_EPHEMERAL_FIRST; port <= VINIX_EPHEMERAL_LAST; ++port)
		taken[port] = true;
	taken[51000] = false;
	for (int i = 0; i < 64; ++i)
		check(vinix_pick_port(VINIX_EPHEMERAL_FIRST, VINIX_EPHEMERAL_LAST, port_taken, NULL) ==
			      51000,
		      "ports: the one free port missed");
	taken[51000] = true;
	check(vinix_pick_port(VINIX_EPHEMERAL_FIRST, VINIX_EPHEMERAL_LAST, port_taken, NULL) == 0,
	      "ports: none free");
	printf("ports: %d of %d picks next to the one before\n", consecutive, picks);
}

static void test_uniform(void)
{
	int counts[3] = {0};

	for (int i = 0; i < 30000; ++i) {
		uint32_t value = vinix_net_random_uniform(3);
		check(value < 3, "uniform: out of range");
		if (value < 3)
			++counts[value];
	}
	for (int i = 0; i < 3; ++i)
		check(counts[i] > 9000 && counts[i] < 11000, "uniform: skewed");
	check(vinix_net_random_uniform(1) == 0 && vinix_net_random_uniform(0) == 0,
	      "uniform: degenerate bounds");
}

static void test_pooling(void)
{
	uint64_t before = requests;

	/* 64 four-byte values from one or two 256-byte requests, not 64. */
	for (int i = 0; i < 64; ++i)
		(void)vinix_net_random();
	check(requests - before <= 2, "pool: the generator asked for every value");
}

int main(void)
{
	test_siphash();
	test_ids();
	test_isn();
	test_ports();
	test_uniform();
	test_pooling();
	if (failures) {
		printf("net-random: %d failures\n", failures);
		return 1;
	}
	printf("net-random: PASS\n");
	return 0;
}
