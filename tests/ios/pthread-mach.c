// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long word;
struct mutex {word words[8];};
struct condition {word words[6];};
struct parameters {int priority;unsigned opaque;};
extern unsigned mach_task_self_;
extern word pthread_self(void),pthread_from_mach_thread_np(unsigned);
extern unsigned pthread_mach_thread_np(word),mach_thread_self(void);
extern int mach_port_type(unsigned,unsigned,unsigned *),mach_port_get_refs(unsigned,unsigned,int,unsigned *),mach_port_mod_refs(unsigned,unsigned,int,int),mach_port_deallocate(unsigned,unsigned);
extern int pthread_create(word *,const void *,void *(*)(void *),void *),pthread_join(word,void **);
extern int pthread_attr_init(void *),pthread_attr_setdetachstate(void *,int),pthread_attr_setstacksize(void *,word),pthread_attr_destroy(void *);
extern void pthread_exit(void *) __attribute__((noreturn));
extern int pthread_key_create(word *,void (*)(void *)),pthread_key_delete(word),pthread_setspecific(word,const void *);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_lock(void *),pthread_mutex_unlock(void *),pthread_mutex_destroy(void *);
extern int pthread_cond_init(void *,const void *),pthread_cond_wait(void *,void *),pthread_cond_broadcast(void *),pthread_cond_destroy(void *);
extern int pthread_getschedparam(word,int *,struct parameters *),pthread_setschedparam(word,int,const struct parameters *);
extern int *__error(void),puts(const char *),printf(const char *,...),fflush(void *),strcmp(const char *,const char *),fork(void),waitpid(int,int *,int),usleep(unsigned);
extern void _exit(int) __attribute__((noreturn));
#define CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-MACH: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define WORK_CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-MACH: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(91);}}while(0)
static int refs(unsigned port,unsigned expected){
    struct {unsigned before,value,after;} output={0x12345678,0xa5a5a5a5,0x87654321};
    *__error()=177;
    int result=mach_port_get_refs(mach_task_self_,port,0,&output.value);
    if(result || output.value!=expected)printf("IOS-PTHREAD-MACH: port %u references %u expected %u result %d\n",port,output.value,expected,result);
    CHECK(result==0 && output.value==expected && *__error()==177,1);
    CHECK(output.before==0x12345678 && output.after==0x87654321,2);
    output.value=0xa5a5a5a5;
    CHECK(mach_port_type(mach_task_self_,port,&output.value)==0 && output.value==0x10000 && output.before==0x12345678 && output.after==0x87654321 && *__error()==177,3);
    for(int right=1;right<6;right++)CHECK(mach_port_get_refs(mach_task_self_,port,right,&output.value)==0 && output.value==0 && *__error()==177,4);
    return 0;
}
static int dead_refs(unsigned port,unsigned expected){
    struct {unsigned before,value,after;} output={0x12345678,0xa5a5a5a5,0x87654321};
    unsigned type=0;
    /* Native pthread_join can return before the Mach kernel finishes its
     * asynchronous port destruction. Wait for the actual dead-name state. */
    for(int i=0;i<1000;i++){
        CHECK(mach_port_type(mach_task_self_,port,&type)==0,50);
        if(type==0x100000)break;
        CHECK(type==0x10000 && usleep(1000)==0,51);
    }
    *__error()=177;
    CHECK(type==0x100000 && mach_port_get_refs(mach_task_self_,port,4,&output.value)==0 && output.value==expected && *__error()==177,52);
    CHECK(output.before==0x12345678 && output.after==0x87654321,53);
    CHECK(mach_port_get_refs(mach_task_self_,port,0,&output.value)==0 && output.value==0 && *__error()==177,54);return 0;
}
struct state {struct mutex mutex;struct condition gate;word key,main;unsigned main_port;int ready,go,fork_worker;};
struct job {struct state *state;word handle;unsigned port,base;int index,visits;};
static void cleanup(void *context){
    struct job *job=context;
    *__error()=177;
    WORK_CHECK(pthread_mach_thread_np(pthread_self())==job->port && pthread_from_mach_thread_np(job->port)==pthread_self() && *__error()==177,5);
    WORK_CHECK(pthread_mutex_lock(&job->state->mutex)==0,55);
    job->visits++;
    int visits=job->visits;
    WORK_CHECK(pthread_mutex_unlock(&job->state->mutex)==0,56);
    if(visits<3)WORK_CHECK(pthread_setspecific(job->state->key,job)==0,6);
}
static void *worker(void *context){
    struct job *job=context;struct state *state=job->state;
    WORK_CHECK(pthread_mutex_lock(&state->mutex)==0,7);
    job->port=pthread_mach_thread_np(pthread_self());
    WORK_CHECK(job->port && mach_port_get_refs(mach_task_self_,job->port,0,&job->base)==0,8);
    for(int i=0;i<32;i++)WORK_CHECK(pthread_mach_thread_np(pthread_self())==job->port && pthread_from_mach_thread_np(job->port)==pthread_self() && refs(job->port,job->base)==0,9);
    if(job->index!=7)WORK_CHECK(mach_thread_self()==job->port && mach_thread_self()==job->port && refs(job->port,job->base+2)==0,10);
    state->ready++;WORK_CHECK(pthread_cond_broadcast(&state->gate)==0,11);
    while(!state->go)WORK_CHECK(pthread_cond_wait(&state->gate,&state->mutex)==0,12);
    WORK_CHECK(pthread_mutex_unlock(&state->mutex)==0,13);
    int policy=-1;struct parameters parameters={-1,0};
    WORK_CHECK(pthread_getschedparam(pthread_self(),&policy,&parameters)==0 && policy==4 && parameters.priority==15,14);
    parameters.priority=31;parameters.opaque=10;WORK_CHECK(pthread_setschedparam(pthread_self(),1,&parameters)==0,15);
    WORK_CHECK(pthread_setspecific(state->key,job)==0,16);
    if(state->fork_worker && !job->index){
        int child=fork();
        if(!child){unsigned own=pthread_mach_thread_np(pthread_self());_exit(own && pthread_from_mach_thread_np(own)==pthread_self() && pthread_from_mach_thread_np(state->main_port)!=state->main?0:92);}
        WORK_CHECK(child>0,17);int status=-1;WORK_CHECK(waitpid(child,&status,0)==child && status==0,18);
    }
    if(job->index&1)pthread_exit(job);
    return job;
}
static int roundtrip(int fork_worker,int detached){
    struct state state={0};struct job jobs[8]={0};state.main=pthread_self();state.main_port=pthread_mach_thread_np(state.main);state.fork_worker=fork_worker;
    CHECK(pthread_mutex_init(&state.mutex,0)==0 && pthread_cond_init(&state.gate,0)==0 && pthread_key_create(&state.key,cleanup)==0,20);
    word attributes[8];CHECK(pthread_attr_init(attributes)==0 && pthread_attr_setdetachstate(attributes,detached?2:1)==0,57);
    int started=0;
    for(int i=0;i<8;i++){jobs[i].state=&state;jobs[i].index=i;if(pthread_create(&jobs[i].handle,attributes,worker,&jobs[i]))break;started++;}
    CHECK(pthread_attr_destroy(attributes)==0,58);
    WORK_CHECK(pthread_mutex_lock(&state.mutex)==0,21);
    while(state.ready!=started)WORK_CHECK(pthread_cond_wait(&state.gate,&state.mutex)==0,22);
    for(int i=0;i<started;i++){
        unsigned p=pthread_mach_thread_np(jobs[i].handle);WORK_CHECK(p==jobs[i].port && p!=state.main_port && pthread_from_mach_thread_np(p)==jobs[i].handle,23);
        for(int j=0;j<i;j++)WORK_CHECK(p!=jobs[j].port,24);
        struct parameters request={15,10};WORK_CHECK(pthread_setschedparam(pthread_from_mach_thread_np(p),4,&request)==0,25);
    }
    state.go=1;WORK_CHECK(pthread_cond_broadcast(&state.gate)==0 && pthread_mutex_unlock(&state.mutex)==0,26);
    for(int i=0;i<started;i++){
        if(!detached){void *result=0;WORK_CHECK(pthread_join(jobs[i].handle,&result)==0 && result==&jobs[i],27);}
        unsigned p=jobs[i].port,type=0xa5a5a5a5;*__error()=177;
        if(i!=7){
            WORK_CHECK(dead_refs(p,2)==0 && mach_port_mod_refs(mach_task_self_,p,4,-100)==18 && dead_refs(p,2)==0,29);
            WORK_CHECK(mach_port_mod_refs(mach_task_self_,p,4,3)==0 && dead_refs(p,5)==0 && mach_port_mod_refs(mach_task_self_,p,4,-3)==0 && dead_refs(p,2)==0,30);
            if(i==6){
                WORK_CHECK(mach_port_mod_refs(mach_task_self_,p,4,65535)==0 && dead_refs(p,65535)==0,63);
                WORK_CHECK(mach_port_deallocate(mach_task_self_,p)==0 && dead_refs(p,65535)==0 && mach_port_mod_refs(mach_task_self_,p,4,-65535)==0,64);
            } else WORK_CHECK(mach_port_deallocate(mach_task_self_,p)==0 && dead_refs(p,1)==0 && mach_port_deallocate(mach_task_self_,p)==0,31);
        } else if(detached){
            int result=0;
            for(int n=0;n<1000;n++){
                result=mach_port_type(mach_task_self_,p,&type);
                if(result==15)break;
                WORK_CHECK(result==0 && type==0x10000 && usleep(1000)==0,59);
            }
            WORK_CHECK(result==15,60);type=0xa5a5a5a5;
        }
        WORK_CHECK(pthread_from_mach_thread_np(p)==0 && *__error()==177,28);
        WORK_CHECK(mach_port_type(mach_task_self_,p,&type)==15 && type==0xa5a5a5a5 && mach_port_deallocate(mach_task_self_,p)==15 && *__error()==177,32);
        WORK_CHECK(pthread_mutex_lock(&state.mutex)==0 && jobs[i].visits==3 && pthread_mutex_unlock(&state.mutex)==0,61);
    }
    CHECK(started==8 && pthread_key_delete(state.key)==0 && pthread_cond_destroy(&state.gate)==0 && pthread_mutex_destroy(&state.mutex)==0,33);return 0;
}
int main(int argc,char **argv){
    *__error()=177;
    CHECK(!pthread_mach_thread_np(0) && !pthread_from_mach_thread_np(0) && !pthread_from_mach_thread_np(~0u) && *__error()==177,40);
    unsigned borrowed=pthread_mach_thread_np(pthread_self()),base=0;CHECK(borrowed && mach_port_get_refs(mach_task_self_,borrowed,0,&base)==0,41);
    for(int i=0;i<64;i++)CHECK(pthread_mach_thread_np(pthread_self())==borrowed && refs(borrowed,base)==0,42);
    CHECK(mach_thread_self()==borrowed && refs(borrowed,base+1)==0 && mach_port_deallocate(mach_task_self_,borrowed)==0 && refs(borrowed,base)==0,43);
    CHECK(mach_port_mod_refs(mach_task_self_,borrowed,4,0)==17 && mach_port_mod_refs(mach_task_self_,borrowed,0,-100)==18 && refs(borrowed,base)==0,44);
    struct {unsigned before,value,after;} output={0x12345678,0xa5a5a5a5,0x87654321};
    CHECK(mach_port_type(mach_task_self_,0,&output.value)==15 && output.value==0xa5a5a5a5 && mach_port_type(mach_task_self_,~0u,&output.value)==0 && output.value==0x100000 && output.before==0x12345678 && output.after==0x87654321,45);
    CHECK(mach_port_deallocate(mach_task_self_,0)==0 && mach_port_deallocate(mach_task_self_,~0u)==0,46);
    if(argc>1 && !strcmp(argv[1],"--create-failure")){
        word attributes[8];struct {word before,handle,after;} output={0x123456789abcdef0UL,0xaaaaaaaaaaaaaaaaUL,0xfedcba9876543210UL};
        CHECK(pthread_attr_init(attributes)==0 && pthread_attr_setstacksize(attributes,~16383UL)==0,65);
        for(int i=0;i<64;i++){
            *__error()=177;
            CHECK(pthread_create(&output.handle,attributes,worker,0)==22 && output.handle==0xaaaaaaaaaaaaaaaaUL && output.before==0x123456789abcdef0UL && output.after==0xfedcba9876543210UL && *__error()==177,66);
        }
        CHECK(pthread_attr_destroy(attributes)==0,67);
        puts("IOS-PTHREAD-MACH: failed native creation preserves outputs and releases unpublished lifetime objects");return 0;
    }
    if(argc>1 && !strcmp(argv[1],"--saturated")){
        CHECK(mach_port_mod_refs(mach_task_self_,borrowed,0,65535)==0 && refs(borrowed,65535)==0,47);
        CHECK(mach_port_mod_refs(mach_task_self_,borrowed,0,-65535)==20 && mach_port_mod_refs(mach_task_self_,borrowed,0,-65534)==0 && mach_port_mod_refs(mach_task_self_,borrowed,0,65536)==18 && mach_port_deallocate(mach_task_self_,borrowed)==0 && mach_thread_self()==borrowed && refs(borrowed,65535)==0,48);
        puts("IOS-PTHREAD-MACH: native send references saturate and remain pinned");return 0;
    }
    for(int i=0;i<8;i++)CHECK(roundtrip(!i,0)==0,49);
    CHECK(roundtrip(0,1)==0,62);
    puts("IOS-PTHREAD-MACH: real thread identities, borrowed ports, owned send references, native scheduling, fork isolation and destructor lifetime in eight threads");return 0;
}
