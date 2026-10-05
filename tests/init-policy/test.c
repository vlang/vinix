/* SPDX-License-Identifier: GPL-2.0-only */
/* Independent raw-syscall fixture: the production policy calls no host syscall. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
struct delay { int64_t seconds, nanoseconds; };
struct action { void (*handler)(int); uint64_t flags; void (*restorer)(void); uint64_t mask; };
void vinix_init_shell(void), vinix_init_full(void);
void vinix_init_power_signal(int), vinix_init_child_signal(int);
void initcore__prepare_desktop_boot(void), initcore__prepare_hosted_x11_storage(void);
void initcore__install_power_signals(void), initcore__apply_power_request(void);
void initcore__pause_for(struct delay), initcore__wait_for_child(int64_t,int32_t *);
void initcore__stop_desktop_group(int64_t);
int64_t initcore__spawn_program(char **,char **,bool,int32_t *,char **,bool);
extern volatile int32_t vinit_power, vinit_reload;
struct record { uint64_t nr,a[5]; char path[160], other[160]; };
static struct record calls[4096];
static size_t used, output_used, read_at, waits, sleeps, probes;
static char output[32768];
static const char *const *lines;
static jmp_buf finished;
static int mode, exit_status, symlink_failure, link_failure, mount_failure;
static int64_t cloned;
static bool stop_sleep, full_echo;
enum { BASIC, SHELL, FULL, WAIT, RELOAD, SLEEP, SPAWN, GROUP };
static void reset(int next) {
    used=output_used=read_at=waits=sleeps=probes=0;
    output[0]=0; mode=next; exit_status=-1; symlink_failure=link_failure=mount_failure=0;
    cloned=77; stop_sleep=false; vinit_power=vinit_reload=0;
}
static void text_copy(char *out,uint64_t ptr) {
    assert(ptr); const char *s=(const char *)(uintptr_t)ptr;
    assert(strlen(s)<160); strcpy(out,s);
}
int64_t vinit_syscall(uint64_t nr,uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,uint64_t a4) {
    assert(used<4096); struct record *r=&calls[used++];
    *r=(struct record){.nr=nr,.a={a0,a1,a2,a3,a4}};
    if(nr==64) {
        assert(a0==1 && output_used+a2<sizeof(output));
        memcpy(output+output_used,(void *)(uintptr_t)a1,(size_t)a2);
        output_used+=(size_t)a2; output[output_used]=0; return (int64_t)a2;
    }
    if(nr==63) {
        assert(mode==SHELL && a0==0 && a2==255);
        const char *line=lines[read_at++]; if(!line) return 0;
        assert(strlen(line)<=a2); memcpy((void *)(uintptr_t)a1,line,strlen(line)); return (int64_t)strlen(line);
    }
    if(nr==93) { exit_status=(int)a0; longjmp(finished,1); }
    if(nr==56) {
        assert(a0==(uint64_t)(int64_t)-100); text_copy(r->path,a1);
        if(a2==0x41) { assert(a3==0600); return 9; }
        return 8;
    }
    if(nr==57) { assert(a0==8 || a0==9); return 0; }
    if(nr==35 || nr==34) {
        assert(a0==(uint64_t)(int64_t)-100); text_copy(r->path,a1);
        if(nr==34) assert(a2==0700);
        return 0;
    }
    if(nr==36) { text_copy(r->path,a0); text_copy(r->other,a2); assert(a1==(uint64_t)(int64_t)-100); return strstr(r->other,"activity") && symlink_failure ? -5:0; }
    if(nr==37 || nr==38) {
        assert(a0==(uint64_t)(int64_t)-100 && a2==(uint64_t)(int64_t)-100);
        text_copy(r->path,a1); text_copy(r->other,a3); return nr==37 && link_failure ? -5:0;
    }
    if(nr==40) { text_copy(r->path,a0); text_copy(r->other,a1); assert(!strcmp((char *)(uintptr_t)a2,"tmpfs")); assert(!a3 && !a4); return mount_failure?-5:0; }
    if(nr==134) {
        assert(!a2 && a3==8); struct action *action=(void *)(uintptr_t)a1;
        assert(!action->flags && !action->mask && action->restorer);
        assert(action->handler==(a0==17 ? vinix_init_child_signal:vinix_init_power_signal)); return 0;
    }
    if(nr==81) { assert(!a0); return 0; }
    if(nr==142) { assert(a0==0xfee1dead && a1==0x28121969 && !a3); return -1; }
    if(nr==115) {
        assert(a0==1 && !a1 && a2==a3); struct delay *d=(void *)(uintptr_t)a2; sleeps++;
        if(mode==SLEEP && sleeps<3) { d->seconds=0; d->nanoseconds=1000/(int64_t)sleeps; if(stop_sleep) vinit_reload=1; return -4; }
        if(mode==SLEEP) assert(d->seconds==0 && d->nanoseconds==500);
        else assert(d->seconds==0 && d->nanoseconds==10000000);
        return 0;
    }
    if(nr==220) { assert(a0==17 && !a1 && !a2 && !a3 && !a4); return cloned; }
    if(nr==154) { assert((!a0 && !a1)||(a0==77 && a1==77)); return 0; }
    if(nr==221) {
        text_copy(r->path,a0); char **arguments=(void *)(uintptr_t)a1; char **environment=(void *)(uintptr_t)a2;
        assert(!strcmp(arguments[0],r->path)); assert(environment && !strcmp(environment[0],"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"));
        if(mode==FULL) {
            assert(!strcmp(r->path,"/bin/busybox"));
            assert(!strcmp(arguments[1],full_echo?"echo":"sh"));
            assert(!strcmp(arguments[2],full_echo?"VINIX BUSYBOX EXEC TEST: PASS":"/etc/vinix-boot-test.sh") && !arguments[3]);
            assert(!strcmp(environment[1],"HOME=/root") && !strcmp(environment[2],"TERM=linux") && !strcmp(environment[3],"PS1=vinix# "));
            assert(!strcmp(environment[4],"LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules"));
            assert(!strcmp(environment[5],"LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri") && !environment[6]);
        } else assert(mode==SPAWN && !arguments[1] && !environment[1]);
        return -2;
    }
    if(nr==260) {
        assert(a0==(uint64_t)(int64_t)-1 && !a3); waits++;
        if(a2==1) return 0;
        assert(!a2 && (mode==WAIT || mode==RELOAD || mode==SPAWN));
        if(mode==SPAWN) { *(int32_t *)(uintptr_t)a1=4<<8; return 77; }
        if(waits==1) { *(int32_t *)(uintptr_t)a1=0; return 101; }
        if(waits==2) { if(mode==WAIT) vinit_power=12; return -4; }
        assert(waits==3); *(int32_t *)(uintptr_t)a1=11; return 77;
    }
    if(nr==129) {
        if(mode==GROUP && a1==0) return ++probes>100?-3:0;
        assert((mode==GROUP && (int64_t)a0==-77)||(a0==77 && (mode==WAIT || mode==RELOAD)));
        return 0;
    }
    assert(!"unexpected syscall"); return -1;
}
static size_t count(uint64_t nr) { size_t n=0;for(size_t i=0;i<used;i++) n+=calls[i].nr==nr; return n; }
static struct record *number(uint64_t nr,size_t at) { for(size_t i=0;i<used;i++) if(calls[i].nr==nr && !at--) return &calls[i]; assert(!"missing syscall");return 0; }
static void shell_test(void) {
    static const char *const input[]={" \t\r\n","help\n","hello\r\n","uname\n","echo   hello world\n","echo\n","echoes\n","missing\n","exit\n",0};
    reset(SHELL); lines=input; if(!setjmp(finished)) vinix_init_shell();
    assert(exit_status==0 && read_at==9);
    assert(strstr(output," | | | | | '_ \\| \\ \\/ /\n"));
    assert(strstr(output,"Type 'help' for available commands.\n\nvinix# vinix# Available commands:\n"));
    assert(strstr(output,"  exit   - exit shell\nvinix# Hello from userland!\nvinix# Vinix 0.1.0 aarch64\nvinix# hello world\nvinix# \nvinix# unknown command: echoes\nvinix# unknown command: missing\nvinix# Goodbye!\n"));
    static const char *const eof[]={0}; reset(SHELL); lines=eof; if(!setjmp(finished)) vinix_init_shell();
    assert(exit_status==1 && strstr(output,"read error or EOF, exiting\n"));
}
static void full_test(void) {
    reset(FULL); if(!setjmp(finished)) vinix_init_full();
    assert(exit_status==1 && count(221)==1);
    assert(!strcmp(output,"\nVinix ARM64 test userland: starting boot tests\ninit: execve /bin/sh failed\n"));
}
static void boot_test(void) {
    reset(BASIC); initcore__prepare_desktop_boot();
    assert(used==20 && count(35)==10 && count(36)==3 && count(38)==4 && count(37)==1);
    assert(!strcmp(calls[0].path,"/run/vinix-desktop-development") && !strcmp(calls[2].path,"/run/vinix-latest-release"));
    assert(!strcmp(number(36,0)->path,"vinix-desktop") && !strcmp(number(36,2)->other,"/usr/bin/.vinix-settings.system"));
    assert(!strcmp(number(38,3)->other,"/usr/bin/vinix-desktop"));
    reset(BASIC); symlink_failure=link_failure=1; initcore__prepare_desktop_boot();
    assert(count(38)==2 && count(37)==1 && count(35)==11 && strstr(output,"could not restore the packaged desktop"));
    reset(BASIC); initcore__prepare_hosted_x11_storage();
    assert(used==4 && calls[0].nr==34 && calls[1].nr==40 && calls[2].nr==56 && calls[3].nr==57);
    reset(BASIC); mount_failure=1; initcore__prepare_hosted_x11_storage();
    assert(count(56)==0 && strstr(output,"scratch mount unavailable; using /tmp"));
}
static void signal_test(void) {
    reset(BASIC); initcore__install_power_signals();
    static const uint64_t signals[]={1,15,10,12,17}; assert(used==5);
    for(size_t i=0;i<5;i++) assert(calls[i].nr==134 && calls[i].a[0]==signals[i]);
    vinix_init_power_signal(1); assert(vinit_reload==1 && !vinit_power);
    vinix_init_power_signal(15); assert(vinit_reload==1 && vinit_power==15);
    vinix_init_child_signal(17); assert(vinit_reload==1 && vinit_power==15);
    static const uint64_t power[]={15,10,12},commands[]={0x01234567,0xcdef0123,0x4321fedc};
    for(size_t i=0;i<3;i++) { reset(BASIC); vinix_init_power_signal((int)power[i]); initcore__apply_power_request(); assert(calls[0].nr==81 && calls[1].nr==142 && calls[1].a[2]==commands[i] && !vinit_power); }
    reset(WAIT); vinit_power=15; int32_t status=-1; initcore__wait_for_child(77,&status);
    assert(status==11 && waits==3 && count(129)==2 && number(129,0)->a[1]==15 && number(129,1)->a[1]==12);
    reset(RELOAD); vinit_reload=1; initcore__wait_for_child(77,&status);
    assert(status==11 && waits==3 && count(129)==1 && number(129,0)->a[1]==1);
    reset(SLEEP); initcore__pause_for((struct delay){1,0}); assert(sleeps==3);
    reset(SLEEP); stop_sleep=true; initcore__pause_for((struct delay){1,0}); assert(sleeps==1 && vinit_reload==1);
}
static void process_test(void) {
    char *arguments[]={"/usr/bin/vinix-desktop-gpu",0},*fallback[]={"/usr/bin/vinix-desktop",0};
    char *environment[]={"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",0}; int32_t status=0;
    reset(SPAWN); assert(initcore__spawn_program(arguments,fallback,true,&status,environment,true)==77);
    assert(status==4<<8 && count(154)==1 && count(260)==1 && !output_used);
    reset(SPAWN); cloned=0; if(!setjmp(finished)) initcore__spawn_program(arguments,fallback,true,&status,environment,true);
    assert(exit_status==127 && count(221)==2 && count(154)==1);
    assert(!strcmp(number(221,0)->path,arguments[0]) && !strcmp(number(221,1)->path,fallback[0]));
    assert(!strcmp(output,"init: GPU desktop child process group ready; entering execve\ninit: GPU desktop execve returned; trying software fallback\ninit: GPU and software desktop execve both failed\n"));
    reset(SPAWN); cloned=-12; assert(initcore__spawn_program(arguments,0,false,&status,environment,false)==-12 && used==1);
    reset(GROUP); initcore__stop_desktop_group(77);
    assert(probes==101 && sleeps==100 && count(260)==102 && count(129)==103);
    assert(number(129,0)->a[1]==15 && number(129,101)->a[1]==9 && !output_used);
}
int main(int argc,char **argv) {
    full_echo=argc>1 && !strcmp(argv[1],"echo");
    shell_test();full_test();boot_test();signal_test();process_test();
    puts("INIT POLICY TEST: PASS");return 0;
}
