/* SPDX-License-Identifier: GPL-2.0-only */
#include "apple_smc.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BASE UINT64_C(0x23fe00000)
#define SIZE UINT64_C(0x100000)
#define M(kind, payload) (((uint64_t)(kind) << 52) | (uint64_t)(payload))
#define LAST (UINT64_C(1) << 51)

struct message { uint64_t word; uint8_t ep; };
struct fake {
    struct message queue[512];
    unsigned head, tail;
    uint64_t ticks, step, sram_reply, buffer_address;
    unsigned min_version, max_version, map_group, percent, length, smc_status;
    unsigned sends, reads, log_acks, report_acks, last_id, hello_version;
    int no_smc, no_boot, drop_sram, drop_read, wrong_id, notifications;
    int recv_error, send_error, flood, zero_buffer;
    int iop_received, ap_received, app_started, boot_ack_first;
};

static void enqueue(struct fake *f, uint8_t ep, uint64_t word)
{
    assert(f->tail - f->head < 512);
    f->queue[f->tail++ % 512] = (struct message){word, ep};
}

static int tx(void *context, uint64_t word, uint8_t ep)
{
    struct fake *f = context;
    ++f->sends;
    if (f->send_error)
        return 0;
    if (!ep) {
        unsigned type = (unsigned)((word >> 52) & 255);
        switch (type) {
        case 6:
            assert((word & 0xffff) == 0x220);
            if (!f->no_boot) {
                if (f->boot_ack_first)
                    enqueue(f, 0, M(7, 0x220));
                enqueue(f, 0, M(1, f->min_version | ((uint64_t)f->max_version << 16)));
            }
            break;
        case 2:
            f->hello_version = (unsigned)(word & 0xffff);
            assert(f->hello_version == ((word >> 16) & 0xffff));
            enqueue(f, 0, M(8, 0x117)); /* mgmt, crashlog, syslog, IOReport, OSLog */
            enqueue(f, 0, M(8, LAST | ((uint64_t)f->map_group << 32) | !f->no_smc));
            if (!f->boot_ack_first)
                enqueue(f, 0, M(7, 0x220));
            break;
        case 8:
            /* Group 0 requests another map; final group echoes LAST. */
            if ((word >> 32 & 0x3f) == 0)
                assert((word & 0xffffffff) == 1);
            else
                assert(word & LAST);
            break;
        case 5: {
            unsigned started = (unsigned)((word >> 32) & 255);
            assert((word & 0xffffffff) == 2);
            if (started == 32) {
                assert(f->iop_received && f->ap_received);
                f->app_started = 1;
            } else {
                assert(started == 1 || started == 2 || started == 4 || started == 8);
                uint64_t address = f->zero_buffer ? 0 : f->buffer_address + started * 0x4000;
                uint64_t announcement = started == 8
                    ? (UINT64_C(1) << 56) | (UINT64_C(4096) << 36) | (address >> 12)
                    : M(1, (UINT64_C(1) << 44) | address);
                enqueue(f, (uint8_t)started, announcement);
            }
            break;
        }
        case 11:
            assert((word & 0xffff) == 0x20);
            enqueue(f, 0, M(11, 0x20));
            break;
        default:
            assert(!"unexpected RTKit write");
        }
    } else if (ep == 32) {
        assert(f->app_started);
        unsigned command = (unsigned)(word & 255);
        /* This checks every outgoing SMC command: no write-key, GPIO,
         * charge-limit, notification-enable, reset, or shutdown command.
         */
        assert(command == 0x17 || command == 0x10);
        if (f->notifications)
            enqueue(f, 32, UINT64_C(0x7203000000000018));
        if (command == 0x17) {
            assert((word >> 16) == 0);
            if (!f->drop_sram)
                enqueue(f, 32, f->sram_reply);
        } else {
            assert((uint32_t)(word >> 32) == 0x42525343);
            assert(((word >> 16) & 0xffff) == 2);
            ++f->reads;
            f->last_id = (unsigned)((word >> 12) & 15);
            uint64_t reply = ((uint64_t)f->percent << 32) |
                ((uint64_t)f->length << 16) | ((uint64_t)f->last_id << 12) | f->smc_status;
            if (f->wrong_id)
                enqueue(f, 32, (reply & ~UINT64_C(0xf000)) |
                        ((uint64_t)((f->last_id + 1) & 15) << 12));
            if (!f->drop_read)
                enqueue(f, 32, reply);
        }
    } else if (ep == 2) {
        assert((word >> 52 & 255) == 5);
        ++f->log_acks;
    } else if (ep == 4) {
        assert((word >> 52 & 255) == 8 || (word >> 52 & 255) == 12);
        ++f->report_acks;
    } else {
        assert(!"unexpected system endpoint write");
    }
    return 1;
}

