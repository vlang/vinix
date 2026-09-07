#include <stddef.h>
#include <vinix/hypervisor.h>

_Static_assert(VINIX_HV_API_VERSION == 1, "unexpected API version");
_Static_assert(sizeof(struct vinix_hv_create) == 8, "create ABI changed");
_Static_assert(sizeof(struct vinix_hv_registers) == 15 * 8, "register ABI changed");
_Static_assert(sizeof(struct vinix_hv_entry) == 24, "entry ABI changed");
_Static_assert(sizeof(struct vinix_hv_exit) == 24, "exit ABI changed");
_Static_assert(offsetof(struct vinix_hv_exit, qualification) == 8,
               "exit qualification is misaligned");

int main(void) {
    return VINIX_HV_GET_API_VERSION != 0x48560000UL ||
           VINIX_HV_CREATE_VM != 0x48560001UL ||
           VINIX_HV_RUN != 0x48560006UL;
}
