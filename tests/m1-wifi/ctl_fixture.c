/* SPDX-License-Identifier: ISC */
/* Independent native device fixture: production C and V use identical hooks. */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include "brcm_m1.h"
extern int test_program_main(int,char **);
static unsigned sleeps,queries,uploads;
static const char *mode;
static const uint8_t *join_request;
static int tty_restored;
static void verify_exit(void) { if(!strcmp(mode,"load-bad")) { assert(!uploads); puts("Wi-Fi pre-upload fixture: PASS"); } }
static uint32_t le32(const uint8_t *p) { return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static void put32(uint8_t *p,uint32_t v) { for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8)); }
int test_open(const char *path,int flags,...) { (void)flags;assert(!strcmp(path,"/dev/wlan0")||!strcmp(path,"/dev/tty"));return !strcmp(path,"/dev/wlan0")?100:101; }
int test_close(int fd) { assert(fd==100||fd==101);return 0; }
ssize_t test_read(int fd,void *buf,size_t size) { static unsigned at;static const char input[]="passphrase\n";assert(fd==101&&size==1);*(uint8_t *)buf=(uint8_t)input[at++];return 1; }
int test_tcgetattr(int fd,struct termios *state) { assert(fd==101);memset(state,0,sizeof(*state));state->c_lflag=ECHO;return 0; }
int test_tcsetattr(int fd,int action,const struct termios *state) { assert(fd==101&&action==TCSANOW);if(state->c_lflag&ECHO)tty_restored++;return 0; }
int test_nanosleep(const struct timespec *time,struct timespec *remaining) { (void)remaining;assert(time->tv_sec==0&&time->tv_nsec==100000000);sleeps++;return 0; }
int test_ioctl(int fd,unsigned long request,...) {
    va_list args;va_start(args,request);uint8_t *out=va_arg(args,uint8_t *);va_end(args);assert(fd==100);
    if(request==BW_IOCTL_STATUS) {
        if(join_request)for(unsigned i=0;i<BW_JOIN_SIZE;i++)assert(!join_request[i]);
        memset(out,0,BW_STATUS_SIZE);put32(out,!strcmp(mode,"join-timeout")?4:join_request?5:1);put32(out+8,3);return 0;
    }
    if(request==BW_IOCTL_NETWORKS) {
        queries++;memset(out,0,BW_NETWORKS_SIZE);put32(out,1);put32(out+4,1);
        if(!strcmp(mode,"scan"))put32(out+8,1);
        out[16]=4;out[17]=1;out[18]=6;out[20]=0xd6;out[21]=0xff;memcpy(out+32,"test",4);
        if(!strcmp(mode,"invalid"))out[18]=234;
        return 0;
    }
    if(request==BW_IOCTL_JOIN) { assert(le32(out)==4&&le32(out+4)==10&&!memcmp(out+8,"test",4)&&!memcmp(out+40,"passphrase",10));join_request=out;return 0; }
    if(request==BW_IOCTL_RADIO) { assert(le32(out)==(!strcmp(mode,"on")?1u:0u));return 0; }
    if(request==BW_IOCTL_SCAN||request==BW_IOCTL_STOP)return 0;
    if(request==BW_IOCTL_UPLOAD) { uploads++;unsigned part=le32(out),offset=le32(out+8),n=le32(out+12);assert(part<4&&n<=4096);for(unsigned i=0;i<n;i++)assert(out[16+i]==(uint8_t)(part+1));assert(offset%4096==0);return 0; }
    if(request==BW_IOCTL_BOOT)return 0;
    assert(!"unexpected ioctl");return -1;
}
int main(int argc,char **argv) {
    assert(argc==2||argc==3);mode=argv[1];atexit(verify_exit);char *command=(char *)mode;char *args[]={"wifi-ctl",command,"test",NULL};int count=2;
    if(!strcmp(mode,"invalid"))args[1]="networks";
    if(!strncmp(mode,"load",4)) { assert(argc==3);args[1]="load";args[2]=argv[2];count=3; }
    if(!strcmp(mode,"join")||!strcmp(mode,"join-timeout")){args[1]="join";count=3;}
    int result=test_program_main(count,args);
    if(!strcmp(mode,"invalid"))assert(result==1);
    else if(!strcmp(mode,"join-timeout")){assert(result==1&&sleeps==310&&tty_restored==1);}
    else { assert(result==0); }
    if(!strcmp(mode,"scan"))assert(queries==161&&sleeps==160);
    if(!strcmp(mode,"join"))assert(join_request&&tty_restored==1);
    assert(uploads==(!strcmp(mode,"load")?5u:0u));puts("Wi-Fi control fixture: PASS");return 0;
}
