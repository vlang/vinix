#ifndef VINIX_RENDER_TEST_ABI_H
#define VINIX_RENDER_TEST_ABI_H
/* Test-only SDK declarations; process and socket algorithms live in V. */
#include <termios.h>
#include <sys/socket.h>
#include <sys/un.h>
typedef struct sockaddr_un vinix_render_test_address;
#endif
