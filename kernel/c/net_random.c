/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * The numbers the IP stack makes up, made unpredictable the way OpenBSD makes
 * them. lwIP's own are a counter or a guess away from one:
 *
 * - IP IDs counted up by one per datagram, so anyone who saw two of them knew
 *   how much else the machine had sent in between: the side channel an idle
 *   scan uses. ip_randomid() draws them from a shuffle of every ID instead.
 * - TCP initial sequence numbers were 6510 plus the ticks since boot, added up
 *   per connection, so the next one could be predicted and a connection
 *   spoofed or reset blind. They are RFC 6528's now, keyed by a secret.
 * - Ephemeral ports were handed out one after another from a start chosen by
 *   the clock, which is what made DNS cache poisoning practical. Each is now
 *   picked at random, as OpenBSD's in_pcbpickport() picks them.
 * - LWIP_RAND, behind DNS transaction IDs and DHCP's, was an xorshift seeded
 *   from the clock. It reads the kernel's ChaCha20 generator now.
 *
 * Callers serialise: lwIP runs under the network lock.
 */
#include "net_random.h"

#include <string.h>

_Bool krandom__fill(void *buf, uint64_t count, _Bool allow_insecure);
uint64_t time__monotonic_ns(void);
void vinix_explicit_bzero(void *buf, size_t len);

/*
 * Bytes from the kernel's generator, taken a few blocks at a time: an IP ID
 * is two bytes, and each request of the generator costs two ChaCha20 blocks.
 * Each byte is cleared as it is handed out, as arc4random clears its buffer,
 * so the pool never holds output that has already been used.
 */
static uint8_t pool[256];
static size_t pool_left;
static uint64_t fallback_state;

static uint64_t cycle_counter(void)
{
#if defined(__x86_64__)
	uint32_t low, high;
	__asm__ volatile("rdtsc" : "=a"(low), "=d"(high));
	return ((uint64_t)high << 32) | low;
#elif defined(__aarch64__)
	uint64_t value;
	__asm__ volatile("mrs %0, cntvct_el0" : "=r"(value));
	return value;
#else
	return 0;
#endif
}

static void refill(void)
{
	pool_left = sizeof pool;
	if (krandom__fill(pool, sizeof pool, 1))
		return;
	/* Only before the generator exists, which inet.initialise() sees to. */
	for (size_t i = 0; i < sizeof pool; i += 8) {
		uint64_t z = (fallback_state += 0x9e3779b97f4a7c15ULL) ^ cycle_counter();
		z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
		z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
		z ^= z >> 31;
		memcpy(&pool[i], &z, 8);
	}
}

void vinix_net_random_bytes(void *out, size_t length)
{
	uint8_t *to = out;

	while (length != 0) {
		if (pool_left == 0)
			refill();
		size_t take = length < pool_left ? length : pool_left;
		uint8_t *from = &pool[sizeof pool - pool_left];
		memcpy(to, from, take);
		vinix_explicit_bzero(from, take);
		to += take;
		length -= take;
		pool_left -= take;
	}
}

uint32_t vinix_net_random(void)
{
	uint32_t value;

	vinix_net_random_bytes(&value, sizeof value);
	return value;
}

/* arc4random_uniform(3): a value below upper_bound, with the values that
 * would make the smaller results likelier thrown away. */
uint32_t vinix_net_random_uniform(uint32_t upper_bound)
{
	if (upper_bound < 2)
		return 0;
	uint32_t min = -upper_bound % upper_bound;
	for (;;) {
		uint32_t value = vinix_net_random();
		if (value >= min)
			return value % upper_bound;
	}
}

/*
 * OpenBSD's ip_randomid(): every ID, shuffled once, then read in order with
 * the one just read swapped back into a random slot among the 32768 before
 * it. An ID cannot come up again within 32768 datagrams, which keeps the
 * fragments of different datagrams to the same host apart, and which one
 * comes next cannot be told from those before. 0 is never used.
 */
static uint16_t id_shuffle[65536];
static uint32_t id_index;
static int id_shuffled;

uint16_t vinix_ip_randomid(void)
{
	uint16_t id;

	if (!id_shuffled) {
		/* Knuth's shuffle, in the form that fills the table as it goes. */
		for (uint32_t i = 0; i < 65536; ++i) {
			uint32_t j = vinix_net_random_uniform(i + 1);
			id_shuffle[i] = id_shuffle[j];
			id_shuffle[j] = (uint16_t)i;
		}
		id_shuffled = 1;
	}
	do {
		uint16_t step;
		vinix_net_random_bytes(&step, sizeof step);
		uint32_t i = id_index & 0xffff;
		uint32_t j = (id_index - (step & 0x7fff)) & 0xffff;
		id = id_shuffle[i];
		id_shuffle[i] = id_shuffle[j];
		id_shuffle[j] = id;
		++id_index;
	} while (id == 0);
	return id;
}

/*
 * RFC 6528: ISN = M + F(local address, local port, remote address, remote
 * port, secret). M ticks every 4 microseconds, so a connection that reuses
 * an earlier one's addresses and ports starts past where that one did; F is
 * SipHash-2-4 under a key made at the first connection, as Linux keys its
 * own, so another connection's ISN says nothing about this one's. OpenBSD's
 * tcp_set_iss_tsm() does the same with SHA-512.
 */
