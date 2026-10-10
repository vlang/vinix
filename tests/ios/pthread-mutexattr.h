// SPDX-License-Identifier: GPL-2.0-or-later
/* Shared, header-free Mac/iOS checks, also run by the condition-attribute suite. */
typedef unsigned long mutex_word;
struct mutex_attr { mutex_word signature; int ceiling; unsigned flags; };
struct mutex_object { mutex_word words[8]; };
struct mutex_condition { mutex_word words[6]; };
extern int pthread_mutexattr_init(void *),pthread_mutexattr_destroy(void *);
extern int pthread_mutexattr_gettype(const void *,int *),pthread_mutexattr_settype(void *,int);
extern int pthread_mutexattr_getpolicy_np(const void *,int *),pthread_mutexattr_setpolicy_np(void *,int);
extern int pthread_mutexattr_getpshared(const void *,int *),pthread_mutexattr_setpshared(void *,int);
extern int pthread_mutexattr_getprotocol(const void *,int *),pthread_mutexattr_setprotocol(void *,int);
extern int pthread_mutexattr_getprioceiling(const void *,int *),pthread_mutexattr_setprioceiling(void *,int);
extern int pthread_mutex_init(void *,const void *),pthread_mutex_destroy(void *),pthread_mutex_lock(void *),pthread_mutex_trylock(void *),pthread_mutex_unlock(void *);
extern int pthread_cond_init(void *,const void *),pthread_cond_destroy(void *),pthread_cond_wait(void *,void *),pthread_cond_timedwait(void *,void *,const void *),pthread_cond_signal(void *),pthread_cond_broadcast(void *);
extern int pthread_create(mutex_word *,const void *,void *(*)(void *),void *),pthread_join(mutex_word,void **);
extern int *__error(void),printf(const char *,...),puts(const char *),fflush(void *),strcmp(const char *,const char *),memcmp(const void *,const void *,mutex_word);
extern void *memset(void *,int,mutex_word);
extern void _exit(int) __attribute__((noreturn));
#define MUTEX_CHECK(value,code) do {if(!(value)){printf("IOS-MUTEXATTR: failure %d errno %d\n",code,*__error());return code;}}while(0)
#define MUTEX_WORK_CHECK(value,code) do {if(!(value)){printf("IOS-MUTEXATTR: worker failure %d errno %d\n",code,*__error());fflush(0);_exit(92);}}while(0)
struct mutex_state { struct mutex_object lock,foreign; struct mutex_condition ready; int waiting,permit,count,kind; };
static void *mutex_worker(void *context) {
    struct mutex_state *s=context;*__error()=177;
    MUTEX_WORK_CHECK(pthread_mutex_unlock(&s->foreign)==1,1);
    MUTEX_WORK_CHECK(pthread_mutex_lock(&s->lock)==0,2);
    s->waiting++;MUTEX_WORK_CHECK(pthread_cond_broadcast(&s->ready)==0,3);
    while(!s->permit)MUTEX_WORK_CHECK(pthread_cond_wait(&s->ready,&s->lock)==0,4);
    MUTEX_WORK_CHECK(pthread_mutex_unlock(&s->lock)==0,5);
    for(int i=0;i<200;i++){
        MUTEX_WORK_CHECK(pthread_mutex_lock(&s->lock)==0,6);
        if(s->kind==1)MUTEX_WORK_CHECK(pthread_mutex_lock(&s->lock)==11 && pthread_mutex_trylock(&s->lock)==16,7);
        if(s->kind==2)MUTEX_WORK_CHECK(pthread_mutex_trylock(&s->lock)==0 && pthread_mutex_unlock(&s->lock)==0,8);
        s->count++;MUTEX_WORK_CHECK(pthread_mutex_unlock(&s->lock)==0 && *__error()==177,9);
    }
    return context;
}
static int mutex_roundtrip(int kind) {
    struct mutex_attr a;struct mutex_state s={0};mutex_word ids[8]={0};s.kind=kind;
    MUTEX_CHECK(pthread_mutexattr_init(&a)==0 && pthread_mutexattr_settype(&a,1)==0,50);
    MUTEX_CHECK(pthread_mutex_init(&s.foreign,&a)==0 && pthread_mutex_lock(&s.foreign)==0,51);
    MUTEX_CHECK(pthread_mutexattr_setpolicy_np(&a,3)==0 && pthread_mutexattr_settype(&a,kind)==0,52);
    struct mutex_attr copy=a;
    MUTEX_CHECK(pthread_mutex_init(&s.lock,&copy)==0 && pthread_mutexattr_destroy(&copy)==0 && pthread_mutexattr_destroy(&a)==0,53);
    MUTEX_CHECK(pthread_cond_init(&s.ready,0)==0,54);
    int started=0;for(int i=0;i<8;i++){if(pthread_create(&ids[i],0,mutex_worker,&s))break;started++;}
    MUTEX_CHECK(pthread_mutex_lock(&s.lock)==0,55);
    while(s.waiting!=started)MUTEX_CHECK(pthread_cond_wait(&s.ready,&s.lock)==0,56);
    s.permit=1;MUTEX_CHECK(pthread_cond_broadcast(&s.ready)==0,57);
    MUTEX_CHECK(pthread_mutex_unlock(&s.lock)==0,58);
    for(int i=0;i<started;i++){void *result=0;MUTEX_CHECK(pthread_join(ids[i],&result)==0 && result==&s,59);}
    MUTEX_CHECK(started==8 && s.count==1600,60);
    MUTEX_CHECK(pthread_cond_destroy(&s.ready)==0 && pthread_mutex_destroy(&s.lock)==0,61);
    MUTEX_CHECK(pthread_mutex_unlock(&s.foreign)==0 && pthread_mutex_destroy(&s.foreign)==0,62);
    return 0;
}
static int mutexattr_checks(int adapter) {
    struct {mutex_word before;struct mutex_attr a;mutex_word after;} g;
    memset(&g,0xa5,sizeof g);g.before=0x123456789abcdef0UL;g.after=0xfedcba9876543210UL;
    struct mutex_attr *a=&g.a,saved;
    struct {unsigned before;int value;unsigned after;} out={0x12345678,-7,0x87654321};
    *__error()=177;
    MUTEX_CHECK(pthread_mutexattr_getpolicy_np(a,&out.value)==22 && out.value==-7 && pthread_mutexattr_setpolicy_np(a,3)==22 && pthread_mutexattr_destroy(a)==22,1);
    MUTEX_CHECK(pthread_mutexattr_init(a)==0 && a->signature==0x4d545841 && a->ceiling==0 && a->flags==0xa5a5a4a0,2);
    MUTEX_CHECK(pthread_mutexattr_gettype(a,&out.value)==0 && out.value==0,3);
    MUTEX_CHECK(pthread_mutexattr_getpolicy_np(a,&out.value)==0 && out.value==3,4);
    MUTEX_CHECK(pthread_mutexattr_getpshared(a,&out.value)==0 && out.value==2,5);
    MUTEX_CHECK(pthread_mutexattr_getprotocol(a,&out.value)==0 && out.value==0,6);
    MUTEX_CHECK(pthread_mutexattr_getprioceiling(a,&out.value)==0 && out.value==0,7);
    saved=*a;
    for(int i=-2;i<7;i++)if(i!=1 && i!=3)MUTEX_CHECK(pthread_mutexattr_setpolicy_np(a,i)==22 && !memcmp(a,&saved,16),8);
    MUTEX_CHECK(pthread_mutexattr_settype(a,2)==0 && pthread_mutexattr_setpolicy_np(a,1)==0 && a->flags==0xa5a5a468,9);
    MUTEX_CHECK(pthread_mutexattr_gettype(a,&out.value)==0 && out.value==2 && pthread_mutexattr_getpolicy_np(a,&out.value)==0 && out.value==1,10);
    MUTEX_CHECK(pthread_mutexattr_setpshared(a,1)==0 && pthread_mutexattr_setprotocol(a,2)==0 && pthread_mutexattr_setprioceiling(a,-999)==0 && a->flags==0xa5a5a45a,11);
    MUTEX_CHECK(pthread_mutexattr_getpshared(a,&out.value)==0 && out.value==1 && pthread_mutexattr_getprotocol(a,&out.value)==0 && out.value==2 && pthread_mutexattr_getprioceiling(a,&out.value)==0 && out.value==-999,12);
    saved=*a;
    MUTEX_CHECK(pthread_mutexattr_settype(a,3)==22 && pthread_mutexattr_setpshared(a,0)==22 && pthread_mutexattr_setpshared(a,3)==22 && pthread_mutexattr_setprotocol(a,3)==22 && pthread_mutexattr_setprioceiling(a,-1000)==22 && pthread_mutexattr_setprioceiling(a,1000)==22 && !memcmp(a,&saved,16),13);
    MUTEX_CHECK(pthread_mutexattr_setprioceiling(a,999)==0 && pthread_mutexattr_getprioceiling(a,&out.value)==0 && out.value==999,14);
    MUTEX_CHECK(pthread_mutexattr_init(a)==0,15);
    for(unsigned i=0;i<8;i++){
        a->flags=(a->flags&~0x1c0U)|(i<<6);out.value=-7;
        int r=pthread_mutexattr_getpolicy_np(a,&out.value);
        MUTEX_CHECK((i==1 || i==2)?(r==0 && out.value==(i==1?1:3)):(r==22 && out.value==-7),16);
    }
    MUTEX_CHECK(pthread_mutexattr_init(a)==0,17);
    struct {mutex_word before;struct mutex_object value;mutex_word after;} object;
    memset(&object,0x5a,sizeof object);struct mutex_object untouched=object.value;
    if(adapter){
        MUTEX_CHECK(pthread_mutexattr_setpolicy_np(a,1)==0 && pthread_mutex_init(&object.value,a)==45 && !memcmp(&object.value,&untouched,64),18);
        MUTEX_CHECK(pthread_mutexattr_setpolicy_np(a,3)==0 && pthread_mutexattr_setpshared(a,1)==0 && pthread_mutex_init(&object.value,a)==45 && !memcmp(&object.value,&untouched,64),19);
        MUTEX_CHECK(pthread_mutexattr_setpshared(a,2)==0 && pthread_mutexattr_setprotocol(a,1)==0 && pthread_mutex_init(&object.value,a)==45 && !memcmp(&object.value,&untouched,64),20);
        MUTEX_CHECK(pthread_mutexattr_setprotocol(a,2)==0 && pthread_mutex_init(&object.value,a)==45 && !memcmp(&object.value,&untouched,64),21);
    }else{
        MUTEX_CHECK(pthread_mutexattr_setpolicy_np(a,1)==0 && pthread_mutex_init(&object.value,a)==0 && pthread_mutex_lock(&object.value)==0 && pthread_mutex_unlock(&object.value)==0 && pthread_mutex_destroy(&object.value)==0,22);
    }
    MUTEX_CHECK(pthread_mutexattr_init(a)==0 && pthread_mutexattr_settype(a,2)==0 && pthread_mutexattr_setprioceiling(a,-999)==0,23);
    struct mutex_attr copy=*a;
    MUTEX_CHECK(pthread_mutexattr_destroy(a)==0 && pthread_mutexattr_destroy(a)==22 && a->signature==0 && a->ceiling==-999 && a->flags==0xa5a5a4a8,24);
    untouched=object.value;MUTEX_CHECK(pthread_mutex_init(&object.value,a)==22 && (!adapter || !memcmp(&object.value,&untouched,64)),25);
    MUTEX_CHECK(pthread_mutex_init(&object.value,&copy)==0 && pthread_mutexattr_destroy(&copy)==0,26);
    MUTEX_CHECK(pthread_mutex_lock(&object.value)==0 && pthread_mutex_trylock(&object.value)==0 && pthread_mutex_unlock(&object.value)==0,27);
    struct mutex_condition c;struct {long sec,nsec;} deadline={0,0};
    MUTEX_CHECK(pthread_cond_init(&c,0)==0 && pthread_cond_timedwait(&c,&object.value,&deadline)==60 && pthread_mutex_trylock(&object.value)==0 && pthread_mutex_unlock(&object.value)==0,28);
    MUTEX_CHECK(pthread_mutex_unlock(&object.value)==0 && pthread_mutex_unlock(&object.value)==1 && pthread_mutex_destroy(&object.value)==0 && pthread_cond_destroy(&c)==0,29);
    MUTEX_CHECK(object.before==0x5a5a5a5a5a5a5a5aUL && object.after==0x5a5a5a5a5a5a5a5aUL && g.before==0x123456789abcdef0UL && g.after==0xfedcba9876543210UL && out.before==0x12345678 && out.after==0x87654321 && *__error()==177,30);
    struct mutex_object statics[]={{{0x32aaaba7}},{{0x32aaaba3}},{{0x32aaaba1}},{{0x32aaaba2}}};
    for(int i=0;i<4;i++)MUTEX_CHECK(pthread_mutex_lock(&statics[i])==0 && pthread_mutex_unlock(&statics[i])==0 && pthread_mutex_destroy(&statics[i])==0,31);
    for(int round=0;round<3;round++)for(int kind=0;kind<3;kind++)MUTEX_CHECK(mutex_roundtrip(kind)==0,32);
    puts("IOS-MUTEXATTR: guarded Darwin layouts, copied types and policies, native FIRSTFIT contention, recursive/errorcheck ownership, condition waits and eight threads");
    return 0;
}
