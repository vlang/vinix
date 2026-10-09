// SPDX-License-Identifier: GPL-2.0-or-later
// Shared native Mac / iOS fixture: declarations intentionally describe Darwin.
struct addrinfo {
    int flags, family, type, protocol;
    unsigned length;
    char *canonical;
    void *address;
    struct addrinfo *next;
};
extern int getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
extern void freeaddrinfo(struct addrinfo *);
extern int getnameinfo(const void *, unsigned, char *, unsigned, char *, unsigned, int);
extern int strcmp(const char *, const char *), puts(const char *), printf(const char *, ...);
extern int snprintf(char *, unsigned long, const char *, ...), *__error(void);
extern int socket(int, int, int), bind(int, const void *, unsigned), getsockname(int, void *, unsigned *), close(int);
extern unsigned short ntohs(unsigned short);
extern long sendto(int, const void *, unsigned long, int, const void *, unsigned), recvfrom(int, void *, unsigned long, int, void *, unsigned *);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-NETDB: failure %d errno %d\n",code,*__error()); return code; } } while (0)
_Static_assert(sizeof(struct addrinfo) == 48 && __builtin_offsetof(struct addrinfo, canonical) == 24 && __builtin_offsetof(struct addrinfo, address) == 32, "Darwin addrinfo ABI");

