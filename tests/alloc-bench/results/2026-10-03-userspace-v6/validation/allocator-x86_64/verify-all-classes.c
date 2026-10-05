#define main original_verify_main
#include "verify.c"
#undef main

/* Supplement the public API checks with a burst in every ordinary class.
 * The requests sit just below each class's upper payload boundary. */
static int every_class_burst(void)
{
    static const unsigned units[] = {
        1,2,3,4,5,6,7,8,9,10,12,15,18,20,25,31,
        36,42,50,63,72,84,102,127,146,170,204,255,
        292,340,409,511,584,682,818,1023,1169,1364,1637,2047,
        2340,2730,3276,4095,4680,5460,6552,8191
    };
    unsigned char *live[72];
    for (unsigned round=0; round<3; ++round) {
        for (unsigned sc=0; sc<48; ++sc) {
            const size_t n=(size_t)units[sc]*16-5;
            for (unsigned i=0; i<72; ++i) {
                live[i]=malloc(n);
                REQUIRE(live[i] && !((uintptr_t)live[i]&15));
                memset(live[i], (int)(i+sc+round+1), n);
            }
            for (unsigned i=0; i<72; i+=2) {
                REQUIRE(has_byte(live[i],n,(unsigned char)(i+sc+round+1)));
                free(live[i]); live[i]=NULL;
            }
            errno=ERANGE;
            (void)malloc_trim(0);
            REQUIRE(errno==ERANGE);
            for (unsigned i=1; i<72; i+=2) {
                REQUIRE(has_byte(live[i],n,(unsigned char)(i+sc+round+1)));
                free(live[i]); live[i]=NULL;
            }
            for (unsigned i=0; i<12; ++i) {
                unsigned char *p=calloc(1,n);
                REQUIRE(p && has_byte(p,n,0));
                memset(p,0xb9,n);
                free(p);
            }
            (void)malloc_trim(0);
        }
    }
    puts("UALLOC-ALL-CLASSES classes=48 burst=72 rounds=3");
    return 0;
}

static void *transition_worker(void *ignored)
{
    (void)ignored;
    unsigned char *p=malloc(96);
    if (p) memset(p,0x7a,96);
    return p;
}

/* After the final worker exits musl marks need_locks negative. Repeated
 * public allocations and trims exercise its negative-to-zero transition,
 * then another pthread creation publishes the multithreaded state again. */
static int repeated_thread_transitions(void)
{
    for (unsigned cycle=0; cycle<24; ++cycle) {
        unsigned char *held=malloc(64);
        REQUIRE(held);
        memset(held,0x6d,64);
        pthread_t worker_thread;
        REQUIRE(!pthread_create(&worker_thread,NULL,transition_worker,NULL));
        void *transferred=NULL;
        REQUIRE(!pthread_join(worker_thread,&transferred));
        REQUIRE(has_byte(held,64,0x6d));
        free(held);
        REQUIRE(transferred && has_byte(transferred,96,0x7a));
        free(transferred);
        unsigned char *p=calloc(1,96);
        REQUIRE(p && has_byte(p,96,0));
        free(p);
        errno=EDOM;
        (void)malloc_trim(0);
        REQUIRE(errno==EDOM);
    }
    puts("UALLOC-THREAD-TRANSITIONS cycles=24");
    return 0;
}

/* Small independent requests repeatedly exhaust and refill a warmed group.
 * Keeping one allocation alive also checks that reuse never steals its slot. */
