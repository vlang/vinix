/* x86_64 kmod ABI from Apple's mach/kmod.h, packed to four bytes. */
#include <stddef.h>
#include <stdint.h>

extern int kmod_alloc_start(void *, void *);
extern int kmod_alloc_stop(void *, void *);

#pragma pack(push, 4)
struct benchmark_kmod_info {
	void *next;
	int32_t info_version;
	uint32_t id;
	char name[64];
	char version[64];
	int32_t reference_count;
	void *reference_list;
	uintptr_t address;
	uintptr_t size;
	uintptr_t hdr_size;
	int (*start)(void *, void *);
	int (*stop)(void *, void *);
};
#pragma pack(pop)

_Static_assert(sizeof(struct benchmark_kmod_info) == 196, "x86_64 kmod ABI");
struct benchmark_kmod_info kmod_info = {
	0, 1, UINT32_MAX, "org.vinix.AllocKernelBench", "1.0.0", -1,
	0, 0, 0, 0, kmod_alloc_start, kmod_alloc_stop
};
