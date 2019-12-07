#include <vore.h>

void vrt_main();

void sys__init_consts();
void io__init_consts();
void sys__kmain();

void vrt_main() {
    sys__init_consts();
    io__init_consts();

    sys__kmain();
}