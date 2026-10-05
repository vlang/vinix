#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("VINIX IPV6: FAIL line=%d errno=%d: %s\n", __LINE__, errno, #x); return 1; } } while (0)
static struct sockaddr_in6 addr6(const char *text, unsigned port, unsigned scope) {
    struct sockaddr_in6 result = {.sin6_family = AF_INET6, .sin6_port = htons(port), .sin6_scope_id = scope};
    if (inet_pton(AF_INET6, text, &result.sin6_addr) != 1) abort();
    return result;
}
static int ready(int fd) { struct pollfd p = {.fd=fd,.events=POLLIN}; return poll(&p, 1, 2000) == 1 && (p.revents & POLLIN); }
static int recvcheck(int fd, const char *value) {
    char buffer[64];
    if (!ready(fd)) return -1;
    ssize_t count = recv(fd, buffer, sizeof buffer, 0);
    return count == (ssize_t)strlen(value) && !memcmp(buffer, value, count) ? 0 : -1;
}
static int loopback(void) {
    int receiver = socket(AF_INET6, SOCK_DGRAM, 0), sender = socket(AF_INET6, SOCK_DGRAM, 0);
    CHECK(receiver >= 0 && sender >= 0);
    struct sockaddr_in6 local = addr6("::1", 19001, 0), peer;
    CHECK(bind(receiver, (void *)&local, sizeof local - 1) == -1 && errno == EINVAL);
    CHECK(bind(receiver, (void *)&local, sizeof local) == 0);
    CHECK(sendto(sender, "loop6", 5, 0, (void *)&local, sizeof local) == 5);
    char bytes[16]; socklen_t length = sizeof peer;
    CHECK(ready(receiver) && recvfrom(receiver, bytes, sizeof bytes, 0, (void *)&peer, &length) == 5);
    CHECK(length == sizeof peer && peer.sin6_family == AF_INET6 && IN6_IS_ADDR_LOOPBACK(&peer.sin6_addr) && peer.sin6_scope_id == 0);
    length = sizeof peer;
    CHECK(getsockname(receiver, (void *)&peer, &length) == 0 && peer.sin6_port == local.sin6_port);
    int domain; length = sizeof domain;
    CHECK(getsockopt(receiver, SOL_SOCKET, SO_DOMAIN, &domain, &length) == 0 && domain == AF_INET6);
    CHECK(connect(sender, (void *)&local, sizeof local) == 0 && send(sender, "again", 5, 0) == 5 && recvcheck(receiver, "again") == 0);
    close(receiver); close(sender);
    int listener = socket(AF_INET6, SOCK_STREAM, 0), client = socket(AF_INET6, SOCK_STREAM, 0);
    local = addr6("::1", 19002, 0);
    CHECK(listener >= 0 && client >= 0 && bind(listener, (void *)&local, sizeof local) == 0 && listen(listener, 8) == 0);
    CHECK(connect(client, (void *)&local, sizeof local) == 0);
    length = sizeof peer; int server = accept(listener, (void *)&peer, &length);
    CHECK(server >= 0 && length == sizeof peer && peer.sin6_family == AF_INET6 && IN6_IS_ADDR_LOOPBACK(&peer.sin6_addr));
    CHECK(send(client, "tcp6", 4, 0) == 4 && recvcheck(server, "tcp6") == 0);
    CHECK(send(server, "reply", 5, 0) == 5 && recvcheck(client, "reply") == 0);
    FILE *table = fopen("/proc/net/tcp6", "r"); CHECK(table != NULL);
    char line[512]; int found = 0; while (fgets(line, sizeof line, table)) if (strstr(line, "00000000000000000000000001000000")) found = 1;
    fclose(table); CHECK(found);
    close(client); close(server); close(listener);
    puts("IPV6 PASS: TCP and UDP loopback, names and tcp6"); return 0;
}
static int dual(void) {
    int receiver = socket(AF_INET6, SOCK_DGRAM, 0), sender = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in6 any = addr6("::", 19003, 0), peer;
    struct sockaddr_in v4 = {.sin_family=AF_INET,.sin_port=htons(19003),.sin_addr={htonl(INADDR_LOOPBACK)}};
    CHECK(receiver >= 0 && sender >= 0 && bind(receiver, (void *)&any, sizeof any) == 0);
    CHECK(sendto(sender, "dual", 4, 0, (void *)&v4, sizeof v4) == 4);
    char bytes[8]; socklen_t length = sizeof peer;
    CHECK(ready(receiver) && recvfrom(receiver, bytes, sizeof bytes, 0, (void *)&peer, &length) == 4 && IN6_IS_ADDR_V4MAPPED(&peer.sin6_addr));
    CHECK(sendto(receiver, "mapped", 6, 0, (void *)&peer, sizeof peer) == 6 && recvcheck(sender, "mapped") == 0);
    close(receiver); close(sender);
    receiver = socket(AF_INET6, SOCK_DGRAM, 0); int one = 1;
    CHECK(receiver >= 0 && setsockopt(receiver, IPPROTO_IPV6, IPV6_V6ONLY, &one, 1) == -1 && errno == EINVAL);
    CHECK(setsockopt(receiver, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof one) == 0);
    struct sockaddr_in6 mapped = addr6("::ffff:127.0.0.1", 19003, 0);
    CHECK(sendto(receiver, "x", 1, 0, (void *)&mapped, sizeof mapped) == -1 && errno == ENETUNREACH);
    CHECK(bind(receiver, (void *)&any, sizeof any) == 0);
    one = 0; CHECK(setsockopt(receiver, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof one) == -1 && errno == EINVAL);
    close(receiver);
    int listener=socket(AF_INET6,SOCK_STREAM,0);
    any.sin6_port=htons(19004);
    CHECK(listener>=0 && bind(listener,(void *)&any,sizeof any)==0 && listen(listener,8)==0);
    for(int family=AF_INET;family<=AF_INET6;family+=8) {
        int client=socket(family,SOCK_STREAM,0); CHECK(client>=0);
        struct sockaddr_in6 destination=addr6("::1",19004,0);
        v4.sin_port=htons(19004);
        CHECK(connect(client,family==AF_INET6 ? (void *)&destination : (void *)&v4,family==AF_INET6 ? sizeof destination : sizeof v4)==0);
        length=sizeof peer; int server=accept(listener,(void *)&peer,&length);
        CHECK(server>=0 && length==sizeof peer && peer.sin6_family==AF_INET6);
        CHECK(family==AF_INET6 ? IN6_IS_ADDR_LOOPBACK(&peer.sin6_addr) : IN6_IS_ADDR_V4MAPPED(&peer.sin6_addr));
        CHECK(send(client,"both",4,0)==4 && recvcheck(server,"both")==0);
        close(client);close(server);
    }
    close(listener);
    puts("IPV6 PASS: mapped addresses and V6ONLY"); return 0;
}
static int membership(int family, unsigned interface, int print) {
    int a = socket(family, SOCK_DGRAM | SOCK_NONBLOCK, 0), b = socket(family, SOCK_DGRAM | SOCK_NONBLOCK, 0), sender = socket(family, SOCK_DGRAM, 0), one = 1;
    CHECK(a >= 0 && b >= 0 && sender >= 0);
    CHECK(setsockopt(a, SOL_SOCKET, SO_REUSEADDR, &one, 4) == 0 && setsockopt(b, SOL_SOCKET, SO_REUSEADDR, &one, 4) == 0);
    struct sockaddr_in6 any6 = addr6("::", 19010 + family, 0), group6 = addr6("ff02::1234", 19010 + family, interface);
    struct sockaddr_in any4 = {.sin_family=AF_INET,.sin_port=htons(19010 + family)}, group4=any4;
    CHECK(inet_pton(AF_INET, "239.1.2.3", &group4.sin_addr) == 1);
    void *any = family == AF_INET6 ? (void *)&any6 : (void *)&any4, *group = family == AF_INET6 ? (void *)&group6 : (void *)&group4;
    socklen_t size = family == AF_INET6 ? sizeof any6 : sizeof any4;
    CHECK(bind(a, any, size) == 0 && bind(b, any, size) == 0);
    struct ipv6_mreq request6 = {.ipv6mr_multiaddr=group6.sin6_addr,.ipv6mr_interface=interface};
    struct ip_mreqn request4 = {.imr_multiaddr=group4.sin_addr,.imr_ifindex=(int)interface};
    void *request = family == AF_INET6 ? (void *)&request6 : (void *)&request4;
    unsigned reqsize = family == AF_INET6 ? sizeof request6 : sizeof request4;
    int level = family == AF_INET6 ? IPPROTO_IPV6 : IPPROTO_IP, join = family == AF_INET6 ? IPV6_JOIN_GROUP : IP_ADD_MEMBERSHIP, leave = family == AF_INET6 ? IPV6_LEAVE_GROUP : IP_DROP_MEMBERSHIP;
    CHECK(setsockopt(a, level, join, request, reqsize) == 0 && setsockopt(b, level, join, request, reqsize) == 0);
    CHECK(setsockopt(a, level, join, request, reqsize) == -1 && errno == EADDRINUSE);
    if (family == AF_INET6) CHECK(setsockopt(sender, level, IPV6_MULTICAST_IF, &interface, 4) == 0);
    else CHECK(setsockopt(sender, level, IP_MULTICAST_IF, &request4, sizeof request4) == 0);
    CHECK(sendto(sender, "joined", 6, 0, group, size) == 6 && recvcheck(a, "joined") == 0 && recvcheck(b, "joined") == 0);
    char bytes[16]; CHECK(recv(a, bytes, sizeof bytes, 0) == -1 && errno == EAGAIN); /* one loop delivery */
    CHECK(setsockopt(a, level, leave, request, reqsize) == 0);
    CHECK(setsockopt(a, level, leave, request, reqsize) == -1 && errno == EADDRNOTAVAIL);
    CHECK(sendto(sender, "left", 4, 0, group, size) == 4 && recvcheck(b, "left") == 0);
    CHECK(recv(a, bytes, sizeof bytes, 0) == -1 && errno == EAGAIN);
    one = 0; CHECK(setsockopt(sender, level, family == AF_INET6 ? IPV6_MULTICAST_LOOP : IP_MULTICAST_LOOP, &one, 4) == 0);
    CHECK(sendto(sender, "off", 3, 0, group, size) == 3 && recv(b, bytes, sizeof bytes, 0) == -1 && errno == EAGAIN);
    CHECK(setsockopt(b, level, leave, request, family == AF_INET6 ? 19 : 7) == -1 && errno == EINVAL);
    CHECK(setsockopt(b, level, leave, (void *)1, reqsize) == -1 && errno == EFAULT);
    close(a); close(b); close(sender);
    if (print) printf("IPV6 PASS: %s multicast interface=%u\n", family == AF_INET6 ? "MLD" : "IGMP", interface);
    return 0;
}
static unsigned long slab(void) {
    FILE *file = fopen("/proc/meminfo", "r"); if (!file) return ~0ul;
    char line[256]; unsigned long result = ~0ul;
    while (fgets(line, sizeof line, file)) if (!strncmp(line, "Slab:", 5)) { result = strtoul(line + 5, NULL, 10); break; }
    fclose(file); return result;
}
static int automatic_membership(void) {
    int receiver=socket(AF_INET,SOCK_DGRAM,0),sender=socket(AF_INET,SOCK_DGRAM,0);
    CHECK(receiver>=0 && sender>=0);
    struct sockaddr_in any={.sin_family=AF_INET,.sin_port=htons(19040)},group=any;
    CHECK(inet_pton(AF_INET,"224.0.0.1",&group.sin_addr)==1);
    struct ip_mreqn request={.imr_multiaddr=group.sin_addr,.imr_ifindex=1};
    CHECK(bind(receiver,(void *)&any,sizeof any)==0);
    CHECK(setsockopt(receiver,IPPROTO_IP,IP_ADD_MEMBERSHIP,&request,sizeof request)==0);
    CHECK(setsockopt(sender,IPPROTO_IP,IP_MULTICAST_IF,&request,sizeof request)==0);
    CHECK(sendto(sender,"all-hosts",9,0,(void *)&group,sizeof group)==9 && recvcheck(receiver,"all-hosts")==0);
    CHECK(setsockopt(receiver,IPPROTO_IP,IP_DROP_MEMBERSHIP,&request,sizeof request)==0);
    CHECK(setsockopt(receiver,IPPROTO_IP,IP_ADD_MEMBERSHIP,&request,sizeof request)==0);
    close(receiver);close(sender);
    return 0;
}
static int physical(void) {
    char line[256], local[33] = {0}, linklocal[33] = {0}; int ready_addr = 0;
    for (int attempt = 0; attempt < 80 && !ready_addr; ++attempt) {
        FILE *file = fopen("/proc/net/if_inet6", "r"); CHECK(file != NULL);
        while (fgets(line, sizeof line, file)) {
            if (attempt == 79) printf("IPV6 ADDRESS: %s", line);
            unsigned index, prefix, scope, flags; char name[32], text[33];
            if (sscanf(line, "%32s %x %x %x %x %31s", text, &index, &prefix, &scope, &flags, name) == 6 && index == 2 && !(flags & 0x60)) {
                if (!scope) { memcpy(local,text,33); ready_addr=1; }
                if (scope == 0x20) memcpy(linklocal,text,33);
            }
        }
        fclose(file); if (!ready_addr) usleep(250000);
    }
    CHECK(ready_addr); printf("IPV6 SLAAC: %s\n", local);
    CHECK(linklocal[0]);
    struct sockaddr_in6 scoped={.sin6_family=AF_INET6,.sin6_port=htons(19044)};
    for (int i=0;i<16;++i) { char byte[3]={linklocal[2*i],linklocal[2*i+1],0}; scoped.sin6_addr.s6_addr[i]=(uint8_t)strtoul(byte,NULL,16); }
    int scope_receiver=socket(AF_INET6,SOCK_DGRAM,0), scope_sender=socket(AF_INET6,SOCK_DGRAM,0);
    CHECK(scope_receiver>=0 && scope_sender>=0);
    CHECK(bind(scope_receiver,(void *)&scoped,sizeof scoped)==-1 && errno==EINVAL);
    scoped.sin6_scope_id=999; CHECK(bind(scope_receiver,(void *)&scoped,sizeof scoped)==-1 && errno==ENODEV);
    scoped.sin6_scope_id=1; CHECK(bind(scope_receiver,(void *)&scoped,sizeof scoped)==-1 && errno==EADDRNOTAVAIL);
    scoped.sin6_scope_id=2; CHECK(bind(scope_receiver,(void *)&scoped,sizeof scoped)==0);
    CHECK(sendto(scope_sender,"scoped",6,0,(void *)&scoped,sizeof scoped)==6);
    char scope_data[16]; struct sockaddr_in6 scope_peer; socklen_t scope_length=sizeof scope_peer;
    CHECK(ready(scope_receiver) && recvfrom(scope_receiver,scope_data,sizeof scope_data,0,(void *)&scope_peer,&scope_length)==6 && scope_peer.sin6_scope_id==2);
    close(scope_receiver);close(scope_sender);
    puts("IPV6 PASS: link-local interface scopes");
    struct sockaddr_in6 host = addr6("fec0::2", 39066, 0);
    int stream = socket(AF_INET6, SOCK_STREAM, 0); CHECK(stream >= 0);
    struct timeval timeout = {.tv_sec=5}; CHECK(setsockopt(stream, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout) == 0);
    CHECK(connect(stream, (void *)&host, sizeof host) == 0 && send(stream, "physical", 8, 0) == 8 && recvcheck(stream, "physical") == 0); close(stream);
    int datagram=socket(AF_INET6, SOCK_DGRAM, 0); CHECK(datagram >= 0);
    CHECK(connect(datagram,(void *)&host,sizeof host)==0);
    int mtu; socklen_t mtu_length=sizeof mtu;
    CHECK(getsockopt(datagram,IPPROTO_IPV6,IPV6_MTU,&mtu,&mtu_length)==0 && mtu>=1280 && mtu<=1500);
    CHECK(sendto(datagram, "udpwire", 7, 0, (void *)&host, sizeof host) == 7 && recvcheck(datagram, "udpwire") == 0); close(datagram);
    CHECK(membership(AF_INET, 2, 1) == 0 && membership(AF_INET6, 2, 1) == 0);
    puts("IPV6 PASS: physical TCP/UDP and SLAAC"); return 0;
}
static void alloc_report(void) {
    int fd=open("/proc/allocsites",O_RDONLY); if(fd<0)return;
    char bytes[4096]; ssize_t count;
    while((count=read(fd,bytes,sizeof bytes))>0) write(STDOUT_FILENO,bytes,count);
    close(fd);
}
static void alloc_start(void) {
    int fd=open("/proc/allocstart",O_RDONLY); if(fd<0)return;
    char bytes[64]; (void)read(fd,bytes,sizeof bytes); close(fd);
}
static int proc_snapshots(void) {
    const char *paths[]={"/proc/net/tcp","/proc/net/tcp6","/proc/net/if_inet6"};
    char bytes[1024];
    for(unsigned i=0;i<sizeof paths/sizeof paths[0];++i) {
        int fd=open(paths[i],O_RDONLY); CHECK(fd>=0);
        ssize_t count; do { count=read(fd,bytes,sizeof bytes); } while(count>0);
        CHECK(count==0);close(fd);
    }
    return 0;
}
int main(void) {
#if defined(__x86_64__)
    int serial=open("/dev/com1",O_WRONLY);
    if(serial>=0) { dup2(serial,STDOUT_FILENO);dup2(serial,STDERR_FILENO);close(serial); }
#endif
    setbuf(stdout, NULL);
    puts("VINIX IPV6: START");
    int status = loopback() || dual() || membership(AF_INET,1,1) || membership(AF_INET6,1,1) || automatic_membership() || physical();
    if (!status) {
        int live6=socket(AF_INET6,SOCK_STREAM,0),live4=socket(AF_INET,SOCK_STREAM,0);
        struct sockaddr_in6 local6=addr6("::1",19050,0);
        struct sockaddr_in local4={.sin_family=AF_INET,.sin_port=htons(19051),.sin_addr={htonl(INADDR_LOOPBACK)}};
        CHECK(live6>=0 && live4>=0 && bind(live6,(void *)&local6,sizeof local6)==0 && listen(live6,1)==0);
        CHECK(bind(live4,(void *)&local4,sizeof local4)==0 && listen(live4,1)==0);
        for (int i=0;i<20;++i) CHECK(membership(AF_INET,1,0)==0 && membership(AF_INET6,1,0)==0 && proc_snapshots()==0);
        unsigned long before=slab(); alloc_start();
        for (int i=0;i<500;++i) CHECK(membership(AF_INET,1,0)==0 && membership(AF_INET6,1,0)==0 && proc_snapshots()==0);
        unsigned long after=slab(); alloc_report(); printf("IPV6 SLAB: %lu -> %lu KiB\n",before,after);
        CHECK(before != ~0ul && after <= before + 16);
        close(live6);close(live4);
        puts("IPV6 PASS: repeated memberships and close stay flat");
        puts("VINIX IPV6: PASS");
    }
    sleep(1); sync(); reboot(RB_POWER_OFF); for (;;) pause();
}
