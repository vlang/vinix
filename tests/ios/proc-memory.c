// SPDX-License-Identifier: GPL-2.0-or-later
extern unsigned long os_proc_available_memory(void);
extern int *__error(void), printf(const char *, ...), puts(const char *), strcmp(const char *, const char *);
extern int open(const char *, int, ...), close(int);
extern long read(int, void *, unsigned long), write(int, const void *, unsigned long);
extern unsigned long strlen(const char *);
extern void *mmap(void *, unsigned long, int, int, int, long);
extern int munmap(void *, unsigned long);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-PROC-MEMORY: failure %d errno %d\n",code,*__error()); return code; } } while (0)
#define MIB (1024UL*1024)
static unsigned long query(void) {
    *__error()=177;
    unsigned long result=os_proc_available_memory();
    if (*__error()!=177) return ~0UL;
    return result;
}
static int set_limit(const char *group,const char *value) {
    char path[4096]; unsigned long n=strlen(group), v=strlen(value);
    if(n+12>=sizeof(path)) return -1;
    for(unsigned long i=0;i<n;i++)path[i]=group[i];
    const char *tail="/memory.max";
    for(unsigned long i=0;i<=strlen(tail);i++)path[n+i]=tail[i];
    int fd=open(path,1);if(fd<0)return -1;
    long result=write(fd,value,v);int cleanup=close(fd);
    return result==(long)v && !cleanup ? 0 : -1;
}
struct job { int result; };
static void *worker(void *argument) {
    struct job *job=argument;
    for(int i=0;i<16;i++)if(query()!=0){job->result=1;break;}
    return 0;
}
int main(int argc,char **argv) {
    int limited=argc>1 && !strcmp(argv[1],"limited");
    unsigned long before=query();
    CHECK(limited ? before>128*MIB && before<512*MIB : before==0,1);
    unsigned long size=8*MIB;
    volatile unsigned char *bytes=mmap(0,size,3,0x1002,-1,0);
    CHECK((void *)bytes!=(void *)-1,2);
    for(unsigned long i=0;i<size;i+=4096)bytes[i]=0x5a;
    unsigned long touched=query();
    CHECK(limited ? before>touched && before-touched>=size && before-touched<=size+128*1024 : touched==0,3);
    CHECK(munmap((void *)bytes,size)==0,4);
    unsigned long released=query();
    CHECK(limited ? released>=touched+size && released<=before+128*1024 : released==0,5);
    if(limited) {
        CHECK(argc==4,6);
        /* Parent starts at 512 MiB, child at 768 MiB: the parent binds first.
           Alter real kernel limits while this very process stays alive. */
        CHECK(set_limit(argv[2],"268435456")==0,7);
        unsigned long child=query();
        CHECK(released>child && released-child>=256*MIB-128*1024 && released-child<=256*MIB+128*1024,8);
        CHECK(set_limit(argv[3],"134217728")==0,9);
        unsigned long parent=query();
        CHECK(child>parent && child-parent>=128*MIB-128*1024 && child-parent<=128*MIB+128*1024,10);
        CHECK(set_limit(argv[2],"max")==0 && set_limit(argv[3],"max")==0,11);
        CHECK(query()==0,12);
    }
    unsigned long clients[8];struct job jobs[8]={0};int started=0,failed=0;
    for(int i=0;i<8;i++){if(pthread_create(&clients[i],0,worker,&jobs[i]))break;started++;}
    for(int i=0;i<started;i++)if(pthread_join(clients[i],0) || jobs[i].result)failed=1;
    CHECK(started==8 && !failed,13);
    puts(limited ? "IOS-PROC-MEMORY: real nested budgets, touched pages, released mappings, live limit changes and eight threads" :
        "IOS-PROC-MEMORY: unmanaged budget, touched pages, released mappings, errno and eight threads");
    return 0;
}