static int rx(void *context, uint64_t *word, uint8_t *ep)
{
    struct fake *f = context;
    if (f->recv_error)
        return -1;
    if (f->head == f->tail) {
        if (!f->flood)
            return 0;
        *ep = 32;
        *word = 0x18;
        return 1;
    }
    struct message m = f->queue[f->head++ % 512];
    *word = m.word;
    *ep = m.ep;
    if (!m.ep && ((m.word >> 52) & 255) == 7)
        f->iop_received = 1;
    if (!m.ep && ((m.word >> 52) & 255) == 11)
        f->ap_received = 1;
    return 1;
}

static uint64_t tick(void *context)
{
    struct fake *f = context;
    uint64_t result = f->ticks;
    f->ticks += f->step;
    return result;
}

static void relax_cpu(void *context) { (void)context; }

static struct fake defaults(void)
{
    return (struct fake){.step=1, .min_version=11, .max_version=12,
        .map_group=1, .percent=73, .length=2,
        .sram_reply=BASE+0x80000, .buffer_address=BASE};
}

static void *new_state(void)
{
    void *s = calloc(1, vinix_smc_state_size());
    assert(s);
    return s;
}

static int boot(void *s, struct fake *f)
{
    return vinix_smc_boot(s, f, tx, rx,tick, relax_cpu, 1000, BASE, SIZE);
}

static void test_boot_and_read(void)
{
    struct fake f=defaults(); void *s=new_state();
    assert(boot(s,&f)==0);
    assert(f.hello_version==12);
    assert(vinix_smc_cached_capacity(s)==VINIX_SMC_NOT_READY);
    assert(vinix_smc_refresh(s)==73);
    assert(vinix_smc_cached_capacity(s)==73);
    assert(f.reads==1 && f.last_id==1);
    free(s);
}

static void test_version_11_and_early_power_ack(void)
{
    struct fake f=defaults(); void *s=new_state();
    f.max_version=11; f.boot_ack_first=1;
    assert(boot(s,&f)==0 && f.hello_version==11);
    assert(vinix_smc_refresh(s)==73); free(s);
}

static void test_versions_rejected(void)
{
    unsigned versions[][2]={{13,14},{1,10},{12,11}};
    for(unsigned i=0;i<3;++i) {
        struct fake f=defaults(); void *s=new_state();
        f.min_version=versions[i][0]; f.max_version=versions[i][1];
        assert(boot(s,&f)==VINIX_SMC_UNSUPPORTED); free(s);
    }
}

static void test_missing_endpoint(void)
{
    struct fake f=defaults(); void *s=new_state(); f.no_smc=1;
    assert(boot(s,&f)==VINIX_SMC_UNSUPPORTED); free(s);
}

static void test_invalid_epmap_group(void)
{
    struct fake f=defaults(); void *s=new_state(); f.map_group=8;
    assert(boot(s,&f)==VINIX_SMC_PROTOCOL); free(s);
}

static void test_firmware_buffers(void)
{
    struct fake f=defaults(); void *s=new_state();
    assert(boot(s,&f)==0); /* Includes all four firmware-owned buffer formats. */
    enqueue(&f,2,M(5,17)); enqueue(&f,4,M(8,123)); enqueue(&f,4,M(12,456));
    assert(vinix_smc_poll(s,64)==0);
    assert(f.log_acks==1 && f.report_acks==2);
    assert(vinix_smc_refresh(s)==73); free(s);
}

static void test_zero_dma_address_rejected(void)
{
    struct fake f=defaults(); void *s=new_state(); f.zero_buffer=1;
    assert(boot(s,&f)==VINIX_SMC_UNSUPPORTED); free(s);
}

static void test_firmware_buffer_outside_sram(void)
{
    struct fake f=defaults(); void *s=new_state(); f.buffer_address=BASE+SIZE;
    assert(boot(s,&f)==VINIX_SMC_PROTOCOL); free(s);
}

static void test_sram_bounds(void)
{
    uint64_t addresses[]={0,BASE-0x4000,BASE+SIZE,BASE+SIZE-0x2000,UINT64_MAX};
    for(unsigned i=0;i<sizeof(addresses)/sizeof(addresses[0]);++i) {
        struct fake f=defaults(); void *s=new_state(); f.sram_reply=addresses[i];
        assert(boot(s,&f)==VINIX_SMC_PROTOCOL); free(s);
    }
    struct fake f=defaults(); void *s=new_state(); f.sram_reply=BASE+SIZE-0x4000;
    assert(boot(s,&f)==0); free(s);
}

