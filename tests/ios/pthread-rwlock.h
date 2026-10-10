// SPDX-License-Identifier: GPL-2.0-or-later
/* Header-free Mac/iOS synchronization checks shared with the attribute suite. */
typedef unsigned long rw_word;
struct rw_attr {rw_word signature;unsigned share,pad;rw_word unused;};
struct rw_object {rw_word words[25];};
struct rw_mutex {rw_word words[8];};
struct rw_condition {rw_word words[6];};
extern int pthread_rwlockattr_init(void *),pthread_rwlockattr_destroy(void *),pthread_rwlockattr_getpshared(const void *,int *),pthread_rwlockattr_setpshared(void *,int);
extern int pthread_rwlock_init(void *,const void *),pthread_rwlock_destroy(void *),pthread_rwlock_rdlock(void *),pthread_rwlock_tryrdlock(void *),pthread_rwlock_wrlock(void *),pthread_rwlock_trywrlock(void *),pthread_rwlock_unlock(void *);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_destroy(void *),pthread_mutex_lock(void *),pthread_mutex_unlock(void *);
extern int pthread_cond_init(void *,const void *),pthread_cond_destroy(void *),pthread_cond_wait(void *,void *),pthread_cond_broadcast(void *);
extern int pthread_create(rw_word *,const void *,void *(*)(void *),void *),pthread_join(rw_word,void **),sched_yield(void);
extern int *__error(void),printf(const char *,...),puts(const char *),fflush(void *),strcmp(const char *,const char *),memcmp(const void *,const void *,rw_word);
extern void *memset(void *,int,rw_word);
extern void _exit(int) __attribute__((noreturn));
#define RW_CHECK(value,code) do {if(!(value)){printf("IOS-RWLOCK: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define RW_WORK_CHECK(value,code) do {if(!(value)){printf("IOS-RWLOCK: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(93);}}while(0)
struct rw_state {struct rw_object rw;struct rw_mutex mutex;struct rw_condition changed;int entered,writer,reader,release,left,right;};
static void *rw_queued_writer(void *context){
    struct rw_state *s=context;*__error()=177;
    RW_WORK_CHECK(pthread_mutex_lock(&s->mutex)==0,1);s->entered=1;
    RW_WORK_CHECK(pthread_cond_broadcast(&s->changed)==0 && pthread_mutex_unlock(&s->mutex)==0,2);
    RW_WORK_CHECK(pthread_rwlock_wrlock(&s->rw)==0,3);
    RW_WORK_CHECK(pthread_rwlock_trywrlock(&s->rw)==16 && pthread_rwlock_tryrdlock(&s->rw)==16,4);
    RW_WORK_CHECK(pthread_mutex_lock(&s->mutex)==0,5);s->writer=1;
    RW_WORK_CHECK(pthread_cond_broadcast(&s->changed)==0,6);
    while(!s->release)RW_WORK_CHECK(pthread_cond_wait(&s->changed,&s->mutex)==0,7);
    RW_WORK_CHECK(pthread_mutex_unlock(&s->mutex)==0,8);s->left=42;s->right=42^0x12345678;
    RW_WORK_CHECK(pthread_rwlock_unlock(&s->rw)==0 && *__error()==177,9);return context;
}
static void *rw_queued_reader(void *context){
    struct rw_state *s=context;*__error()=177;
    RW_WORK_CHECK(pthread_rwlock_tryrdlock(&s->rw)==16 && pthread_rwlock_trywrlock(&s->rw)==16,10);
    RW_WORK_CHECK(pthread_mutex_lock(&s->mutex)==0,11);s->reader=1;
    RW_WORK_CHECK(pthread_cond_broadcast(&s->changed)==0 && pthread_mutex_unlock(&s->mutex)==0,12);
    RW_WORK_CHECK(pthread_rwlock_rdlock(&s->rw)==0 && s->left==42 && s->right==(42^0x12345678),13);
    RW_WORK_CHECK(pthread_rwlock_unlock(&s->rw)==0 && *__error()==177,14);return context;
}
static int rw_writer_preference(void){
    struct rw_state s={0};rw_word writer,reader;
    RW_CHECK(pthread_rwlock_init(&s.rw,0)==0 && pthread_mutex_init(&s.mutex,0)==0 && pthread_cond_init(&s.changed,0)==0,50);
    RW_CHECK(pthread_rwlock_rdlock(&s.rw)==0 && pthread_create(&writer,0,rw_queued_writer,&s)==0,51);
    RW_CHECK(pthread_mutex_lock(&s.mutex)==0,52);
    while(!s.entered)RW_CHECK(pthread_cond_wait(&s.changed,&s.mutex)==0,53);
    RW_CHECK(pthread_mutex_unlock(&s.mutex)==0,54);
    int queued=0;
    for(int i=0;i<100000;i++){
        int r=pthread_rwlock_tryrdlock(&s.rw);
        if(r==16){queued=1;break;}
        RW_CHECK(r==0 && pthread_rwlock_unlock(&s.rw)==0,55);sched_yield();
    }
    RW_CHECK(queued && pthread_rwlock_destroy(&s.rw)==16 && pthread_rwlock_tryrdlock(&s.rw)==16,56);
    RW_CHECK(pthread_rwlock_unlock(&s.rw)==0 && pthread_mutex_lock(&s.mutex)==0,57);
    while(!s.writer)RW_CHECK(pthread_cond_wait(&s.changed,&s.mutex)==0,58);
    RW_CHECK(pthread_create(&reader,0,rw_queued_reader,&s)==0,59);
    while(!s.reader)RW_CHECK(pthread_cond_wait(&s.changed,&s.mutex)==0,60);
    RW_CHECK(pthread_rwlock_destroy(&s.rw)==16,61);s.release=1;
    RW_CHECK(pthread_cond_broadcast(&s.changed)==0 && pthread_mutex_unlock(&s.mutex)==0,62);
    void *result=0;
    RW_CHECK(pthread_join(writer,&result)==0 && result==&s && pthread_join(reader,&result)==0 && result==&s,63);
    RW_CHECK(pthread_rwlock_destroy(&s.rw)==0 && pthread_cond_destroy(&s.changed)==0 && pthread_mutex_destroy(&s.mutex)==0,64);
    return 0;
}
static void *rw_shared_reader(void *context){
    struct rw_state *s=context;*__error()=177;
    RW_WORK_CHECK(pthread_rwlock_rdlock(&s->rw)==0 && pthread_mutex_lock(&s->mutex)==0,30);
    s->reader++;RW_WORK_CHECK(pthread_cond_broadcast(&s->changed)==0,31);
    while(!s->release)RW_WORK_CHECK(pthread_cond_wait(&s->changed,&s->mutex)==0,32);
    RW_WORK_CHECK(pthread_mutex_unlock(&s->mutex)==0 && pthread_rwlock_unlock(&s->rw)==0 && *__error()==177,33);
    return context;
}
static int rw_shared_readers(void){
    struct rw_state s={0};rw_word ids[8];
    RW_CHECK(pthread_rwlock_init(&s.rw,0)==0 && pthread_mutex_init(&s.mutex,0)==0 && pthread_cond_init(&s.changed,0)==0,80);
    int started=0;for(int i=0;i<8;i++){if(pthread_create(&ids[i],0,rw_shared_reader,&s))break;started++;}
    RW_CHECK(pthread_mutex_lock(&s.mutex)==0,81);
    while(s.reader!=started)RW_CHECK(pthread_cond_wait(&s.changed,&s.mutex)==0,82);
    RW_CHECK(s.reader==8 && pthread_rwlock_trywrlock(&s.rw)==16 && pthread_rwlock_destroy(&s.rw)==16,83);
    s.release=1;RW_CHECK(pthread_cond_broadcast(&s.changed)==0 && pthread_mutex_unlock(&s.mutex)==0,84);
    for(int i=0;i<started;i++){void *result=0;RW_CHECK(pthread_join(ids[i],&result)==0 && result==&s,85);}
    RW_CHECK(pthread_rwlock_trywrlock(&s.rw)==0 && pthread_rwlock_unlock(&s.rw)==0 && pthread_rwlock_destroy(&s.rw)==0,86);
    RW_CHECK(pthread_cond_destroy(&s.changed)==0 && pthread_mutex_destroy(&s.mutex)==0,87);
    return 0;
}
struct rw_job {struct rw_state *s;int writing;};
static void *rw_mixed_worker(void *context){
    struct rw_job *job=context;struct rw_state *s=job->s;*__error()=177;
    for(int i=0;i<200;i++){
        if(job->writing){
            RW_WORK_CHECK(pthread_rwlock_wrlock(&s->rw)==0,20);
            s->left++;sched_yield();s->right=s->left^0x12345678;
        }else{
            RW_WORK_CHECK(pthread_rwlock_rdlock(&s->rw)==0,21);
            RW_WORK_CHECK(s->right==(s->left^0x12345678),22);
        }
        RW_WORK_CHECK(pthread_rwlock_unlock(&s->rw)==0 && *__error()==177,24);
    }
    return context;
}
static int rw_mixed_roundtrip(void){
    struct rw_state s={0};struct rw_job jobs[8];rw_word ids[8];struct rw_attr attr;
    s.right=0x12345678;RW_CHECK(pthread_rwlockattr_init(&attr)==0,70);
    struct rw_attr copy=attr;
    RW_CHECK(pthread_rwlock_init(&s.rw,&copy)==0 && pthread_rwlockattr_destroy(&attr)==0 && pthread_rwlockattr_destroy(&copy)==0,71);
    int started=0;for(int i=0;i<8;i++){jobs[i].s=&s;jobs[i].writing=i&1;if(pthread_create(&ids[i],0,rw_mixed_worker,&jobs[i]))break;started++;}
    for(int i=0;i<started;i++){void *result=0;RW_CHECK(pthread_join(ids[i],&result)==0 && result==&jobs[i],72);}
    RW_CHECK(started==8 && s.left==800 && s.right==(800^0x12345678) && pthread_rwlock_destroy(&s.rw)==0,73);
    return 0;
}
static int rwlock_checks(int adapter){
    struct {rw_word before;struct rw_attr attr;rw_word after;} g;
    memset(&g,0xa5,sizeof g);g.before=0x123456789abcdef0UL;g.after=0xfedcba9876543210UL;
    struct rw_attr *a=&g.attr;struct {unsigned before;int share;unsigned after;} out={0x12345678,-7,0x87654321};
    *__error()=177;
    RW_CHECK(pthread_rwlockattr_getpshared(a,&out.share)==22 && out.share==-7 && pthread_rwlockattr_setpshared(a,2)==22,1);
    RW_CHECK(pthread_rwlockattr_destroy(a)==0 && a->signature==0 && a->share==0 && a->pad==0xa5a5a5a5 && a->unused==0xa5a5a5a5a5a5a5a5UL,2);
    RW_CHECK(pthread_rwlockattr_init(a)==0 && a->signature==0x52574c41 && a->share==2 && a->pad==0xa5a5a5a5 && a->unused==0xa5a5a5a5a5a5a5a5UL,3);
    RW_CHECK(pthread_rwlockattr_getpshared(a,&out.share)==0 && out.share==2,4);
    struct rw_attr saved=*a;
    for(int i=-2;i<5;i++)if(i!=1 && i!=2)RW_CHECK(pthread_rwlockattr_setpshared(a,i)==22 && !memcmp(a,&saved,24),5);
    RW_CHECK(pthread_rwlockattr_setpshared(a,1)==0 && pthread_rwlockattr_getpshared(a,&out.share)==0 && out.share==1,6);
    struct {rw_word before;struct rw_object value;rw_word after;} object;
    memset(&object,0x5a,sizeof object);struct rw_object untouched=object.value;
    RW_CHECK(pthread_rwlock_init(&object.value,a)==(adapter?45:0),7);
    if(adapter)RW_CHECK(!memcmp(&object.value,&untouched,200),8);
    else RW_CHECK(pthread_rwlock_destroy(&object.value)==0,9);
    RW_CHECK(pthread_rwlockattr_setpshared(a,2)==0,10);
    struct rw_attr copy=*a;
    RW_CHECK(pthread_rwlockattr_destroy(a)==0 && pthread_rwlockattr_destroy(a)==0,11);
    untouched=object.value;RW_CHECK(pthread_rwlock_init(&object.value,a)==22 && !memcmp(&object.value,&untouched,200),12);
    RW_CHECK(pthread_rwlock_init(&object.value,&copy)==0 && pthread_rwlockattr_destroy(&copy)==0,13);
    RW_CHECK(pthread_rwlock_unlock(&object.value)==0 && pthread_rwlock_rdlock(&object.value)==0 && pthread_rwlock_tryrdlock(&object.value)==0 && pthread_rwlock_trywrlock(&object.value)==16,14);
    RW_CHECK(pthread_rwlock_destroy(&object.value)==16 && pthread_rwlock_unlock(&object.value)==0 && pthread_rwlock_unlock(&object.value)==0,15);
    RW_CHECK(pthread_rwlock_wrlock(&object.value)==0 && pthread_rwlock_rdlock(&object.value)==11 && pthread_rwlock_wrlock(&object.value)==11 && pthread_rwlock_tryrdlock(&object.value)==11 && pthread_rwlock_trywrlock(&object.value)==11,16);
    RW_CHECK(pthread_rwlock_destroy(&object.value)==16 && pthread_rwlock_unlock(&object.value)==0 && pthread_rwlock_destroy(&object.value)==0 && object.value.words[0]==0,17);
    RW_CHECK(g.before==0x123456789abcdef0UL && g.after==0xfedcba9876543210UL && object.before==0x5a5a5a5a5a5a5a5aUL && object.after==0x5a5a5a5a5a5a5a5aUL && out.before==0x12345678 && out.after==0x87654321 && *__error()==177,18);
    struct rw_object lazy={{0x2da8b3b4}};
    RW_CHECK(pthread_rwlock_rdlock(&lazy)==0 && pthread_rwlock_unlock(&lazy)==0 && pthread_rwlock_destroy(&lazy)==0,19);
    for(int i=0;i<8;i++)RW_CHECK(rw_writer_preference()==0,25);
    RW_CHECK(rw_shared_readers()==0,27);
    for(int i=0;i<3;i++)RW_CHECK(rw_mixed_roundtrip()==0,26);
    puts("IOS-RWLOCK: guarded attributes, copied private locks, queued writer preference, native shared reads, exclusive writes, deadlock errors, busy destruction and eight threads");
    return 0;
}