static uint8_t isn_key[16];
static int isn_keyed;

uint32_t vinix_tcp_isn_at(uint64_t now_ns, uint32_t local_address, uint16_t local_port,
			  uint32_t remote_address, uint16_t remote_port)
{
	uint8_t tuple[12];

	if (!isn_keyed) {
		vinix_net_random_bytes(isn_key, sizeof isn_key);
		isn_keyed = 1;
	}
	memcpy(&tuple[0], &local_address, 4);
	memcpy(&tuple[4], &remote_address, 4);
	memcpy(&tuple[8], &local_port, 2);
	memcpy(&tuple[10], &remote_port, 2);
	return (uint32_t)(now_ns / 4000) + (uint32_t)vinix_siphash24(isn_key, tuple, sizeof tuple);
}

uint32_t vinix_tcp_isn(uint32_t local_address, uint16_t local_port, uint32_t remote_address,
		       uint16_t remote_port)
{
	return vinix_tcp_isn_at(time__monotonic_ns(), local_address, local_port, remote_address,
				remote_port);
}

/* IPv6 hashes all 128 address bits, rather than silently retaining the IPv4
 * hook's first word. The family is separated by the tuple length. */
uint32_t vinix_tcp_isn_bytes(const void *local, uint16_t local_port,
			    const void *remote, uint16_t remote_port, unsigned length)
{
	uint8_t tuple[36];
	if (length != 4 && length != 16)
		return 0;
	if (!isn_keyed) {
		vinix_net_random_bytes(isn_key, sizeof isn_key);
		isn_keyed = 1;
	}
	memcpy(tuple, local, length);
	memcpy(tuple + length, remote, length);
	memcpy(tuple + length * 2, &local_port, 2);
	memcpy(tuple + length * 2 + 2, &remote_port, 2);
	return (uint32_t)(time__monotonic_ns() / 4000) +
		(uint32_t)vinix_siphash24(isn_key, tuple, length * 2 + 4);
}

/*
 * OpenBSD's in_pcbpickport(): start at a random port of the range and take
 * the first one from there that nothing has bound. 0 when every one has.
 */
uint16_t vinix_pick_port(uint16_t first, uint16_t last, vinix_port_taken_fn taken, void *context)
{
	uint32_t count = (uint32_t)last - first + 1;
	uint32_t candidate = first + vinix_net_random_uniform(count);

	for (uint32_t tried = 0; tried < count; ++tried) {
		if (!taken((uint16_t)candidate, context))
			return (uint16_t)candidate;
		candidate = candidate == last ? first : candidate + 1;
	}
	return 0;
}

static uint64_t load64(const uint8_t *in)
{
	uint64_t value = 0;

	for (int i = 7; i >= 0; --i)
		value = (value << 8) | in[i];
	return value;
}

#define ROTL(x, b) (((x) << (b)) | ((x) >> (64 - (b))))
#define SIPROUND                                                                  \
	do {                                                                      \
		v0 += v1;                                                         \
		v1 = ROTL(v1, 13);                                                \
		v1 ^= v0;                                                         \
		v0 = ROTL(v0, 32);                                                \
		v2 += v3;                                                         \
		v3 = ROTL(v3, 16);                                                \
		v3 ^= v2;                                                         \
		v0 += v3;                                                         \
		v3 = ROTL(v3, 21);                                                \
		v3 ^= v0;                                                         \
		v2 += v1;                                                         \
		v1 = ROTL(v1, 17);                                                \
		v1 ^= v2;                                                         \
		v2 = ROTL(v2, 32);                                                \
	} while (0)

/* SipHash-2-4 (Aumasson and Bernstein), with a 64-bit result. */
uint64_t vinix_siphash24(const uint8_t key[16], const void *data, size_t length)
{
	const uint8_t *in = data;
	uint64_t k0 = load64(&key[0]);
	uint64_t k1 = load64(&key[8]);
	uint64_t v0 = 0x736f6d6570736575ULL ^ k0;
	uint64_t v1 = 0x646f72616e646f6dULL ^ k1;
	uint64_t v2 = 0x6c7967656e657261ULL ^ k0;
	uint64_t v3 = 0x7465646279746573ULL ^ k1;
	uint64_t last = (uint64_t)length << 56;
	size_t whole = length & ~(size_t)7;

	for (size_t at = 0; at < whole; at += 8) {
		uint64_t m = load64(&in[at]);
		v3 ^= m;
		SIPROUND;
		SIPROUND;
		v0 ^= m;
	}
	for (size_t i = 0; i < (length & 7); ++i)
		last |= (uint64_t)in[whole + i] << (8 * i);
	v3 ^= last;
	SIPROUND;
	SIPROUND;
	v0 ^= last;
	v2 ^= 0xff;
	SIPROUND;
	SIPROUND;
	SIPROUND;
	SIPROUND;
	return v0 ^ v1 ^ v2 ^ v3;
}
