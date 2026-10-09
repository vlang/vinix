// SPDX-License-Identifier: GPL-2.0-or-later
struct ifaddrs {
    struct ifaddrs *next;
    char *name;
    unsigned flags;
    unsigned char *address, *netmask, *destination;
    void *data;
};
extern int getifaddrs(struct ifaddrs **), *__error(void);
extern void freeifaddrs(struct ifaddrs *);
extern unsigned if_nametoindex(const char *);
extern int getnameinfo(const void *, unsigned, char *, unsigned, char *, unsigned, int);
extern int strcmp(const char *, const char *), puts(const char *), printf(const char *, ...);
extern unsigned long strlen(const char *);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-INTERFACES: failure %d errno %d\n",code,*__error()); return code; } } while (0)
_Static_assert(sizeof(struct ifaddrs) == 56 && __builtin_offsetof(struct ifaddrs,address) == 24 && __builtin_offsetof(struct ifaddrs,data) == 48, "Darwin ifaddrs ABI");
static int snapshot(struct ifaddrs *list) {
    int count=0, loopback=0, links=0;
    for(struct ifaddrs *p=list;p;p=p->next) {
        CHECK(++count < 1024 && p->name && p->name[0],1);
        *__error()=177;
        unsigned index=if_nametoindex(p->name);
        CHECK(index && *__error()==177,2);
        if(!p->address) continue;
        unsigned char *a=p->address;
        if(a[1]==18) {
            CHECK(a[0]>=20 && (unsigned)(a[2] | a[3]<<8)==index,3);
            CHECK(a[5]==strlen(p->name) && 8u+a[5]+a[6]+a[7] <= a[0],4);
            for(unsigned i=0;i<a[5];i++) CHECK(a[8+i]==(unsigned char)p->name[i],5);
            links++;
        } else if(a[1]==2 || a[1]==30) {
            unsigned length=a[1]==2 ? 16 : 28;
            CHECK(a[0]==length && p->netmask && p->netmask[1]==a[1],6);
            char host[128],service[32];
            CHECK(getnameinfo(a,length,host,sizeof host,service,sizeof service,10)==0,7);
            CHECK(!strcmp(service,"0"),8);
            if((p->flags & 8) && a[1]==2) {
                CHECK(p->flags & 1,9);
                CHECK(!strcmp(host,"127.0.0.1"),10);
                CHECK(p->netmask[4]==255 && p->netmask[5]==0 && p->netmask[6]==0 && p->netmask[7]==0,11);
                loopback++;
            }
        }
    }
    CHECK(loopback && links,12);
    return 0;
}
static int check(void) {
    for(int i=0;i<16;i++) {
        struct ifaddrs *first, *second;
        *__error()=177;
        CHECK(getifaddrs(&first)==0 && first && *__error()==177,13);
        CHECK(getifaddrs(&second)==0 && second && second!=first,14);
        freeifaddrs(second);
        int error=snapshot(first); if(error) return error;
        freeifaddrs(first);
        freeifaddrs(0);
    }
    *__error()=177;
    CHECK(if_nametoindex("vinix_missing")==0 && *__error()==6,15);
    return 0;
}
struct job { int result; };
static void *worker(void *argument) { struct job *job=argument;job->result=check();return 0; }
int main(void) {
    int error=check(); if(error) return error;
    unsigned long clients[8]; struct job jobs[8]={0};
    for(int i=0;i<8;i++) CHECK(pthread_create(&clients[i],0,worker,&jobs[i])==0,16);
    int failed=0;
    for(int i=0;i<8;i++) {
        if(pthread_join(clients[i],0)!=0 || jobs[i].result) failed=1;
    }
    CHECK(!failed,17);
    puts("IOS-INTERFACES: real native snapshots, Darwin link addresses, flags, masks, indices and eight-thread ownership");
    return 0;
}
