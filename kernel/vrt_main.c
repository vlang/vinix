#include <vore.h>

void vrt_main(void* bootloader_info, int magic);

void sys__init_consts();
void mm__init_consts();
void sys__kmain(void* bootloader_info, int magic);

void vrt_main(void* bootloader_info, int magic) {
    sys__init_consts();
    mm__init_consts();
    
    sys__kmain(bootloader_info, magic);
}
