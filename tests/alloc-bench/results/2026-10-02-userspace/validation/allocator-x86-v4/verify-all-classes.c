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

int main(void)
{
    alarm(180);
    if (every_class_burst() || repeated_thread_transitions()) return 1;
    (void)malloc_trim(0);
    printf("UALLOC-SUPPLEMENT-DONE checks=%u\n", checks);
    return 0;
}
