/* SPDX-License-Identifier: ISC
 * Root-only loader/control utility for the experimental Vinix raw interface.
 * No passphrase in argv, environment, configuration files, or diagnostic logs.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include "brcm_m1.h"
static int tty=-1, changed;
static struct termios saved;
static uint8_t password[64];
static void wipe(void *p,size_t n){volatile uint8_t *q=p;while(n--)*q++=0;}
static void restore(void){if(changed&&tty>=0)(void)tcsetattr(tty,TCSANOW,&saved);changed=0;wipe(password,sizeof(password));}
static void interrupted(int sig){restore();_exit(128+sig);}
static uint32_t le32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint64_t le64(const uint8_t *p){return le32(p)|(uint64_t)le32(p+4)<<32;}
static void put32(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(8*i));}
static void die(const char *what){perror(what);exit(1);}
static void pause_ms(unsigned ms){struct timespec t={(time_t)(ms/1000),(long)(ms%1000)*1000000};while(nanosleep(&t,&t)<0&&errno==EINTR){} }
static void status(int fd,uint8_t out[BW_STATUS_SIZE]){memset(out,0,BW_STATUS_SIZE);if(ioctl(fd,BW_IOCTL_STATUS,out)<0)die("Wi-Fi status");}
static void show(int fd){
    uint8_t s[BW_STATUS_SIZE];status(fd,s);
    static const char *const names[]={"off","chip detected","booting","firmware ready","authenticating","authenticated link","stopped"};
    unsigned st=le32(s);printf("state: %s; error: %d; chip revision: %u; DART error: 0x%08x\n",st<7?names[st]:"invalid",(int32_t)le32(s+4),le32(s+8),le32(s+12));
    printf("MAC: %02x:%02x:%02x:%02x:%02x:%02x\n",s[32],s[33],s[34],s[35],s[36],s[37]);
    printf("module: %.15s; vendor: %.15s; module revision: %.15s; antenna: %.15s; board: %.31s\n",s+40,s+56,s+72,s+104,s+120);
    printf("RX: %llu; TX: %llu; queue drops: %llu\n",(unsigned long long)le64(s+16),(unsigned long long)le64(s+24),(unsigned long long)le64(s+152));
}
static size_t read_password(void){
    tty=open("/dev/tty",O_RDWR|O_CLOEXEC);if(tty<0)tty=dup(STDIN_FILENO);if(tty<0)die("terminal");
    if(tcgetattr(tty,&saved)<0)die("cannot disable password echo");
    struct termios settings=saved;settings.c_lflag&=(tcflag_t)~ECHO;
    if(tcsetattr(tty,TCSANOW,&settings)<0)die("password terminal");changed=1;
    fprintf(stderr,"WPA2 passphrase: ");fflush(stderr);size_t n=0;int too_long=0;
    for(;;){uint8_t c;ssize_t k=read(tty,&c,1);if(k<0&&errno==EINTR)continue;if(k!=1){restore();fprintf(stderr,"\nPassword input failed.\n");exit(1);}if(c=='\r'||c=='\n')break;if(n<sizeof(password))password[n++]=c;else too_long=1;}
    (void)tcsetattr(tty,TCSANOW,&saved);changed=0;close(tty);tty=-1;fprintf(stderr,"\n");
    if(too_long||n<8||n>63){fprintf(stderr,"Use an 8–63 character WPA2 passphrase.\n");exit(1);}return n;
}
static void path_join(char *out,size_t size,const char *dir,const char *name){int n=snprintf(out,size,"%s/%s",dir,name);if(n<0||(size_t)n>=size){errno=ENAMETOOLONG;die("firmware path");}}
static void load(int fd,const char *dir){
    static const char *const names[]={"firmware.bin","nvram.txt","clm.blob","txcap.blob"};
    static const size_t limits[]={4u*1024u*1024u,65536,1024u*1024u,1024u*1024u};
    char path[4096];uint8_t manifest[128];path_join(path,sizeof(path),dir,"manifest.bin");
    FILE *mf=fopen(path,"rb");if(!mf)die("manifest");if(fread(manifest,1,128,mf)!=128||fgetc(mf)!=EOF){fprintf(stderr,"Invalid manifest length.\n");exit(1);}fclose(mf);
    uint8_t current[256];status(fd,current);
    if(le32(current)!=1||le32(manifest)!=le32(current+8)||memcmp(manifest+8,current+40,16)||memcmp(manifest+24,current+56,16)||memcmp(manifest+40,current+72,16)||memcmp(manifest+56,current+104,16)||memcmp(manifest+72,current+120,32)){fprintf(stderr,"Manifest does not match the detected chip/board/module; refusing upload.\n");exit(1);}
    /* Validate all four files before changing the kernel's one-shot upload. */
    FILE *files[4];uint32_t totals[4];
    for(unsigned i=0;i<4;i++){path_join(path,sizeof(path),dir,names[i]);files[i]=fopen(path,"rb");if(!files[i])die(names[i]);struct stat st;if(fstat(fileno(files[i]),&st)<0)die("firmware stat");if(!S_ISREG(st.st_mode)||st.st_size<=0||(uint64_t)st.st_size>limits[i]){fprintf(stderr,"Invalid size for %s.\n",names[i]);exit(1);}totals[i]=(uint32_t)st.st_size;}
    for(unsigned i=0;i<4;i++){
        uint8_t chunk[BW_UPLOAD_SIZE];uint32_t off=0;
        while(off<totals[i]){memset(chunk,0,sizeof(chunk));uint32_t n=totals[i]-off;if(n>4096)n=4096;put32(chunk,i);put32(chunk+4,totals[i]);put32(chunk+8,off);put32(chunk+12,n);
            if(fread(chunk+16,1,n,files[i])!=n)die("firmware read");if(ioctl(fd,BW_IOCTL_UPLOAD,chunk)<0)die("firmware upload");off+=n;
        }
        if(fgetc(files[i])!=EOF){fprintf(stderr,"Firmware changed during upload; reboot before retrying.\n");exit(1);}fclose(files[i]);
    }
    if(ioctl(fd,BW_IOCTL_BOOT,manifest)<0)die("firmware boot");show(fd);
}
int main(int argc,char **argv){
    atexit(restore);signal(SIGINT,interrupted);signal(SIGTERM,interrupted);signal(SIGHUP,interrupted);
    if(argc<2){fprintf(stderr,"Usage: %s status | status-raw FILE | load DIRECTORY | join SSID | stop\n",argv[0]);return 2;}
    int fd=open("/dev/wlan0",O_RDWR|O_NONBLOCK|O_CLOEXEC);if(fd<0)die("/dev/wlan0 (requires vinix.apple_wifi=1 and a supported J313 DT)");
    if(!strcmp(argv[1],"status")&&argc==2)show(fd);
    else if(!strcmp(argv[1],"status-raw")&&argc==3){uint8_t s[256];status(fd,s);FILE *out=fopen(argv[2],"wb");if(!out)die("status output");if(fwrite(s,1,sizeof(s),out)!=sizeof(s)||fclose(out))die("status write");}
    else if(!strcmp(argv[1],"load")&&argc==3)load(fd,argv[2]);
    else if(!strcmp(argv[1],"join")&&argc==3){
        size_t sn=strlen(argv[2]);if(!sn||sn>32){fprintf(stderr,"SSID must contain 1–32 bytes.\n");return 2;}
        size_t pn=read_password();uint8_t q[BW_JOIN_SIZE]={0};put32(q,(uint32_t)sn);put32(q+4,(uint32_t)pn);memcpy(q+8,argv[2],sn);memcpy(q+40,password,pn);
        int rc=ioctl(fd,BW_IOCTL_JOIN,q);int error=errno;wipe(q,sizeof(q));wipe(password,sizeof(password));errno=error;if(rc<0)die("WPA2 join");
        for(unsigned i=0;i<310;i++){uint8_t s[256];status(fd,s);if(le32(s)==5){show(fd);printf("Layer-2 link authenticated. This driver does not provide an IP stack.\n");close(fd);return 0;}if(le32(s)==6){show(fd);close(fd);return 1;}pause_ms(100);}fprintf(stderr,"Authentication deadline exceeded.\n");close(fd);return 1;
    }else if(!strcmp(argv[1],"stop")&&argc==2){if(ioctl(fd,BW_IOCTL_STOP,0)<0)die("stop");show(fd);}
    else{fprintf(stderr,"Unknown command or argument count.\n");close(fd);return 2;}
    close(fd);return 0;
}
