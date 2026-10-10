// SPDX-License-Identifier: GPL-2.0-or-later
struct passwd {
    char *name, *password; unsigned uid, gid; long change;
    char *class, *gecos, *directory, *shell; long expire;
};
extern struct passwd *getpwuid(unsigned);
extern unsigned getuid(void), getgid(void);
extern int getpid(void), initgroups(const char *, int), getgroups(int, unsigned *), setgroups(int, const unsigned *), setgid(unsigned), setuid(unsigned);
extern int kill(int, int), *__error(void), strcmp(const char *, const char *), printf(const char *, ...), puts(const char *), fflush(void *);
extern void *malloc(unsigned long), *calloc(unsigned long, unsigned long), *realloc(void *, unsigned long);
extern void free(void *);
extern unsigned long malloc_size(const void *);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-PROCESS: failure %d errno %d\n",code,*__error()); return code; } } while (0)
static int allocations(void) {
    *__error()=177; CHECK(malloc_size(0)==0 && *__error()==177,1);
    unsigned long sizes[]={0,1,15,16,17,100,4096,8193};
    for(int i=0;i<8;i++) {
        unsigned char *p=malloc(sizes[i]); CHECK(p,2);
        *__error()=177; unsigned long capacity=malloc_size(p);
        CHECK(capacity>=sizes[i] && *__error()==177,3);
        /* Every reported byte is usable storage, independent of allocator
           rounding differences. Both calloc and realloc use that backend. */
        for(unsigned long j=0;j<capacity;j++) p[j]=(unsigned char)j;
        unsigned char *q=realloc(p,sizes[i]+100); CHECK(q,4);
        unsigned long preserved=sizes[i]<capacity ? sizes[i] : capacity;
        for(unsigned long j=0;j<preserved;j++) CHECK(q[j]==(unsigned char)j,5);
        CHECK(malloc_size(q)>=sizes[i]+100,6); free(q);
        q=calloc(1,sizes[i]+1); CHECK(q && malloc_size(q)>=sizes[i]+1,7);
        for(unsigned long j=0;j<sizes[i]+1;j++) CHECK(!q[j],8);
        free(q);
    }
    return 0;
}
struct job { int result; };
static void *worker(void *argument) { struct job *job=argument;for(int i=0;i<16;i++){job->result=allocations();if(job->result) break;}return 0; }
static int credentials(int database_fixture) {
    unsigned before[1024],after[1024];
    int count=getgroups(1024,before); CHECK(count>=0,9);
    *__error()=177; CHECK(getgroups(0,0)==count && *__error()==177,10);
    CHECK(getgroups(-1,0)==-1 && *__error()==22,11);
    CHECK(setgid(getgid())==0 && setuid(getuid())==0,12);
    if(database_fixture) {
        CHECK(getuid()==0,13);
        CHECK(kill(getpid(),7)==-1 && *__error()==45,36);
        CHECK(kill(getpid(),29)==-1 && *__error()==45,37);
        *__error()=177; CHECK(initgroups("ios-fixture",37)==0 && *__error()==177,14);
        int changed=getgroups(1024,after); CHECK(changed==3,15);
        int base=0,first=0,second=0;
        for(int i=0;i<changed;i++){base+=after[i]==37;first+=after[i]==8;second+=after[i]==11;}
        CHECK(base==1 && first==1 && second==1,16);
        CHECK(setgroups(count,before)==0,17);
        CHECK(getgroups(1024,after)==count,18);
        for(int i=0;i<count;i++) CHECK(after[i]==before[i],19);
        CHECK(setgid(37)==0 && setuid(1001)==0 && getgid()==37 && getuid()==1001,20);
    } else {
        CHECK(getuid()!=0,21);
    }
    struct passwd *p=getpwuid(getuid()); CHECK(p,22);
    count=getgroups(1024,before); CHECK(count>=0,23);
    CHECK(initgroups(p->name,(int)p->gid)==-1 && *__error()==1,24);
    CHECK(initgroups("vinix_missing_user",37)==-1 && *__error()==1,25);
    CHECK(setgroups(0,0)==-1 && *__error()==1,26);
    CHECK(getgroups(1024,after)==count,27);
    for(int i=0;i<count;i++) CHECK(after[i]==before[i],28);
    CHECK(setuid(0)==-1 && *__error()==1,29);
    return 0;
}
int main(int argc,char **argv) {
    if(argc>1 && !strcmp(argv[1],"usr1")) { puts("IOS-PROCESS: delivering Darwin SIGUSR1");fflush(0);kill(getpid(),30);return 90; }
    if(argc>1 && !strcmp(argv[1],"usr2")) { puts("IOS-PROCESS: delivering Darwin SIGUSR2");fflush(0);kill(getpid(),31);return 91; }
    if(argc>1 && !strcmp(argv[1],"bus")) { puts("IOS-PROCESS: delivering Darwin SIGBUS");fflush(0);kill(getpid(),10);return 92; }
    *__error()=177; CHECK(kill(getpid(),0)==0 && *__error()==177,30);
    CHECK(kill(2147483647,0)==-1 && *__error()==3,31);
    CHECK(kill(getpid(),32)==-1 && *__error()==22,32);
    CHECK(kill(getpid(),-1)==-1 && *__error()==22,33);
    int error=allocations(); if(error) return error;
    unsigned long clients[8];struct job jobs[8]={0};
    int started=0,failed=0;
    for(int i=0;i<8;i++){if(pthread_create(&clients[i],0,worker,&jobs[i])!=0)break;started++;}
    for(int i=0;i<started;i++) if(pthread_join(clients[i],0)!=0 || jobs[i].result) failed=1;
    CHECK(started==8,34);
    CHECK(!failed,35);
    error=credentials(argc>1 && !strcmp(argv[1],"--database-fixture"));if(error) return error;
    puts("IOS-PROCESS: real groups, permission failures, signal queries and eight-thread allocation capacities");
    return 0;
}
