#ifndef VINIX_ENDPOINT_H
#define VINIX_ENDPOINT_H
#include <stdint.h>
/* Address words and port are in network byte order; scope is a Linux ifindex.
 * This value is copied synchronously and never retained by a public call. */
struct vinix_net_endpoint {
    uint32_t words[4];
    uint32_t scope;
    uint16_t family;
    uint16_t port;
};

#endif
