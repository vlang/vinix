/* SPDX-License-Identifier: GPL-2.0-or-later */
/* C ABI tests of kernel/socket/inet/net_random.v; see run.sh. */
#include "net_random.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The kernel generator's stand-in: SplitMix64, so that a failure repeats. */
static uint64_t generator_state = 0x243f6a8885a308d3ULL;
static uint64_t requests;
static bool generator_enabled = true;

bool krandom__fill(void *buf, uint64_t count, bool allow_insecure)
{
	uint8_t *out = buf;

	(void)allow_insecure;
	++requests;
	if (!generator_enabled)
		return false;
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

/* Fixtures captured from the C implementation before the V migration.
 * The empty and 15-byte answers above also match the published reference. */
static const uint64_t siphash_vectors[64] = {
	0x726fdb47dd0e0e31ULL, 0x74f839c593dc67fdULL, 0x0d6c8009d9a94f5aULL, 0x85676696d7fb7e2dULL,
	0xcf2794e0277187b7ULL, 0x18765564cd99a68dULL, 0xcbc9466e58fee3ceULL, 0xab0200f58b01d137ULL,
	0x93f5f5799a932462ULL, 0x9e0082df0ba9e4b0ULL, 0x7a5dbbc594ddb9f3ULL, 0xf4b32f46226bada7ULL,
	0x751e8fbc860ee5fbULL, 0x14ea5627c0843d90ULL, 0xf723ca908e7af2eeULL, 0xa129ca6149be45e5ULL,
	0x3f2acc7f57c29bdbULL, 0x699ae9f52cbe4794ULL, 0x4bc1b3f0968dd39cULL, 0xbb6dc91da77961bdULL,
	0xbed65cf21aa2ee98ULL, 0xd0f2cbb02e3b67c7ULL, 0x93536795e3a33e88ULL, 0xa80c038ccd5ccec8ULL,
	0xb8ad50c6f649af94ULL, 0xbce192de8a85b8eaULL, 0x17d835b85bbb15f3ULL, 0x2f2e6163076bcfadULL,
	0xde4daaaca71dc9a5ULL, 0xa6a2506687956571ULL, 0xad87a3535c49ef28ULL, 0x32d892fad841c342ULL,
	0x7127512f72f27cceULL, 0xa7f32346f95978e3ULL, 0x12e0b01abb051238ULL, 0x15e034d40fa197aeULL,
	0x314dffbe0815a3b4ULL, 0x027990f029623981ULL, 0xcadcd4e59ef40c4dULL, 0x9abfd8766a33735cULL,
	0x0e3ea96b5304a7d0ULL, 0xad0c42d6fc585992ULL, 0x187306c89bc215a9ULL, 0xd4a60abcf3792b95ULL,
	0xf935451de4f21df2ULL, 0xa9538f0419755787ULL, 0xdb9acddff56ca510ULL, 0xd06c98cd5c0975ebULL,
	0xe612a3cb9ecba951ULL, 0xc766e62cfcadaf96ULL, 0xee64435a9752fe72ULL, 0xa192d576b245165aULL,
	0x0a8787bf8ecb74b2ULL, 0x81b3e73d20b49b6fULL, 0x7fa8220ba3b2eceaULL, 0x245731c13ca42499ULL,
	0xb78dbfaf3a8d83bdULL, 0xea1ad565322a1a0bULL, 0x60e61c23a3795013ULL, 0x6606d7e446282b93ULL,
	0x6ca4ecb15c5f91e1ULL, 0x9f626da15c9625f3ULL, 0xe51b38608ef25f57ULL, 0x958a324ceb064572ULL,
};

static void test_siphash_lengths_and_alignment(void)
{
	uint8_t key[32], message[80];
	for (unsigned offset = 0; offset < 16; ++offset) {
		for (unsigned i = 0; i < 16; ++i) key[offset + i] = (uint8_t)i;
		for (unsigned i = 0; i < 64; ++i) message[offset + i] = (uint8_t)i;
		for (unsigned n = 0; n < 64; ++n)
			check(vinix_siphash24(key + offset, message + offset, n) == siphash_vectors[n],
			      "siphash: tail length or unaligned input");
	}
	for (unsigned i = 0; i < 16; ++i) key[i] = (uint8_t)i;
	check(vinix_siphash24(key, NULL, 0) == siphash_vectors[0], "siphash: empty null input");
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

static void test_isn6(void)
{
    uint32_t local[4] = {0x01000020, 0, 0, 1}, remote[4] = {0x01000020, 0, 0, 2};
    uint32_t original = vinix_tcp_isn6_at(0, local, 50000, remote, 80);
    check(vinix_tcp_isn6_at(4000000, local, 50000, remote, 80) - original == 1000,
          "isn6: clock");
    for (int word = 0; word < 4; ++word) {
        local[word] ^= 0x00008000;
        check(vinix_tcp_isn6_at(0, local, 50000, remote, 80) != original,
              "isn6: local address word omitted");
        local[word] ^= 0x00008000;
        remote[word] ^= 0x00008000;
        check(vinix_tcp_isn6_at(0, local, 50000, remote, 80) != original,
              "isn6: remote address word omitted");
        remote[word] ^= 0x00008000;
    }
    check(vinix_tcp_isn6_at(0, local, 50001, remote, 80) != original, "isn6: local port");
    check(vinix_tcp_isn6_at(0, local, 50000, remote, 81) != original, "isn6: remote port");
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

static void test_pool_boundaries_and_fallback(void)
{
	uint8_t output[1026];
	const size_t lengths[] = {0, 1, 255, 256, 257, 511, 512, 513, 1024};
	for (unsigned i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
		memset(output, 0xa5, sizeof(output));
		vinix_net_random_bytes(output + 1, lengths[i]);
		check(output[0] == 0xa5 && output[lengths[i] + 1] == 0xa5,
		      "pool: output bounds");
	}
	uint64_t before = requests;
	vinix_net_random_bytes(NULL, 0);
	check(requests == before, "pool: empty request refilled");
	generator_enabled = false;
	memset(output, 0xa5, sizeof(output));
	vinix_net_random_bytes(output + 1, 1024);
	check(requests > before, "pool: fallback not reached");
	check(output[0] == 0xa5 && output[1025] == 0xa5, "pool: fallback bounds");
	unsigned combined = 0;
	for (unsigned i = 1; i <= 1024; ++i) combined |= output[i];
	check(combined != 0, "pool: fallback returned only zeros");
	generator_enabled = true;
}

static void test_uniform_large_bounds(void)
{
	const uint32_t bounds[] = {2, 3, 256, 65535, 0x80000000U, 0x80000001U, UINT32_MAX};
	for (unsigned i = 0; i < sizeof(bounds) / sizeof(bounds[0]); ++i)
		for (unsigned n = 0; n < 1000; ++n)
			check(vinix_net_random_uniform(bounds[i]) < bounds[i],
			      "uniform: large unsigned bound");
	check(vinix_tcp_isn_bytes(NULL, 0, NULL, 0, 0) == 0 &&
	      vinix_tcp_isn_bytes(NULL, 0, NULL, 0, 15) == 0,
	      "isn: invalid address length");
}

static int single_port_taken(uint16_t port, void *context)
{
	check(port == UINT16_MAX, "ports: inclusive upper endpoint");
	return *(int *)context;
}

static void test_port_callback_context(void)
{
	int occupied = 0;
	check(vinix_pick_port(UINT16_MAX, UINT16_MAX, single_port_taken, &occupied) == UINT16_MAX,
	      "ports: one-port range");
	occupied = -1;
	check(vinix_pick_port(UINT16_MAX, UINT16_MAX, single_port_taken, &occupied) == 0,
	      "ports: negative callback result means occupied");
}

int main(void)
{
	test_siphash();
	test_siphash_lengths_and_alignment();
	test_ids();
	test_isn();
	uint8_t local6[16] = {0x20, 1, 0x0d, 0xb8}, remote6[16] = {0x20, 1, 0x0d, 0xb8};
	uint32_t first6 = vinix_tcp_isn_bytes(local6, 50000, remote6, 443, 16);
	for (unsigned i = 0; i < 16; ++i) {
		remote6[i] ^= 1;
		check(first6 != vinix_tcp_isn_bytes(local6, 50000, remote6, 443, 16),
		      "isn: IPv6 remote address byte left out");
		remote6[i] ^= 1;
		local6[i] ^= 1;
		check(first6 != vinix_tcp_isn_bytes(local6, 50000, remote6, 443, 16),
		      "isn: IPv6 local address byte left out");
		local6[i] ^= 1;
	}
	check(first6 != vinix_tcp_isn_bytes(local6, 50000, remote6, 443, 4),
	      "isn: IPv4 and IPv6 tuples not separated");
	test_isn6();
	test_ports();
	test_uniform();
	test_pooling();
	test_uniform_large_bounds();
	test_port_callback_context();
	test_pool_boundaries_and_fallback();
	if (failures) {
		printf("net-random: %d failures\n", failures);
		return 1;
	}
	printf("net-random: PASS\n");
	return 0;
}