static void test_percentages_and_formatting(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    for(unsigned p=0;p<=100;++p) {
        f.percent=p; f.ticks+=1000;
        assert(vinix_smc_refresh(s)==(int)p);
        uint8_t output[6]={0xa5,0xa5,0xa5,0xa5,0xa5,0xa5};
        int n=vinix_smc_format_capacity((int)p,output);
        char expected[8]; int wanted=snprintf(expected,sizeof(expected),"%u\n",p);
        assert(n==wanted && !memcmp(output,expected,(size_t)n));
        assert(output[n]==0xa5); /* No terminator or buffer overrun. */
    }
    assert(vinix_smc_format_capacity(-1,NULL)==VINIX_SMC_RANGE);
    uint8_t out[4]; assert(vinix_smc_format_capacity(101,out)==VINIX_SMC_RANGE);
    free(s);
}

static void test_invalid_percentages(void)
{
    unsigned invalid[]={101,255,0x4900,0xffff}; /* Includes an endian regression. */
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    for(unsigned i=0;i<sizeof(invalid)/sizeof(invalid[0]);++i) {
        f.percent=invalid[i]; f.ticks+=1000;
        assert(vinix_smc_refresh(s)==VINIX_SMC_RANGE);
        assert(vinix_smc_cached_capacity(s)==VINIX_SMC_RANGE);
    }
    f.percent=50; f.ticks+=1000; assert(vinix_smc_refresh(s)==50); free(s);
}

static void test_wrong_id_and_notifications(void)
{
    struct fake f=defaults(); void *s=new_state(); f.wrong_id=1; f.notifications=1;
    assert(boot(s,&f)==0); assert(vinix_smc_refresh(s)==73); free(s);
}

static void test_reply_size_mismatch(void)
{
    unsigned lengths[]={0,1,3,4,256};
    for(unsigned i=0;i<sizeof(lengths)/sizeof(lengths[0]);++i) {
        struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
        f.length=lengths[i]; assert(vinix_smc_refresh(s)==VINIX_SMC_PROTOCOL);
        unsigned sent=f.sends;
        assert(vinix_smc_refresh(s)==VINIX_SMC_PROTOCOL && f.sends==sent); free(s);
    }
}

static void test_missing_key_and_completed_error(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    f.smc_status=0x84;
    assert(vinix_smc_refresh(s)==VINIX_SMC_NO_KEY);
    unsigned reads=f.reads; assert(vinix_smc_refresh(s)==VINIX_SMC_NO_KEY && f.reads==reads);
    f.smc_status=0x85; f.ticks+=1000; assert(vinix_smc_refresh(s)==VINIX_SMC_IO);
    f.smc_status=0; f.ticks+=1000; assert(vinix_smc_refresh(s)==73); free(s);
}

static void test_cache_and_stale_sample(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    assert(vinix_smc_sample_time(s)==0);
    assert(vinix_smc_refresh(s)==73); f.percent=50;
    uint64_t sampled_at=vinix_smc_sample_time(s);
    assert(vinix_smc_refresh(s)==73 && f.reads==1);
    assert(vinix_smc_sample_time(s)==sampled_at); /* Cache hits do not renew age. */
    f.ticks+=2000; assert(vinix_smc_cached_capacity(s)==VINIX_SMC_TIMEOUT);
    assert(vinix_smc_refresh(s)==50 && f.reads==2);
    assert(vinix_smc_sample_time(s)>sampled_at);
    assert(vinix_smc_sample_time(NULL)==0); free(s);
}

static void test_timeout_poison_and_late_response(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    assert(vinix_smc_refresh(s)==73); f.ticks+=1000; f.drop_read=1;
    assert(vinix_smc_refresh(s)==VINIX_SMC_TIMEOUT);
    assert(vinix_smc_cached_capacity(s)==VINIX_SMC_TIMEOUT);
    enqueue(&f,32,(UINT64_C(90)<<32)|(UINT64_C(2)<<16)|((uint64_t)f.last_id<<12));
    f.drop_read=0; f.ticks+=20000; unsigned sends=f.sends;
    assert(vinix_smc_refresh(s)==VINIX_SMC_TIMEOUT && f.sends==sends); free(s);
}

static void test_boot_and_sram_timeouts(void)
{
    struct fake f=defaults(); void *s=new_state(); f.no_boot=1;
    assert(boot(s,&f)==VINIX_SMC_TIMEOUT); free(s);
    f=defaults(); s=new_state(); f.drop_sram=1;
    assert(boot(s,&f)==VINIX_SMC_TIMEOUT); free(s);
}