static int repeated_group_refills(void)
{
    static const size_t requests[] = {0, 11, 27, 43, 59, 75, 123, 187,
        315, 491, 1003, 2011, 4075, 8171, 16363, 32747, 65515, 131051};
    for (unsigned s=0; s<sizeof requests/sizeof requests[0]; ++s) {
        size_t n=requests[s];
        (void)malloc_trim(0);
        unsigned char *held=malloc(n);
        REQUIRE(held);
        memset(held,0x57,n);
        for (unsigned round=0; round<129; ++round) {
            unsigned char *p=round&1 ? calloc(1,n) : malloc(n);
            REQUIRE(p && p!=held && !((uintptr_t)p&15));
            if (round&1) REQUIRE(has_byte(p,n,0));
            memset(p,(int)(round+1),n);
            REQUIRE(has_byte(p,n,(unsigned char)(round+1)));
            REQUIRE(has_byte(held,n,0x57));
            free(p);
        }
        free(held);
        (void)malloc_trim(0);
    }
    puts("UALLOC-GROUP-REFILLS requests=18 rounds=129");
    return 0;
}

static unsigned char *callback_live;
static unsigned callback_prepare_count, callback_parent_count, callback_child_count;
static int callback_failed;

static void callback_allocate(void)
{
    unsigned char *p=calloc(1,75);
    if (!p || !has_byte(p,75,0)) { callback_failed=1; free(p); return; }
    memset(p,0xa6,75);
    unsigned char *q=realloc(p,262144);
    if (!q) { callback_failed=1; free(p); return; }
    if (!has_byte(q,75,0xa6) || !has_byte(callback_live,96,0x3c))
        callback_failed=1;
    memset(q,0xda,262144);
    free(q);
    errno=EDOM;
    (void)malloc_trim(0);
    if (errno!=EDOM || !has_byte(callback_live,96,0x3c)) callback_failed=1;
}

static void callback_prepare(void) { ++callback_prepare_count; callback_allocate(); }
static void callback_parent(void) { ++callback_parent_count; callback_allocate(); }
static void callback_child(void) { ++callback_child_count; callback_allocate(); }

/* Exercise allocation in each public atfork callback, both with a concurrent
 * allocator thread and after it exits and need_locks changes state again. */
static int allocations_in_fork_callbacks(void)
{
    callback_live=malloc(96);
    REQUIRE(callback_live);
    memset(callback_live,0x3c,96);
    REQUIRE(!pthread_atfork(callback_prepare,callback_parent,callback_child));
    for (unsigned phase=0; phase<2; ++phase) {
        pthread_t thread;
        if (!phase) {
            atomic_store(&worker_stop,0);
            REQUIRE(!pthread_create(&thread,NULL,worker,(void *)(uintptr_t)3));
        }
        for (unsigned trial=0; trial<4; ++trial) {
            unsigned expected=phase*4+trial+1;
            pid_t child=fork();
            REQUIRE(child>=0);
            if (!child) {
                alarm(20);
                int ok=!callback_failed && callback_prepare_count==expected &&
                    callback_parent_count==expected-1 && callback_child_count==1 &&
                    has_byte(callback_live,96,0x3c);
                free(callback_live);
                _exit(ok ? 0 : 1);
            }
            int status;
            REQUIRE(waitpid(child,&status,0)==child && WIFEXITED(status) &&
                !WEXITSTATUS(status));
            REQUIRE(!callback_failed && callback_prepare_count==expected &&
                callback_parent_count==expected && !callback_child_count &&
                has_byte(callback_live,96,0x3c));
        }
        if (!phase) {
            atomic_store(&worker_stop,1);
            void *transfer=NULL;
            REQUIRE(!pthread_join(thread,&transfer));
            REQUIRE(transfer && has_byte(transfer,79+3*64,30));
            free(transfer);
            REQUIRE(!atomic_load(&worker_failed));
        }
    }
    /* No subsequent fork invokes the permanently registered callbacks. */
    free(callback_live);
    callback_live=NULL;
    puts("UALLOC-ATFORK-ALLOCATIONS phases=2 forks=8");
    return 0;
}

int main(void)
{
    alarm(180);
    if (every_class_burst() || repeated_group_refills() ||
        repeated_thread_transitions() || allocations_in_fork_callbacks()) return 1;
    (void)malloc_trim(0);
    printf("UALLOC-SUPPLEMENT-DONE checks=%u\n", checks);
    return 0;
}
