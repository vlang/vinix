// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long word;
struct mutex {word words[8];};
struct condition {word words[6];};
extern word pthread_self(void);
extern int pthread_equal(word,word),pthread_main_np(void),pthread_create(word *,const void *,void *(*)(void *),void *),pthread_join(word,void **);
extern void pthread_exit(void *) __attribute__((noreturn));
extern int pthread_key_create(word *,void (*)(void *)),pthread_key_delete(word),pthread_setspecific(word,const void *);
extern void *pthread_getspecific(word);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_lock(void *),pthread_mutex_unlock(void *),pthread_mutex_destroy(void *);
extern int pthread_cond_init(void *,const void *),pthread_cond_wait(void *,void *),pthread_cond_broadcast(void *),pthread_cond_destroy(void *);
extern int *__error(void),puts(const char *),printf(const char *,...),fflush(void *),strcmp(const char *,const char *),fork(void),waitpid(int,int *,int);
extern void _exit(int) __attribute__((noreturn));
#define CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-IDENTITY: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define WORK_CHECK(value,code) do {if(!(value)){printf("IOS-PTHREAD-IDENTITY: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(91);}}while(0)
struct state {struct mutex mutex;struct condition gate;word main,key;int ready,go,fork_worker;};
struct job {struct state *state;word id;int index,visits,completed;};
static _Thread_local volatile int initial=17,zero;
static void cleanup(void *context){
    struct job *job=context;
    WORK_CHECK(pthread_getspecific(job->state->key)==0,1);
    *__error()=177;
    WORK_CHECK(pthread_main_np()==0 && pthread_equal(pthread_self(),job->id) && !pthread_equal(job->id,job->state->main) && *__error()==177,2);
    job->visits++;
    if(job->visits<3)WORK_CHECK(pthread_setspecific(job->state->key,job)==0,3);
    else job->completed=1;
}
static void explicit_exit(struct job *job){pthread_exit(job->index==7?0:job);}
static void *worker(void *context){
    struct job *job=context;struct state *state=job->state;
    WORK_CHECK(initial==17 && !zero && pthread_getspecific(state->key)==0,4);
    initial=29;zero=job->index+1;
    WORK_CHECK(pthread_mutex_lock(&state->mutex)==0,5);
    state->ready++;WORK_CHECK(pthread_cond_broadcast(&state->gate)==0,6);
    while(!state->go)WORK_CHECK(pthread_cond_wait(&state->gate,&state->mutex)==0,7);
    WORK_CHECK(pthread_mutex_unlock(&state->mutex)==0,8);
    *__error()=177;
    WORK_CHECK(pthread_main_np()==0 && pthread_equal(pthread_self(),job->id)==1 && pthread_equal(job->id,pthread_self())==1 && !pthread_equal(job->id,state->main) && !pthread_equal(0,job->id) && *__error()==177,9);
    WORK_CHECK(initial==29 && zero==job->index+1 && pthread_setspecific(state->key,job)==0,10);
    if(state->fork_worker && !job->index){
        int child=fork();
        if(!child)_exit(pthread_main_np()==0 && pthread_equal(pthread_self(),job->id)?0:92);
        WORK_CHECK(child>0,11);int status=-1;
        WORK_CHECK(waitpid(child,&status,0)==child && status==0,12);
    }
    if(job->index&1)explicit_exit(job);
    return job;
}
static int roundtrip(int expected_main,int fork_worker){
    struct state state={0};struct job jobs[8]={0};
    state.main=pthread_self();state.fork_worker=fork_worker;
    CHECK(pthread_mutex_init(&state.mutex,0)==0 && pthread_cond_init(&state.gate,0)==0 && pthread_key_create(&state.key,cleanup)==0,20);
    int started=0,error=0;
    for(int i=0;i<8;i++){
        jobs[i].state=&state;jobs[i].index=i;
        if(pthread_create(&jobs[i].id,0,worker,&jobs[i]))break;
        started++;
    }
    WORK_CHECK(pthread_mutex_lock(&state.mutex)==0,21);
    while(state.ready!=started)WORK_CHECK(pthread_cond_wait(&state.gate,&state.mutex)==0,22);
    for(int i=0;i<started;i++)for(int j=0;j<started;j++)if(pthread_equal(jobs[i].id,jobs[j].id)!=(i==j))error=1;
    state.go=1;WORK_CHECK(pthread_cond_broadcast(&state.gate)==0 && pthread_mutex_unlock(&state.mutex)==0,23);
    for(int i=0;i<started;i++){
        struct {word before;void *value;word after;} output={0x123456789abcdef0UL,(void *)1,0xfedcba9876543210UL};
        if(pthread_join(jobs[i].id,&output.value) || output.value!=(i==7?0:&jobs[i]) || output.before!=0x123456789abcdef0UL || output.after!=0xfedcba9876543210UL || jobs[i].visits!=3 || !jobs[i].completed)error=1;
    }
    CHECK(pthread_getspecific(state.key)==0 && pthread_key_delete(state.key)==0 && pthread_cond_destroy(&state.gate)==0 && pthread_mutex_destroy(&state.mutex)==0,24);
    CHECK(started==8 && !error && pthread_main_np()==expected_main,25);
    return 0;
}
int main(int argc,char **argv){
    int expected_main=!(argc>1 && !strcmp(argv[1],"--worker-entry"));
    *__error()=177;
    CHECK(pthread_main_np()==expected_main && pthread_equal(pthread_self(),pthread_self())==1 && pthread_equal(0,0)==1 && !pthread_equal(0,pthread_self()) && *__error()==177,30);
    CHECK(initial==17 && !zero,31);initial=41;zero=73;
    for(int i=0;i<8;i++)CHECK(roundtrip(expected_main,!i)==0 && initial==41 && zero==73,32);
    puts("IOS-PTHREAD-IDENTITY: native handles, process main thread, worker forks, explicit exits, guarded join values and three destructor passes in eight threads");return 0;
}
