/* Included by vinix_net.c: every call runs under the existing lwIP lock. */

/* Linux exposes lo=1, eth0=2. lwIP's native index increments on hotplug,
 * so translate only at the API boundary; zones keep the native index. */
static uint32_t linux_interface_index(struct netif *interface) {
    if (!interface) return 0;
    if (interface == &physical_netif) return 2;
    return ip4_addr_isloopback(netif_ip4_addr(interface)) ? 1 : 0;
}
static struct netif *interface_index(uint32_t index) {
    if (index == 2) return link_attached ? &physical_netif : NULL;
    if (index != 1) return NULL;
    struct netif *interface;
    NETIF_FOREACH(interface) if (linux_interface_index(interface) == 1) return interface;
    return NULL;
}

static uint64_t interface_epoch(struct netif *interface) {
    return interface == &physical_netif ? link_epoch : 1;
}

static struct netif *multicast_interface(uint32_t index, uint32_t address) {
    if (index) return interface_index(index);
    if (address) {
        struct netif *interface;
        NETIF_FOREACH(interface) {
            if (netif_ip4_addr(interface)->addr == address) return interface;
        }
        return NULL;
    }
    return netif_default;
}

static int endpoint_ip(struct vinix_socket *socket,
                       const struct vinix_net_endpoint *endpoint, ip_addr_t *ip) {
    if (!socket || !endpoint) return 22;
    memset(ip, 0, sizeof(*ip));
    if (endpoint->family == 2) {
        if (socket->family != 2 && socket->v6only) return 97;
        *ip = ipv4(endpoint->words[0]);
        return 0;
    }
    if (endpoint->family != 10 || socket->family != 10) return 97;
    IP_SET_TYPE_VAL(*ip, IPADDR_TYPE_V6);
    memcpy(ip_2_ip6(ip)->addr, endpoint->words, 16);
    if (ip6_addr_isipv4mappedipv6(ip_2_ip6(ip))) {
        if (socket->v6only) return 101;
        *ip = ipv4(endpoint->words[3]);
        return 0;
    }
    if (endpoint->scope) {
        struct netif *interface = interface_index(endpoint->scope);
        if (!interface || !netif_is_up(interface)) return 19;
        ip6_addr_assign_zone(ip_2_ip6(ip), IP6_UNKNOWN, interface);
    } else if (ip6_addr_lacks_zone(ip_2_ip6(ip), IP6_UNKNOWN)) {
        uint32_t index = socket->multicast_if6;
        const ip_addr_t *local = socket->udp ? &socket->udp->local_ip :
                                socket->tcp ? &socket->tcp->local_ip : NULL;
        if (!index && local && IP_IS_V6(local))
            index = linux_interface_index(netif_get_by_index(ip6_addr_zone(ip_2_ip6(local))));
        struct netif *interface = interface_index(index);
        if (!interface) return 22;
        ip6_addr_assign_zone(ip_2_ip6(ip), IP6_UNKNOWN, interface);
    }
    return 0;
}

static void endpoint_from_ip(int family, const ip_addr_t *ip,
                             uint16_t port, struct vinix_net_endpoint *endpoint) {
    memset(endpoint, 0, sizeof(*endpoint));
    endpoint->family = (uint16_t)family;
    endpoint->port = port;
    if (IP_IS_V6(ip)) {
        memcpy(endpoint->words, ip_2_ip6(ip)->addr, 16);
        endpoint->scope = linux_interface_index(netif_get_by_index(ip6_addr_zone(ip_2_ip6(ip))));
    } else if (!IP_IS_ANY_TYPE_VAL(*ip)) {
        if (family == 10) {
            endpoint->words[2] = PP_HTONL(0x0000ffff);
            endpoint->words[3] = ip_2_ip4(ip)->addr;
        } else {
            endpoint->words[0] = ip_2_ip4(ip)->addr;
        }
    }
}