static int error_case(const char *node, const char *service, struct addrinfo *hints, int expected) {
    struct addrinfo *list = (void *)0x1234;
    *__error() = 177;
    int actual=getaddrinfo(node, service, hints, &list);
    if(actual != expected || list) printf("IOS-NETDB: query %s / %s flags %x family %d type %d protocol %d expected %d actual %d\n",node?node:"NULL",service?service:"NULL",hints->flags,hints->family,hints->type,hints->protocol,expected,actual);
    CHECK(actual == expected && list == 0, 1);
    CHECK(*__error() == 177, 2);
    return 0;
}
static int resolve(const char *node, const char *port, int family, int flags, const char *expected) {
    struct addrinfo hints = {.flags=flags, .family=family, .type=1}, *list;
    *__error() = 177;
    CHECK(getaddrinfo(node, port, &hints, &list) == 0 && list, 3);
    CHECK(*__error() == 177, 4);
    int count = 0;
    for (struct addrinfo *p = list; p; p = p->next) {
        CHECK(++count < 32 && p->flags == 0 && p->family == family && p->type == 1 && p->protocol == 6, 5);
        CHECK(p->length == (family == 2 ? 16u : 28u) && p->address && !p->canonical, 6);
        unsigned char *bytes = p->address;
        CHECK(bytes[0] == p->length && bytes[1] == family, 7);
        char host[128], service[32];
        CHECK(getnameinfo(p->address,p->length,host,sizeof host,service,sizeof service,10) == 0, 8);
        CHECK(!strcmp(host,expected) && !strcmp(service,port) && *__error() == 177, 9);
        char short_host[8]="H", short_service[4]="S";
        CHECK(getnameinfo(p->address,p->length,short_host,1,short_service,4,10) == 14, 10);
        CHECK(!strcmp(short_host,"H") && !strcmp(short_service,"S"), 11);
        CHECK(getnameinfo(p->address,p->length,host,sizeof host,short_service,1,10) == 14, 12);
        CHECK(!strcmp(host,expected) && !strcmp(short_service,"S"), 13);
        CHECK(getnameinfo(p->address,p->length,short_host,0,short_service,0,10) == 0, 14);
        CHECK(!strcmp(short_host,"H") && !strcmp(short_service,"S"), 15);
        CHECK(getnameinfo(p->address,p->length,0,128,0,32,10) == 0, 16);
    }
    freeaddrinfo(list);
    freeaddrinfo(0);
    return 0;
}
static int io(void) {
    struct addrinfo h={.flags=1,.family=2,.type=2}, *server, *client;
    CHECK(getaddrinfo(0,"0",&h,&server) == 0 && server, 17);
    CHECK(server->protocol == 17 && server->length == 16, 18);
    int fd = socket(server->family,server->type,server->protocol);
    CHECK(fd >= 0 && bind(fd,server->address,server->length) == 0, 19);
    freeaddrinfo(server);
    unsigned short address[8]; unsigned length = sizeof address;
    CHECK(getsockname(fd,address,&length) == 0 && length == 16, 20);
    char service[32];
    CHECK(snprintf(service,sizeof service,"%u",(unsigned)ntohs(address[1])) > 0, 21);
    h.flags=4 | 0x1000;
    CHECK(getaddrinfo("127.0.0.1",service,&h,&client) == 0 && client, 22);
    int sender = socket(client->family,client->type,client->protocol);
    CHECK(sender >= 0 && sendto(sender,"DNS",3,0,client->address,client->length) == 3, 23);
    char data[4]; unsigned short peer[8]; length=sizeof peer;
    CHECK(recvfrom(fd,data,sizeof data,0,peer,&length) == 3 && data[0]=='D' && data[2]=='S', 24);
    char host[128];
    CHECK(getnameinfo(peer,length,host,sizeof host,service,sizeof service,10) == 0 && !strcmp(host,"127.0.0.1"), 25);
    freeaddrinfo(client);
    CHECK(close(fd) == 0 && close(sender) == 0, 26);
    return 0;
}
static int check(void) {
    for(int i=0;i<16;i++) {
        int e=resolve("127.0.0.1","443",2,6 | 0x1000,"127.0.0.1"); if(e) return e;
        e=resolve("::1","65535",30,6 | 0x1000,"::1"); if(e) return e;
        e=resolve("127.0.0.1","80",30,4 | 0x800,"::ffff:127.0.0.1"); if(e) return e;
    }
    int e=resolve(0,"443",2,4,"127.0.0.1"); if(e) return e;
    e=resolve(0,"443",2,1,"0.0.0.0"); if(e) return e;
    e=resolve("127.0.0.1","443",30,0,"::ffff:127.0.0.1"); if(e) return e;
    e=resolve("127.0.0.1","443",30,4 | 0x200,"::ffff:127.0.0.1"); if(e) return e;
    struct addrinfo h={.flags=4,.family=2,.type=1};
    e=error_case(0,0,&h,8); if(e) return e;
    e=error_case("localhost","443",&h,8); if(e) return e;
    e=error_case("::1","443",&h,8); if(e) return e;
    e=error_case("127.0.0.1","65536",&h,8); if(e) return e;
    e=error_case("127.0.0.1","-1",&h,8); if(e) return e;
    h.flags |= 0x1000;
    e=error_case("127.0.0.1","80junk",&h,8); if(e) return e;
    h.type=-1; e=error_case("127.0.0.1","443",&h,12); if(e) return e;
    h.type=1; h.protocol=17; e=error_case("127.0.0.1","443",&h,12); if(e) return e;
    h.family=-1; e=error_case("127.0.0.1","443",&h,5); if(e) return e;
#ifndef IOS_NETDB_REFERENCE
    h.family=2; h.protocol=0; h.flags=0x40000000;
    e=error_case("127.0.0.1","443",&h,3); if(e) return e;
#endif
    h=(struct addrinfo){.flags=2,.family=2,.type=1}; struct addrinfo *list;
    CHECK(getaddrinfo("localhost","443",&h,&list) == 0 && list, 27);
    for(struct addrinfo *p=list;p;p=p->next) {
        CHECK(p->canonical && !strcmp(p->canonical,"localhost"), 28);
        char host[128],service[32];
        CHECK(getnameinfo(p->address,p->length,host,sizeof host,service,sizeof service,4 | 8) == 0, 29);
        CHECK(!strcmp(host,"localhost") && !strcmp(service,"443"), 30);
    }
    freeaddrinfo(list);
    h=(struct addrinfo){.flags=4,.family=2};
    CHECK(getaddrinfo("127.0.0.1","80",&h,&list) == 0 && list, 31);
    int tcp=0, udp=0;
    for(struct addrinfo *p=list;p;p=p->next) {
        if(p->type==1 && p->protocol==6) tcp++; else if(p->type==2 && p->protocol==17) udp++; else CHECK(0,32);
    }
    CHECK(tcp==1 && udp==1,33); freeaddrinfo(list);
    CHECK(getaddrinfo("127.0.0.1","80",0,&list) == 0 && list,37);
    tcp=udp=0;
    for(struct addrinfo *p=list;p;p=p->next) {
        if(p->type==1 && p->protocol==6) tcp++; else if(p->type==2 && p->protocol==17) udp++; else CHECK(0,38);
    }
    CHECK(tcp==1 && udp==1,39); freeaddrinfo(list);
    h.type=2;
    CHECK(getaddrinfo("127.0.0.1","domain",&h,&list) == 0 && list,40);
    char host[128],service[32];
    CHECK(getnameinfo(list->address,list->length,host,sizeof host,service,sizeof service,2 | 16) == 0,41);
    CHECK(!strcmp(host,"127.0.0.1") && !strcmp(service,"domain"),42);
    CHECK(getnameinfo(list->address,list->length,host,sizeof host,service,sizeof service,10) == 0 && !strcmp(service,"53"),43);
    freeaddrinfo(list);
    h.flags |= 0x1000; list=(void*)0x1234;
    CHECK(getaddrinfo("127.0.0.1","domain",&h,&list) == 8 && !list,44);
    h=(struct addrinfo){.flags=4,.protocol=58};
    CHECK(getaddrinfo("::1","443",&h,&list) == 0 && list && list->family==30 && list->type==3 && list->protocol==58,45);
    freeaddrinfo(list);
    e=error_case("127.0.0.1","443",&h,8); if(e) return e;
    h=(struct addrinfo){.flags=4,.family=2};
    // Output-only hint members are ignored, as in the installed Mac library.
    h.type=1; h.length=99; h.address=(void*)0x1234; h.canonical=(void*)0x1234; h.next=(void*)0x1234;
    CHECK(getaddrinfo("127.0.0.1","80",&h,&list) == 0 && list,34); freeaddrinfo(list);
    return io();
}
struct job { int result; };
static void *worker(void *argument) { struct job *j=argument; j->result=check(); return 0; }
int main(void) {
    int e=check(); if(e) return e;
    unsigned long clients[8]; struct job jobs[8]={0};
    for(int i=0;i<8;i++) CHECK(pthread_create(&clients[i],0,worker,&jobs[i]) == 0,35);
    int failed=0;
    for(int i=0;i<8;i++) {
        if(pthread_join(clients[i],0) != 0 || jobs[i].result) failed=1;
    }
    CHECK(!failed,36);
    puts("IOS-NETDB: owned Darwin address lists, native names, IPv4/IPv6, mapped addresses, errors and eight-thread UDP I/O");
    return 0;
}
