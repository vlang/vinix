// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long word;
struct attr {word fields[8];};
extern int pthread_attr_init(void *),pthread_attr_destroy(void *),pthread_attr_getdetachstate(const void *,int *),pthread_attr_setdetachstate(void *,int);
extern int pthread_attr_getstacksize(const void *,word *),pthread_attr_setstacksize(void *,word),pthread_attr_getstack(const void *,void **,word *),pthread_attr_setstack(void *,void *,word);
extern int pthread_attr_getguardsize(const void *,word *),pthread_attr_setguardsize(void *,word);
extern int pthread_create(word *,const void *,void *(*)(void *),void *),pthread_join(word,void **),posix_memalign(void **,word,word);
extern word pthread_self(void);
extern int * __error(void),puts(const char *),printf(const char *,...),memcmp(const void *,const void *,word),strcmp(const char *,const char *),pipe(int *),close(int);
extern void free(void *),_exit(int) __attribute__((noreturn));
extern long read(int,void *,word),write(int,const void *,word);
#define CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-ATTR: failure %d errno %d\n",code,*__error());return code;}}while(0)
static _Thread_local int tls;
struct job {word before,id,after;void *base;int result,index;};
static void *worker(void *context){
    struct job *job=context;
    volatile unsigned char frame[262144];
    for(word i=0;i<sizeof frame;i+=4096)frame[i]=(unsigned char)(i/4096+job->index);
    word address=(word)&frame[0];
    if(tls || (job->base && (address<(word)job->base || address+sizeof frame>(word)job->base+1048576)))job->result=1;
    tls=41;
    for(word i=0;i<sizeof frame;i+=4096)if(frame[i]!=(unsigned char)(i/4096+job->index))job->result=2;
    struct attr local;word size=0;*__error()=177;
    if(pthread_attr_init(&local) || pthread_attr_setstacksize(&local,20480) || pthread_attr_getstacksize(&local,&size) || size!=32768 || pthread_attr_destroy(&local) || *__error()!=177)job->result=3;
    return context;
}
static int ready[2],release[2];
static void *detached_worker(void *context){
    (void)context;char byte='x';if(write(ready[1],&byte,1)!=1 || read(release[0],&byte,1)!=1)_exit(91);
    return 0;
}
int main(int argc,char **argv){
    struct {word before;struct attr value;word after;} guarded={0x123456789abcdef0UL,{{0}},0xfedcba9876543210UL};
    struct attr *a=&guarded.value;
    CHECK(pthread_join(pthread_self(),0)==11,28);
    *__error()=177;CHECK(pthread_attr_init(a)==0 && *__error()==177,1);
    const struct attr expected={{0x54484441,0,0,0,0x8ff,0x10010101,0,0}};
    CHECK(!memcmp(a,&expected,64) && guarded.before==0x123456789abcdef0UL && guarded.after==0xfedcba9876543210UL,2);
    struct {unsigned before;int state;unsigned after;} detached={0x12345678,-1,0x87654321};
    word size=0,guard=0;void *base=(void*)1;
    CHECK(pthread_attr_getdetachstate(a,&detached.state)==0 && detached.state==1 && detached.before==0x12345678 && detached.after==0x87654321,3);
    CHECK(pthread_attr_getstacksize(a,&size)==0 && size==524288 && pthread_attr_getguardsize(a,&guard)==0 && guard==16384,4);
    CHECK(pthread_attr_getstack(a,&base,&size)==0 && base==0 && size==524288,5);
    CHECK(pthread_attr_setdetachstate(a,0)==22 && pthread_attr_setdetachstate(a,3)==22 && !memcmp(a,&expected,64),6);
    CHECK(pthread_attr_setdetachstate(a,2)==0 && pthread_attr_getdetachstate(a,&detached.state)==0 && detached.state==2 && pthread_attr_setdetachstate(a,1)==0,7);
    CHECK(pthread_attr_setstacksize(a,0)==22 && pthread_attr_setstacksize(a,16385)==22 && !memcmp(a,&expected,64),8);
    const word sizes[]={4096,8192,12288,16384,20480,32768,524288,1048576};
    for(int i=0;i<8;i++){
        CHECK(pthread_attr_setstacksize(a,sizes[i])==0 && pthread_attr_getstacksize(a,&size)==0 && size==((sizes[i]+16383)&~16383UL),9);
        CHECK(pthread_attr_getstack(a,&base,&size)==0 && (word)base==0-size,10);
    }
    CHECK(pthread_attr_setguardsize(a,1)==22 && pthread_attr_setguardsize(a,4096)==0 && pthread_attr_getguardsize(a,&guard)==0 && guard==16384,11);
    CHECK(pthread_attr_setguardsize(a,0)==0 && pthread_attr_getguardsize(a,&guard)==0 && guard==0,12);
    CHECK(pthread_attr_setguardsize(a,32768)==0 && pthread_attr_getguardsize(a,&guard)==0 && guard==32768,13);
    void *allocation=0;CHECK(posix_memalign(&allocation,16384,1048576)==0,14);
    CHECK(pthread_attr_setstack(a,(char*)allocation+4096,524288)==22 && pthread_attr_setstack(a,allocation,20480)==22,15);
    CHECK(pthread_attr_setstack(a,allocation,1048576)==0 && pthread_attr_getstack(a,&base,&size)==0 && base==allocation && size==1048576,16);
    CHECK(pthread_attr_setstacksize(a,524288)==0 && pthread_attr_getstack(a,&base,&size)==0 && base==(char*)allocation+524288 && size==524288,17);
    struct attr destroyed=*a;CHECK(pthread_attr_destroy(a)==0,18);destroyed.fields[0]=0;
    size=123;detached.state=-1;CHECK(!memcmp(a,&destroyed,64) && pthread_attr_destroy(a)==22 && pthread_attr_getstacksize(a,&size)==22 && size==123 && pthread_attr_getdetachstate(a,&detached.state)==22 && detached.state==-1,19);
    CHECK(*__error()==177,20);free(allocation);
    if(argc>1 && !strcmp(argv[1],"--detached")){
        CHECK(pipe(ready)==0 && pipe(release)==0 && pthread_attr_init(a)==0 && pthread_attr_setdetachstate(a,2)==0,21);
        word id=0;CHECK(pthread_create(&id,a,detached_worker,0)==0 && pthread_attr_destroy(a)==0,22);
        char byte;CHECK(read(ready[0],&byte,1)==1 && pthread_join(id,0)==22,23);
        /* Terminate the process while the detached worker is blocked. This
         * tests native detach behavior without promising live-image unload. */
        static const char message[]="IOS-PTHREAD-ATTR: real detached thread rejects joining\n";
        CHECK(write(1,message,sizeof(message)-1)==sizeof(message)-1,24);_exit(0);
    }
    struct attr source;CHECK(pthread_attr_init(&source)==0 && pthread_attr_setstacksize(&source,1048576)==0,25);
    struct job jobs[8]={0};int started=0,error=0;
    for(int i=0;i<8;i++){
        jobs[i].before=0x123456789abcdef0UL;jobs[i].after=0xfedcba9876543210UL;jobs[i].index=i;
        struct attr copy=source;
        if(i%2 && (posix_memalign(&jobs[i].base,16384,1048576) || pthread_attr_setstack(&copy,jobs[i].base,1048576)))break;
        *__error()=177;
        if(pthread_create(&jobs[i].id,&copy,worker,&jobs[i]))break;
        started++;
        if(*__error()!=177)error=1;
        if(pthread_attr_destroy(&copy))error=1;
    }
    for(int i=0;i<started;i++){
        void *result=0;if(pthread_join(jobs[i].id,&result) || result!=&jobs[i] || jobs[i].result || jobs[i].before!=0x123456789abcdef0UL || jobs[i].after!=0xfedcba9876543210UL)error=1;
    }
    for(int i=0;i<8;i++)free(jobs[i].base);
    CHECK(started==8 && !error && pthread_attr_destroy(&source)==0,26);
    CHECK(guarded.before==0x123456789abcdef0UL && guarded.after==0xfedcba9876543210UL,27);
    puts("IOS-PTHREAD-ATTR: guarded layouts, copied attributes, rounded sizes, real user stacks, 256 KiB frames, errno and eight threads");return 0;
}
