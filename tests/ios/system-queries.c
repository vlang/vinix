// SPDX-License-Identifier: GPL-2.0-or-later
struct passwd {
    char *name, *password;
    unsigned uid, gid;
    long change;
    char *class, *gecos, *directory, *shell;
    long expire;
};
struct protoent { char *name; char **aliases; int number; };
struct usage_time { long seconds; int microseconds, padding; };
struct rusage { struct usage_time user, system; long counters[14]; };
extern int getdtablesize(void), gethostname(char *, unsigned long), getrusage(int, struct rusage *), *__error(void);
extern unsigned getuid(void), getgid(void), getegid(void);
extern struct passwd *getpwuid(unsigned);
extern struct protoent *getprotobyname(const char *);
extern const unsigned char in6addr_loopback[16];
extern int puts(const char *), printf(const char *, ...), strcmp(const char *, const char *);
extern unsigned long strlen(const char *);
extern void *malloc(unsigned long), *memset(void *, int, unsigned long);
extern void free(void *);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
extern int pthread_mutex_lock(void *), pthread_mutex_unlock(void *), pthread_cond_wait(void *, void *), pthread_cond_broadcast(void *);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-SYSTEM-QUERIES: failure %d errno %d\n",code,*__error()); return code; } } while (0)
_Static_assert(sizeof(struct passwd)==72 && __builtin_offsetof(struct passwd,directory)==48 && __builtin_offsetof(struct passwd,expire)==64,"Darwin passwd ABI");
_Static_assert(sizeof(struct protoent)==24 && __builtin_offsetof(struct protoent,number)==16,"Darwin protocol ABI");
_Static_assert(sizeof(struct rusage)==144 && __builtin_offsetof(struct rusage,counters)==32,"Darwin resource usage ABI");
static unsigned long lock[8]={0x32aaaba7}, condition[6]={0x3cb0b1bb};
static unsigned arrived, generation;
static int rendezvous(void) {
    CHECK(pthread_mutex_lock(lock)==0,1);
    unsigned previous=generation;
    if(++arrived==8) { arrived=0;generation++;pthread_cond_broadcast(condition); }
    else while(previous==generation) CHECK(pthread_cond_wait(condition,lock)==0,2);
    CHECK(pthread_mutex_unlock(lock)==0,3);
    return 0;
}
static int hostname(void) {
    char full[256]; *__error()=177;
    CHECK(gethostname(full,sizeof full)==0 && *__error()==177,4);
    unsigned long length=strlen(full);
    CHECK(length>0 && length<sizeof full,5);
    unsigned long sizes[]={0,1,length,length+1,sizeof full};
    for(int i=0;i<5;i++) {
        unsigned char buffer[258]; memset(buffer,0xa5,sizeof buffer); *__error()=177;
        CHECK(gethostname((char *)buffer+1,sizes[i])==0 && *__error()==177,6);
        /* Native macOS writes destination[-1] for capacity zero. The V
           adapter deliberately leaves a zero-capacity buffer untouched. */
#ifdef IOS_SYSTEM_QUERIES_REFERENCE
        CHECK(buffer[0]==(sizes[i] ? 0xa5 : 0) && buffer[sizes[i]+1]==0xa5,7);
#else
        CHECK(buffer[0]==0xa5 && buffer[sizes[i]+1]==0xa5,7);
#endif
        if(!sizes[i]) continue;
        unsigned long copied=length<sizes[i] ? length : sizes[i]-1;
        for(unsigned long j=0;j<copied;j++) CHECK(buffer[j+1]==(unsigned char)full[j],8);
        CHECK(buffer[copied+1]==0,9);
    }
    return 0;
}
static int resources(void) {
    struct { unsigned long before; struct rusage usage; unsigned long after; } guard;
    memset(&guard,0xa5,sizeof guard); *__error()=177;
    CHECK(getrusage(0,&guard.usage)==0 && *__error()==177,10);
    CHECK(guard.before==0xa5a5a5a5a5a5a5a5UL && guard.after==guard.before,11);
    CHECK(guard.usage.user.seconds>=0 && guard.usage.user.microseconds>=0 && guard.usage.user.microseconds<1000000,12);
    CHECK(guard.usage.system.seconds>=0 && guard.usage.system.microseconds>=0 && guard.usage.system.microseconds<1000000,13);
    CHECK(guard.usage.counters[0]>0,14);
    CHECK(getrusage(-1,&guard.usage)==0,15);
    memset(&guard.usage,0xa5,sizeof guard.usage);
    CHECK(getrusage(1,&guard.usage)==-1 && *__error()==22,16);
    for(unsigned long i=0;i<sizeof guard.usage;i++) CHECK(((unsigned char *)&guard.usage)[i]==0xa5,17);
    CHECK(getrusage(0,0)==-1 && *__error()==14,18);
    return 0;
}
struct job { unsigned uid; int protocol, result; };
static int worker_check(struct job *job) {
    int failure=0;
    for(int iteration=0;iteration<32;iteration++) {
        *__error()=177;
        struct passwd *p=getpwuid(job->uid);
        struct protoent *protocol=getprotobyname(job->protocol==6 ? "TCP" : "udp");
        int query_errno=*__error();
        /* Every worker completes both barriers and all iterations, including
           after a failed query, so peers can finish and main can join them. */
        int barrier_error=rendezvous();
        if(barrier_error) failure=19;
        if(!(p && p->uid==job->uid && p->name && p->name[0] && p->password && p->class && p->gecos && p->directory && p->shell)) failure=20;
        if(!(protocol && protocol->number==job->protocol && protocol->name && protocol->aliases && protocol->aliases[0] && query_errno==177)) failure=21;
        else {
            if(strcmp(protocol->name,job->protocol==6 ? "tcp" : "udp")) failure=22;
            if(strcmp(protocol->aliases[0],job->protocol==6 ? "TCP" : "UDP")) failure=23;
        }
        barrier_error=rendezvous();
        if(barrier_error) failure=24;
    }
    CHECK(!failure,failure);
    return 0;
}
static void *worker(void *argument) { struct job *job=argument;job->result=worker_check(job);return 0; }
int main(int argc, char **argv) {
    *__error()=177;
    CHECK(getdtablesize()>0 && *__error()==177,25);
    unsigned gid=getgid(), egid=getegid();
    CHECK(gid==egid && *__error()==177,26);
    for(int i=0;i<16;i++) CHECK(in6addr_loopback[i]==(i==15 ? 1 : 0),27);
    int error=hostname(); if(error) return error;
    error=resources(); if(error) return error;
    struct passwd *p=getpwuid(getuid());
    CHECK(p && p->uid==getuid() && p->gid==gid,28);
    *__error()=177;
    CHECK(!getpwuid(0xffffffffu) && *__error()==177,29);
    CHECK(!getprotobyname("vinix-missing-protocol") && *__error()==177,30);
    int database_fixture=argc>1 && !strcmp(argv[1],"--database-fixture");
    if(database_fixture) {
        p=getpwuid(1001);
        CHECK(p && p->uid==1001 && p->gid==37 && !strcmp(p->name,"ios-fixture"),35);
        CHECK(p->change==0 && p->expire==0 && !p->class[0],36);
        CHECK(!strcmp(p->directory,"/var/empty") && !strcmp(p->shell,"/bin/false"),37);
        CHECK(strlen(p->gecos)==8192,38);
        for(int i=0;i<8192;i++) CHECK(p->gecos[i]=='G',39);
    }
    /* Touch enough memory to distinguish native KiB from Darwin bytes. */
    unsigned long size=32UL*1024*1024;
    volatile unsigned char *memory=malloc(size); CHECK(memory,31);
    for(unsigned long i=0;i<size;i+=4096) memory[i]=1;
    struct rusage usage;
    int result=getrusage(0,&usage);
    free((void *)memory);
    CHECK(result==0 && usage.counters[0]>=(long)size,32);
    unsigned long clients[8]; struct job jobs[8]={0};
    for(int i=0;i<8;i++) {
        jobs[i].uid=i%2 ? (database_fixture ? 1001 : 0) : getuid(); jobs[i].protocol=i%2 ? 6 : 17;
        CHECK(pthread_create(&clients[i],0,worker,&jobs[i])==0,33);
    }
    int failed=0;
    for(int i=0;i<8;i++) { if(pthread_join(clients[i],0)!=0 || jobs[i].result) failed=1; }
    CHECK(!failed,34);
    puts("IOS-SYSTEM-QUERIES: native limits, credentials, hostname, account/protocol ownership and Darwin resource usage");
    return 0;
}