struct vinix_socket *vinix_socket_new_family(int type, int protocol, int family) {
    if (family != 2 && family != 10) return NULL;
    struct vinix_socket *socket = vinix_socket_new(type, protocol);
    if (!socket) return NULL;
    socket->family = family;
    if (family == 10) {
        struct ip_pcb *pcb = socket_ip_pcb(socket);
        IP_SET_TYPE_VAL(pcb->local_ip, IPADDR_TYPE_ANY);
        IP_SET_TYPE_VAL(pcb->remote_ip, IPADDR_TYPE_ANY);
    }
    return socket;
}

int vinix_socket_bind_endpoint(struct vinix_socket *socket,
                               const struct vinix_net_endpoint *endpoint) {
    ip_addr_t ip;
    int error = endpoint_ip(socket, endpoint, &ip);
    if (error) return error;
    if (IP_IS_V6(&ip) && !ip6_addr_isany(ip_2_ip6(&ip)) &&
        !ip6_addr_ismulticast(ip_2_ip6(&ip))) {
        struct netif *interface;
        int found = 0;
        NETIF_FOREACH(interface) {
            if (endpoint->scope && linux_interface_index(interface) != endpoint->scope) continue;
            for (int slot = 0; slot < LWIP_IPV6_NUM_ADDRESSES; ++slot) {
                if (ip6_addr_isvalid(netif_ip6_addr_state(interface, slot)) &&
                    ip6_addr_cmp(netif_ip6_addr(interface, slot), ip_2_ip6(&ip))) found = 1;
            }
        }
        if (!found) return 99;
    }
    if (socket->family == 10 && !socket->v6only &&
        IP_IS_V6(&ip) && ip6_addr_isany(ip_2_ip6(&ip))) {
        IP_SET_TYPE_VAL(ip, IPADDR_TYPE_ANY);
    }
    return bind_ip(socket, &ip, endpoint->port);
}

int vinix_socket_connect_endpoint(struct vinix_socket *socket,
                                  const struct vinix_net_endpoint *endpoint) {
    ip_addr_t ip;
    int error = endpoint_ip(socket, endpoint, &ip);
    if (error) return error;
    return connect_ip(socket, &ip, endpoint->port);
}

int vinix_socket_send_endpoint(struct vinix_socket *socket, const void *data,
                               size_t length, const struct vinix_net_endpoint *endpoint,
                               int has_address) {
    ip_addr_t ip;
    if (has_address) {
        int error = endpoint_ip(socket, endpoint, &ip);
        if (error) return -error;
    }
    return send_ip(socket, data, length, has_address ? &ip : NULL,
                   has_address ? endpoint->port : 0, has_address);
}

int vinix_socket_recv_endpoint(struct vinix_socket *socket, void *data, size_t length,
                               struct vinix_net_endpoint *endpoint) {
    ip_addr_t ip;
    uint16_t port = 0;
    memset(&ip, 0, sizeof(ip));
    int result = recv_ip(socket, data, length, &ip, &port);
    if (result >= 0 && endpoint) endpoint_from_ip(socket->family, &ip, port, endpoint);
    return result;
}

int vinix_socket_name_endpoint(struct vinix_socket *socket,
                               struct vinix_net_endpoint *endpoint, int peer) {
    if (!socket || !endpoint) return 22;
    if (peer && !socket->connected) return 107;
    const ip_addr_t *ip;
    uint16_t port;
    if (socket->type == VINIX_NET_STREAM) {
        ip = socket->tcp ? (peer ? &socket->tcp->remote_ip : &socket->tcp->local_ip) :
                          (peer ? &socket->last_remote_address : &socket->last_local_address);
        port = socket->tcp ? lwip_htons(peer ? socket->tcp->remote_port : socket->tcp->local_port) :
                            (peer ? socket->last_remote_port : socket->last_local_port);
    } else {
        ip = peer ? &socket->udp->remote_ip : &socket->udp->local_ip;
        port = lwip_htons(peer ? socket->udp->remote_port : socket->udp->local_port);
    }
    endpoint_from_ip(socket->family, ip, port, endpoint);
    return 0;
}

