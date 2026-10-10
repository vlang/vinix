// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long word;
struct parameters {int priority;unsigned opaque;};
struct mutex {word words[8];};
struct condition {word words[6];};
extern word pthread_self(void);
extern int pthread_getschedparam(word,int *,struct parameters *),pthread_setschedparam(word,int,const struct parameters *);
extern int sched_get_priority_min(int),sched_get_priority_max(int),sched_yield(void);
extern int pthread_create(word *,const void *,void *(*)(void *),void *),pthread_join(word,void **);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_lock(void *),pthread_mutex_unlock(void *),pthread_mutex_destroy(void *);
extern int pthread_cond_init(void *,const void *),pthread_cond_wait(void *,void *),pthread_cond_broadcast(void *),pthread_cond_destroy(void *);
extern int *__error(void),puts(const char *),printf(const char *,...),fflush(void *),strcmp(const char *,const char *),memcmp(const void *,const void *,word),setuid(unsigned);
extern int open(const char *,int,...),close(int);
extern long read(int,void *,word);
extern void _exit(int) __attribute__((noreturn));
#define CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-SCHED: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define WORK_CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-SCHED: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(91);}}while(0)
/* Inspect the kernel's main-thread record independently of the adapter's
 * getters. This kernel also reports those fields through thread-self/stat,
 * so call this only on the main thread. No Linux scheduling symbols are imported. */
