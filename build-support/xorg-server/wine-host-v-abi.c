/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "wine-host-v-abi.h"
/* Signal-safe storage and native callback types stay at the libc boundary. */
static volatile sig_atomic_t running = 1;
int vwh_running(void) { return running; }
void vwh_set_running(int value) { running = value; }
int vwh_errno(void) { return errno; }
void vinix_wine_host_stop(int);
int vinix_wine_host_x_error(Display *, XErrorEvent *);
void vwh_install_signals(void) {
    struct sigaction action = {0};
    action.sa_handler = vinix_wine_host_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
}
void vwh_install_x_error(void) { XSetErrorHandler(vinix_wine_host_x_error); }
void vwh_damage_store(void *p, uint32_t value) { *(volatile uint32_t *)p = value; }
#ifndef VINIX_WINE_HOST_NO_MAIN
int main(int argc, char **argv) { return vinix_wine_host_main(argc, argv); }
#endif