/* Preserve the original IPv4 bridge ABI used by existing production/tests. */
int vinix_socket_bind(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    ip_addr_t ip = ipv4(address);
    return bind_ip(socket, &ip, port);
}
int vinix_socket_connect(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    ip_addr_t ip = ipv4(address);
    return connect_ip(socket, &ip, port);
}
int vinix_socket_send(struct vinix_socket *socket, const void *data, size_t length,
                      uint32_t address, uint16_t port, int has_address) {
    ip_addr_t ip = ipv4(address);
    return send_ip(socket, data, length, &ip, port, has_address);
}
int vinix_socket_recv(struct vinix_socket *socket, void *data, size_t length,
                      uint32_t *address, uint16_t *port) {
    ip_addr_t ip;
    int result = recv_ip(socket, data, length, address ? &ip : NULL, port);
    if (result >= 0 && address) *address = ip_2_ip4(&ip)->addr;
    return result;
}

static int live_membership(struct membership *member, struct netif *interface) {
    return member->used && interface && linux_interface_index(interface) == member->ifindex &&
           interface_epoch(interface) == member->epoch;
}

static int has_membership(struct vinix_socket *socket, const ip_addr_t *group,
                          struct netif *interface) {
    for (int i = 0; i < SOCKET_MEMBERSHIPS; ++i) {
        struct membership *member = &socket->memberships[i];
        if (live_membership(member, interface) && ip_addr_cmp(&member->group, group)) return 1;
    }
    return 0;
}

static int automatic_allhosts(const ip_addr_t *group) {
    return IP_IS_V4(group) && ip_2_ip4(group)->addr == PP_HTONL(0xe0000001);
}

static err_t leave_membership(struct membership *member, struct netif *interface) {
    /* IGMP owns the permanent 224.0.0.1 group until netif_remove. Its native
     * join/leave API excludes this address; socket policy records borrow it. */
    if (automatic_allhosts(&member->group)) return ERR_OK;
    return IP_IS_V6(&member->group) ? mld6_leavegroup_netif(interface, ip_2_ip6(&member->group)) :
                                    igmp_leavegroup_netif(interface, ip_2_ip4(&member->group));
}

static void release_memberships(struct vinix_socket *socket) {
    for (int i = 0; i < SOCKET_MEMBERSHIPS; ++i) {
        struct membership *member = &socket->memberships[i];
        struct netif *interface = interface_index(member->ifindex);
        if (live_membership(member, interface)) (void)leave_membership(member, interface);
        member->used = 0;
    }
}