static int native_state(int policy,int priority){
    char buffer[4096];int fd=open("/proc/thread-self/stat",0);CHECK(fd>=0,70);
    long size=read(fd,buffer,sizeof buffer-1);int cleanup=close(fd);CHECK(size>0 && size<(long)sizeof buffer && !cleanup,71);buffer[size]=0;
    char *start=0;for(char *p=buffer;*p;p++)if(*p==')')start=p+1;
    CHECK(start,72);int actual_policy=-1,actual_priority=-1;
    for(int field=3;field<=41;field++){
        while(*start==' ' || *start=='\n')start++;char *end=start;while(*end && *end!=' ' && *end!='\n')end++;
        CHECK(end!=start,73);
        if(field==40 || field==41){int value=0;for(char *p=start;p<end;p++){CHECK(*p>='0' && *p<='9' && value<1000000,74);value=value*10+*p-'0';}if(field==40)actual_priority=value;else actual_policy=value;}
        start=end;
    }
    CHECK(actual_policy==policy && actual_priority==priority,75);return 0;
}
static int query_state(word thread,int expected_policy,int expected_priority){
    struct {unsigned before;int policy;unsigned after;} p={0x12345678,-17,0x87654321};
    struct {unsigned before;struct parameters value;unsigned after;} s={0x12345678,{-17,0xa5a5a5a5},0x87654321};
    *__error()=177;
    CHECK(pthread_getschedparam(thread,&p.policy,&s.value)==0 && p.policy==expected_policy && s.value.priority==expected_priority && s.value.opaque==10 && *__error()==177,10);
    CHECK(p.before==0x12345678 && p.after==0x87654321 && s.before==0x12345678 && s.after==0x87654321,11);
    p.policy=-17;s.value.priority=-17;s.value.opaque=0xa5a5a5a5;
    CHECK(pthread_getschedparam(thread,&p.policy,0)==0 && p.policy==expected_policy && s.value.priority==-17 && s.value.opaque==0xa5a5a5a5,12);
    p.policy=-17;
    CHECK(pthread_getschedparam(thread,0,&s.value)==0 && p.policy==-17 && s.value.priority==expected_priority && s.value.opaque==10,13);
    CHECK(pthread_getschedparam(thread,0,0)==0 && *__error()==177,14);return 0;
}
static int change(word thread,int policy,int priority){
    struct parameters request={priority,10},copy=request;*__error()=177;
    CHECK(pthread_setschedparam(thread,policy,&request)==0 && !memcmp(&request,&copy,8) && *__error()==177,20);
    CHECK(query_state(thread,policy,priority)==0,21);return 0;
}
struct state {struct mutex mutex;struct condition gate;int ready,go,adapter;};
struct job {struct state *state;word id;int policy,priority;};
static _Thread_local int tls;
static void *worker(void *context){
    struct job *job=context;struct state *state=job->state;WORK_CHECK(!tls,30);tls=41;
    WORK_CHECK(pthread_mutex_lock(&state->mutex)==0,31);state->ready++;
    WORK_CHECK(pthread_cond_broadcast(&state->gate)==0,32);
    while(!state->go)WORK_CHECK(pthread_cond_wait(&state->gate,&state->mutex)==0,33);
    WORK_CHECK(pthread_mutex_unlock(&state->mutex)==0,34);
    word self=pthread_self();WORK_CHECK(self==job->id && query_state(self,job->policy,job->priority)==0,35);
    const int policies[]={4,2,1};
    for(int p=0;p<3;p++)for(int n=0;n<(p==2?1:3);n++){
        int priority=p==2?31:15+16*n;
        WORK_CHECK(change(self,policies[p],priority)==0,37);
        *__error()=177;WORK_CHECK(sched_yield()==0 && *__error()==177,39);
    }
    WORK_CHECK(tls==41,40);return job;
}
static int roundtrip(int adapter){
    struct state shared={0};struct job jobs[8]={0};shared.adapter=adapter;
    CHECK(pthread_mutex_init(&shared.mutex,0)==0 && pthread_cond_init(&shared.gate,0)==0,41);
    int started=0,error=0;
    for(int i=0;i<8;i++){jobs[i].state=&shared;jobs[i].policy=i&1?2:4;jobs[i].priority=15+i*4;if(pthread_create(&jobs[i].id,0,worker,&jobs[i]))break;started++;}
    WORK_CHECK(pthread_mutex_lock(&shared.mutex)==0,42);
    while(shared.ready!=started)WORK_CHECK(pthread_cond_wait(&shared.gate,&shared.mutex)==0,43);
    for(int i=0;i<started;i++)WORK_CHECK(change(jobs[i].id,jobs[i].policy,jobs[i].priority)==0,44);
    shared.go=1;WORK_CHECK(pthread_cond_broadcast(&shared.gate)==0 && pthread_mutex_unlock(&shared.mutex)==0,45);
    for(int i=0;i<started;i++){void *result=0;WORK_CHECK(pthread_join(jobs[i].id,&result)==0,46);if(result!=&jobs[i])error=1;}
    CHECK(pthread_cond_destroy(&shared.gate)==0 && pthread_mutex_destroy(&shared.mutex)==0 && started==8 && !error,47);
    CHECK(query_state(pthread_self(),1,31)==0,48);return 0;
}
int main(int argc,char **argv){
    int adapter=argc>1 && !strcmp(argv[1],"--adapter");
    if(argc>2 && !strcmp(argv[2],"--unsupported-native")){
        int policy=-17;struct parameters output={-17,0xa5a5a5a5};*__error()=177;
        CHECK(pthread_getschedparam(pthread_self(),&policy,&output)==45 && policy==-17 && output.priority==-17 && output.opaque==0xa5a5a5a5 && *__error()==177,50);
        CHECK(native_state(3,0)==0 && change(pthread_self(),1,31)==0 && native_state(0,0)==0,51);
        puts("IOS-PTHREAD-SCHED: unsupported inherited native policy preserves outputs and restores ordinary scheduling");return 0;
    }
    CHECK(query_state(pthread_self(),1,31)==0,52);
    if(argc>2 && !strcmp(argv[2],"--unprivileged")){
        CHECK(setuid(1001)==0,53);struct parameters request={15,10};*__error()=177;
        CHECK(pthread_setschedparam(pthread_self(),4,&request)==1 && *__error()==177 && query_state(pthread_self(),1,31)==0 && native_state(0,0)==0,54);
        puts("IOS-PTHREAD-SCHED: native privilege denial preserves ordinary policy and errno");return 0;
    }
    for(int policy=-1;policy<7;policy++){*__error()=177;CHECK(sched_get_priority_min(policy)==15 && sched_get_priority_max(policy)==47 && *__error()==177,55);}
    int policy=-17;struct parameters output={-17,0xa5a5a5a5};*__error()=177;
    CHECK(pthread_getschedparam(0,&policy,&output)==3 && policy==-17 && output.priority==-17 && output.opaque==0xa5a5a5a5 && *__error()==177,56);
    struct parameters request={31,10};
    CHECK(pthread_setschedparam(0,1,&request)==3 && *__error()==177,57);
    CHECK(pthread_setschedparam(pthread_self(),3,&request)==22 && *__error()==177,58);
    request.priority=-1;CHECK(pthread_setschedparam(pthread_self(),1,&request)==22 && query_state(pthread_self(),1,31)==0,59);
    request.priority=30;CHECK(pthread_setschedparam(pthread_self(),1,&request)==(adapter?45:0),60);
    CHECK(query_state(pthread_self(),1,adapter?31:30)==0 && change(pthread_self(),1,31)==0,61);
    request.priority=31;request.opaque=0x5a5a5a5a;
    CHECK(pthread_setschedparam(pthread_self(),1,&request)==(adapter?45:0),62);
    CHECK(pthread_getschedparam(pthread_self(),&policy,&output)==0 && policy==1 && output.priority==31 && output.opaque==(adapter?10:0x5a5a5a5aU),63);
    CHECK(change(pthread_self(),1,31)==0,64);
    if(adapter){request.opaque=10;request.priority=0;CHECK(pthread_setschedparam(pthread_self(),4,&request)==45,65);request.priority=100;CHECK(pthread_setschedparam(pthread_self(),2,&request)==45 && query_state(pthread_self(),1,31)==0,66);}
    if(adapter){
        const int policies[]={4,2,1};
        for(int p=0;p<3;p++)for(int n=0;n<(p==2?1:3);n++){
            int priority=p==2?31:15+16*n;
            CHECK(change(pthread_self(),policies[p],priority)==0 && native_state(p==0?1:p==1?2:0,p==2?0:priority)==0,68);
            *__error()=177;CHECK(sched_yield()==0 && *__error()==177,69);
        }
    }
    for(int i=0;i<8;i++)CHECK(roundtrip(adapter)==0,67);
    puts("IOS-PTHREAD-SCHED: guarded Darwin parameters, copied inputs, optional outputs, native FIFO/RR changes, yielding and eight threads");return 0;
}
