#include <vore.h>

void vrt_main();

void sys__init_consts();
void mm__init_consts();
void sys__kmain();

void vrt_main() {
    sys__init_consts();
    mm__init_consts();

    sys__kmain();
}