int vinix_socket_membership(struct vinix_socket *socket,
                            const struct vinix_net_endpoint *endpoint,
                            uint32_t interface_address, int join) {
    if (!socket || !endpoint || (endpoint->family != 2 && endpoint->family != 10)) return 22;
    if (endpoint->family == 10 && socket->family != 10) return 92;
    ip_addr_t group;
    memset(&group, 0, sizeof(group));
    IP_SET_TYPE_VAL(group, endpoint->family == 10 ? IPADDR_TYPE_V6 : IPADDR_TYPE_V4);
    if (endpoint->family == 10) memcpy(ip_2_ip6(&group)->addr, endpoint->words, 16);
    else ip_2_ip4(&group)->addr = endpoint->words[0];
    if (!ip_addr_ismulticast(&group)) return 22;
    uint32_t index = endpoint->scope;
    struct netif *interface = NULL;
    if (!join && !index && !interface_address) {
        for (int i = 0; i < SOCKET_MEMBERSHIPS; ++i) {
            struct membership *member = &socket->memberships[i];
            struct netif *candidate = interface_index(member->ifindex);
            if (live_membership(member, candidate)) {
                ip_addr_t comparable = group;
                if (IP_IS_V6(&comparable)) ip6_addr_assign_zone(ip_2_ip6(&comparable), IP6_MULTICAST, candidate);
                if (ip_addr_cmp(&member->group, &comparable)) { interface = candidate; break; }
            }
        }
        if (!interface) return 99;
    } else {
        if (!index && !interface_address) index = endpoint->family == 10 ? socket->multicast_if6 : socket->multicast_if4;
        interface = multicast_interface(index, interface_address);
    }
    if (!interface || !netif_is_up(interface)) return 19;
    if (IP_IS_V6(&group)) ip6_addr_assign_zone(ip_2_ip6(&group), IP6_MULTICAST, interface);
    int available = -1;
    for (int i = 0; i < SOCKET_MEMBERSHIPS; ++i) {
        struct membership *member = &socket->memberships[i];
        if (!live_membership(member, interface_index(member->ifindex))) {
            member->used = 0;
            if (available < 0) available = i;
            continue;
        }
        if (member->ifindex != linux_interface_index(interface) || !ip_addr_cmp(&member->group, &group)) continue;
        if (join) return 98;
        err_t error = leave_membership(member, interface);
        if (error != ERR_OK) return linux_error(error);
        member->used = 0;
        return 0;
    }
    if (!join) return 99;
    if (available < 0) return 105;
    /* Native group use is u8_t and also includes other protocol owners.
     * Reject saturation before lwIP increments and wraps the shared count. */
    if (IP_IS_V6(&group)) {
        struct mld_group *existing = mld6_lookfor_group(interface, ip_2_ip6(&group));
        if (existing && existing->use == UINT8_MAX) return 105;
    } else {
        struct igmp_group *existing = igmp_lookfor_group(interface, ip_2_ip4(&group));
        if (!automatic_allhosts(&group) && existing && existing->use == UINT8_MAX) return 105;
    }
    err_t error;
    if (automatic_allhosts(&group)) {
        if (!igmp_lookfor_group(interface, ip_2_ip4(&group))) return 12;
        error = ERR_OK;
    } else {
        error = IP_IS_V6(&group) ? mld6_joingroup_netif(interface, ip_2_ip6(&group)) :
                                  igmp_joingroup_netif(interface, ip_2_ip4(&group));
    }
    if (error != ERR_OK) return linux_error(error);
    struct membership *member = &socket->memberships[available];
    ip_addr_copy(member->group, group);
    member->ifindex = (uint8_t)linux_interface_index(interface);
    member->epoch = interface_epoch(interface);
    member->used = 1;
    return 0;
}

int vinix_socket_multicast_interface(struct vinix_socket *socket, int family,
                                     uint32_t index, uint32_t interface_address) {
    if (!socket || !socket->udp) return 92;
    if (family == 10 && socket->family != 10) return 92;
    struct netif *interface = (index || interface_address) ?
                             multicast_interface(index, interface_address) : NULL;
    if ((index || interface_address) && !interface) return 19;
    if (family == 10) socket->multicast_if6 = interface ? linux_interface_index(interface) : 0;
    else {
        socket->multicast_if4 = interface ? linux_interface_index(interface) : 0;
        socket->multicast_addr4 = interface_address;
    }
    return 0;
}

int vinix_net_ipv6_address(uint32_t index, uint32_t slot,
                           struct vinix_net_endpoint *endpoint, uint32_t *state,
                           uint32_t *valid_life, uint32_t *preferred_life) {
    struct netif *interface = interface_index(index);
    if (!interface || slot >= LWIP_IPV6_NUM_ADDRESSES) return 0;
    ip_addr_t ip;
    IP_SET_TYPE_VAL(ip, IPADDR_TYPE_V6);
    ip6_addr_copy(*ip_2_ip6(&ip), *netif_ip6_addr(interface, slot));
    endpoint_from_ip(10, &ip, 0, endpoint);
    if (state) *state = netif_ip6_addr_state(interface, slot);
    if (valid_life) *valid_life = netif_ip6_addr_valid_life(interface, slot);
    if (preferred_life) *preferred_life = netif_ip6_addr_pref_life(interface, slot);
    return 1;
}