static void test_stopped_clock_is_bounded(void)
{
    struct fake f=defaults(); void *s=new_state(); f.no_boot=1; f.step=0;
    assert(boot(s,&f)==VINIX_SMC_TIMEOUT); free(s);
}

static void test_notification_flood_is_bounded(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    f.flood=1; f.drop_read=1;
    assert(vinix_smc_refresh(s)==VINIX_SMC_TIMEOUT); free(s);
}

static void test_send_and_receive_failures(void)
{
    struct fake f=defaults(); void *s=new_state(); f.send_error=1;
    assert(boot(s,&f)==VINIX_SMC_IO); free(s);
    f=defaults(); s=new_state(); assert(boot(s,&f)==0); f.recv_error=1;
    assert(vinix_smc_poll(s,64)==VINIX_SMC_IO); free(s);
    f=defaults(); s=new_state(); assert(boot(s,&f)==0); f.send_error=1;
    assert(vinix_smc_refresh(s)==VINIX_SMC_IO); free(s);
}

static void test_runtime_reset_and_crash(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    enqueue(&f,0,M(1,11|(UINT64_C(12)<<16)));
    assert(vinix_smc_poll(s,64)==VINIX_SMC_IO); free(s);
    f=defaults(); s=new_state(); assert(boot(s,&f)==0);
    enqueue(&f,1,M(1,(UINT64_C(1)<<44)|(BASE+0x4000)));
    assert(vinix_smc_poll(s,64)==VINIX_SMC_IO); free(s);
}

static void test_poll_budget(void)
{
    struct fake f=defaults(); void *s=new_state(); assert(boot(s,&f)==0);
    for(unsigned i=0;i<100;++i) enqueue(&f,32,0x18);
    unsigned before=f.head;
    assert(vinix_smc_poll(s,100000)==0 && f.head-before<=64);
    assert(vinix_smc_poll(s,64)==0);
    assert(vinix_smc_refresh(s)==73); free(s);
}

static void test_counter_and_message_id_wrap(void)
{
    struct fake f=defaults(); void *s=new_state(); f.ticks=UINT64_MAX-20;
    assert(boot(s,&f)==0);
    for(unsigned i=0;i<40;++i) {
        f.ticks+=1000; f.percent=i;
        assert(vinix_smc_refresh(s)==(int)i);
        assert(f.last_id==((i+1)&15));
    }
    free(s);
}

static void test_invalid_configuration(void)
{
    struct fake f=defaults(); void *s=new_state();
    assert(vinix_smc_boot(NULL,&f,tx,rx,tick,relax_cpu,1000,BASE,SIZE)==VINIX_SMC_PROTOCOL);
    assert(vinix_smc_boot(s,&f,tx,rx,tick,relax_cpu,0,BASE,SIZE)==VINIX_SMC_PROTOCOL);
    assert(vinix_smc_boot(s,&f,tx,rx,tick,relax_cpu,UINT64_MAX,BASE,SIZE)==VINIX_SMC_PROTOCOL);
    assert(vinix_smc_boot(s,&f,tx,rx,tick,relax_cpu,1000,UINT64_MAX-100,SIZE)==VINIX_SMC_PROTOCOL);
    assert(vinix_smc_boot(s,&f,NULL,rx,tick,relax_cpu,1000,BASE,SIZE)==VINIX_SMC_PROTOCOL);
    assert(f.sends==0); free(s);
}

#define RUN(name) do { name(); ++tests; printf("PASS %s\n", #name); } while(0)
int main(void)
{
    unsigned tests=0;
    RUN(test_boot_and_read);
    RUN(test_version_11_and_early_power_ack);
    RUN(test_versions_rejected);
    RUN(test_missing_endpoint);
    RUN(test_invalid_epmap_group);
    RUN(test_firmware_buffers);
    RUN(test_zero_dma_address_rejected);
    RUN(test_firmware_buffer_outside_sram);
    RUN(test_sram_bounds);
    RUN(test_percentages_and_formatting);
    RUN(test_invalid_percentages);
    RUN(test_wrong_id_and_notifications);
    RUN(test_reply_size_mismatch);
    RUN(test_missing_key_and_completed_error);
    RUN(test_cache_and_stale_sample);
    RUN(test_timeout_poison_and_late_response);
    RUN(test_boot_and_sram_timeouts);
    RUN(test_stopped_clock_is_bounded);
    RUN(test_notification_flood_is_bounded);
    RUN(test_send_and_receive_failures);
    RUN(test_runtime_reset_and_crash);
    RUN(test_poll_budget);
    RUN(test_counter_and_message_id_wrap);
    RUN(test_invalid_configuration);
    printf("%u tests passed\n",tests);
    return 0;
}
