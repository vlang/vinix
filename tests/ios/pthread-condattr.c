// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long word;
struct attr {word signature,flags;};
struct condition {word words[6];};
struct mutex {word words[8];};
struct guarded_condition {word before;struct condition value;word after;};
extern int pthread_condattr_init(void *),pthread_condattr_destroy(void *),pthread_condattr_getpshared(const void *,int *),pthread_condattr_setpshared(void *,int);
extern int pthread_cond_init(void *,const void *),pthread_cond_destroy(void *),pthread_cond_wait(void *,void *),pthread_cond_timedwait(void *,void *,const void *),pthread_cond_signal(void *),pthread_cond_broadcast(void *);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_destroy(void *),pthread_mutex_lock(void *),pthread_mutex_unlock(void *);
extern int pthread_create(word *,const void *,void *(*)(void *),void *),pthread_join(word,void **);
extern int * __error(void),puts(const char *),printf(const char *,...),fflush(void *),strcmp(const char *,const char *),memcmp(const void *,const void *,word);
extern void *memset(void *,int,word);
extern void _exit(int) __attribute__((noreturn));
#define CHECK(value,code) do {if(!(value)){printf("IOS-CONDATTR: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define WORK_CHECK(value,code) do {if(!(value)){printf("IOS-CONDATTR: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(91);}}while(0)
struct state {struct mutex mutex;struct condition ready;int waiting,done;};
struct job {struct state *state;struct guarded_condition go;word id;int permit;};
static _Thread_local int tls;
static void *worker(void *context){
    struct job *job=context;struct state *state=job->state;
    WORK_CHECK(!tls,1);tls=41;*__error()=177;
    WORK_CHECK(pthread_mutex_lock(&state->mutex)==0,2);state->waiting++;
    WORK_CHECK(pthread_cond_signal(&state->ready)==0,3);
    while(!job->permit)WORK_CHECK(pthread_cond_wait(&job->go.value,&state->mutex)==0 && *__error()==177,4);
    state->done++;WORK_CHECK(pthread_cond_broadcast(&state->ready)==0 && *__error()==177,5);
    WORK_CHECK(pthread_mutex_unlock(&state->mutex)==0,6);return context;
}
static int roundtrip(void){
    struct state state={0};struct job jobs[8]={0};struct attr source;
    CHECK(pthread_condattr_init(&source)==0 && pthread_mutex_init(&state.mutex,0)==0 && pthread_cond_init(&state.ready,&source)==0,30);
    for(int i=0;i<8;i++){
        struct attr copy=source;jobs[i].state=&state;
        jobs[i].go.before=0x123456789abcdef0UL;jobs[i].go.after=0xfedcba9876543210UL;
        CHECK(pthread_cond_init(&jobs[i].go.value,&copy)==0 && pthread_condattr_destroy(&copy)==0,31);
    }
    CHECK(pthread_condattr_destroy(&source)==0,32);
    int started=0,error=0;
    for(int i=0;i<8;i++){if(pthread_create(&jobs[i].id,0,worker,&jobs[i]))break;started++;}
    CHECK(pthread_mutex_lock(&state.mutex)==0,33);
    while(state.waiting!=started)CHECK(pthread_cond_wait(&state.ready,&state.mutex)==0,34);
    for(int i=0;i<started;i++){jobs[i].permit=1;CHECK(pthread_cond_signal(&jobs[i].go.value)==0,35);}
    while(state.done!=started)CHECK(pthread_cond_wait(&state.ready,&state.mutex)==0,36);
    CHECK(pthread_mutex_unlock(&state.mutex)==0,37);
    for(int i=0;i<started;i++){void *result=0;if(pthread_join(jobs[i].id,&result) || result!=&jobs[i])error=1;}
    for(int i=0;i<8;i++)CHECK(pthread_cond_destroy(&jobs[i].go.value)==0 && jobs[i].go.before==0x123456789abcdef0UL && jobs[i].go.after==0xfedcba9876543210UL,38);
    CHECK(pthread_cond_destroy(&state.ready)==0 && pthread_mutex_destroy(&state.mutex)==0,39);
    CHECK(started==8 && !error,40);return 0;
}
int main(int argc,char **argv){
    int adapter=argc>1 && !strcmp(argv[1],"--adapter");
    struct {word before;struct attr value;word after;} guarded={0x123456789abcdef0UL,{0xa5a5a5a5a5a5a5a5UL,0xa5a5a5a5a5a5a5a5UL},0xfedcba9876543210UL};
    struct attr *a=&guarded.value;
    struct {unsigned before;int state;unsigned after;} output={0x12345678,-1,0x87654321};
    *__error()=177;CHECK(pthread_condattr_getpshared(a,&output.state)==22 && output.state==-1 && pthread_condattr_setpshared(a,2)==22,1);
    CHECK(pthread_condattr_destroy(a)==0 && a->signature==0 && a->flags==0xa5a5a5a5a5a5a5a5UL,2);
    CHECK(pthread_condattr_init(a)==0 && a->signature==0x434e4441 && a->flags==0xa5a5a5a5a5a5a5a6UL,3);
    CHECK(pthread_condattr_getpshared(a,&output.state)==0 && output.state==2 && output.before==0x12345678 && output.after==0x87654321,4);
    struct attr saved=*a;CHECK(pthread_condattr_setpshared(a,0)==22 && pthread_condattr_setpshared(a,3)==22 && !memcmp(a,&saved,16),5);
    CHECK(pthread_condattr_setpshared(a,1)==0 && pthread_condattr_getpshared(a,&output.state)==0 && output.state==1 && a->flags==0xa5a5a5a5a5a5a5a5UL,6);
    struct guarded_condition condition;memset(&condition,0x5a,sizeof condition);struct guarded_condition before=condition;
    CHECK(pthread_cond_init(&condition.value,a)==(adapter?45:0) && *__error()==177,7);
    if(adapter)CHECK(!memcmp(&condition,&before,sizeof condition),8);
    else CHECK(pthread_cond_destroy(&condition.value)==0,9);
    CHECK(pthread_condattr_setpshared(a,2)==0 && pthread_condattr_destroy(a)==0 && pthread_condattr_destroy(a)==0,10);
    output.state=-1;CHECK(pthread_condattr_getpshared(a,&output.state)==22 && output.state==-1 && pthread_condattr_setpshared(a,2)==22,11);
    /* Native condition initialization reads sharing bits even after the
     * attribute signature is destroyed; private state still initializes. */
    CHECK(pthread_cond_init(&condition.value,a)==0 && pthread_cond_destroy(&condition.value)==0,12);
    CHECK(pthread_condattr_init(a)==0,13);
    for(int state=0;state<4;state++){
        a->flags=(a->flags&~3UL)|(word)state;
        CHECK(pthread_condattr_getpshared(a,&output.state)==0 && output.state==state,14);
    }
    CHECK(pthread_condattr_setpshared(a,2)==0,15);
    struct mutex mutex;struct {long seconds,nanos;} deadline={0,0};
    CHECK(pthread_mutex_init(&mutex,0)==0 && pthread_cond_init(&condition.value,a)==0 && pthread_mutex_lock(&mutex)==0,16);
    CHECK(pthread_cond_timedwait(&condition.value,&mutex,&deadline)==60 && *__error()==177,17);
    deadline.nanos=1000000000;
    CHECK(pthread_cond_timedwait(&condition.value,&mutex,&deadline)==22 && *__error()==177,18);
    CHECK(pthread_mutex_unlock(&mutex)==0 && pthread_cond_destroy(&condition.value)==0 && pthread_mutex_destroy(&mutex)==0,19);
    CHECK(pthread_condattr_destroy(a)==0 && *__error()==177,20);
    CHECK(guarded.before==0x123456789abcdef0UL && guarded.after==0xfedcba9876543210UL,21);
    for(int i=0;i<8;i++)CHECK(roundtrip()==0,22);
    puts("IOS-CONDATTR: guarded attributes, native sharing bits, repeated destruction, copied private conditions, timed waits, signals, broadcasts and eight threads");return 0;
}