static int family_set_option(struct vinix_socket *socket, int level, int option, int value) {
    struct ip_pcb *pcb = socket_ip_pcb(socket);
    if (level == 0) {
        if (option == 2) {
            if (value < -1 || value == 0 || value > 255) return 22;
            if (value == -1) value = 64;
            socket->hops4 = value;
            if (pcb && !IP_IS_V6(&pcb->remote_ip)) pcb->ttl = (uint8_t)value;
            return 0;
        }
        if (!socket->udp) return 92;
        if (value < 0 || value > 255) return 22;
        if (option == 33) socket->multicast_hops4 = value;
        else if (option == 34) socket->multicast_loop4 = value != 0;
        else return 92;
        return 0;
    }
    if (socket->family != 10) return 92;
    if (option == 26) { /* IPV6_V6ONLY: the family is settled before binding. */
        if (value != 0 && value != 1) return 22;
        if (!pcb || socket->connected || socket->connecting || socket->listening ||
            (socket->tcp ? socket->tcp->local_port : socket->udp->local_port)) return 22;
        socket->v6only = value;
        IP_SET_TYPE_VAL(pcb->local_ip, value ? IPADDR_TYPE_V6 : IPADDR_TYPE_ANY);
        IP_SET_TYPE_VAL(pcb->remote_ip, value ? IPADDR_TYPE_V6 : IPADDR_TYPE_ANY);
        return 0;
    }
    if (option == 16) { /* IPV6_UNICAST_HOPS */
        if (value < -1 || value > 255) return 22;
        socket->hops6 = value == -1 ? 64 : value;
        if (pcb && IP_IS_V6(&pcb->remote_ip)) pcb->ttl = (uint8_t)socket->hops6;
        return 0;
    }
    if (!socket->udp) return 92;
    if (option == 17) { /* IPV6_MULTICAST_IF */
        if (value < 0) return 19;
        return vinix_socket_multicast_interface(socket, 10, (uint32_t)value, 0);
    }
    if (option == 18) { /* IPV6_MULTICAST_HOPS */
        if (value < -1 || value > 255) return 22;
        socket->multicast_hops6 = value == -1 ? 1 : value;
        return 0;
    }
    if (option == 19) { /* IPV6_MULTICAST_LOOP */
        if (value != 0 && value != 1) return 22;
        socket->multicast_loop6 = value;
        return 0;
    }
    return 92;
}

static int family_get_option(struct vinix_socket *socket, int level, int option, int *value) {
    if (level == 0) {
        if (option == 2) { *value = socket->hops4; return 0; }
        if (!socket->udp) return 92;
        if (option == 32) *value = (int)socket->multicast_addr4;
        else if (option == 33) *value = socket->multicast_hops4;
        else if (option == 34) *value = socket->multicast_loop4;
        else return 92;
        return 0;
    }
    if (socket->family != 10) return 92;
    if (option == 24) { /* IPV6_MTU: connected path's discovered MTU. */
        struct ip_pcb *pcb = socket_ip_pcb(socket);
        if (!socket->connected || !pcb || !IP_IS_V6(&pcb->remote_ip)) return 107;
        struct netif *interface = ip6_route(ip_2_ip6(&pcb->local_ip), ip_2_ip6(&pcb->remote_ip));
        if (!interface) return 101;
        *value = nd6_get_destination_mtu(ip_2_ip6(&pcb->remote_ip), interface);
        return 0;
    }
    if (option == 26) { *value = socket->v6only; return 0; }
    if (option == 16) { *value = socket->hops6; return 0; }
    if (!socket->udp) return 92;
    if (option == 17) *value = (int)socket->multicast_if6;
    else if (option == 18) *value = socket->multicast_hops6;
    else if (option == 19) *value = socket->multicast_loop6;
    else return 92;
    return 0;
}
