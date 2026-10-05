/* SPDX-License-Identifier: GPL-2.0-only */
/* Native applications exercise the installed init's process and exec policy. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
static void fail(const char *message) { printf("INIT GUEST FAIL: %s errno=%d\n",message,errno);fflush(stdout);for(;;) pause(); }
static void require(int value,const char *message) { if(!value) fail(message); }
#if defined(INIT_SHELL_DRIVER)
int main(void) {
    int input[2]; require(pipe(input)==0,"shell pipe");
    pid_t writer=fork(); require(writer>=0,"shell writer");
    if(writer==0) {
        close(input[0]); usleep(100000);
        static const char *lines[]={"hello\n","uname\n","echo SHELL INIT GUEST: PASS\n"};
        for(size_t i=0;i<sizeof(lines)/sizeof(lines[0]);i++) { require(write(input[1],lines[i],strlen(lines[i]))==(ssize_t)strlen(lines[i]),"shell input");usleep(100000); }
        for(;;) pause();
    }
    close(input[1]);require(dup2(input[0],0)==0,"shell stdin");if(input[0]) close(input[0]);
    char *args[]={"/shell-init",NULL};execv(args[0],args);fail("shell exec");return 1;
}
#elif defined(INIT_FULL_PROGRAM)
int main(int argc,char **argv) {
    require(getpid()==1 && argc==3,"full PID1 argv");
    require(!strcmp(argv[0],"/bin/busybox") && !strcmp(argv[1],"sh") && !strcmp(argv[2],"/etc/vinix-boot-test.sh"),"full command");
    require(!strcmp(getenv("PATH"),"/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin") && !strcmp(getenv("HOME"),"/root") && !strcmp(getenv("TERM"),"linux"),"full environment");
    require(fcntl(0,F_GETFD)>=0 && fcntl(1,F_GETFD)>=0 && fcntl(2,F_GETFD)>=0,"full console descriptors");
    puts("FULL INIT GUEST: PASS");fflush(stdout);for(;;) pause();
}
#else
static volatile sig_atomic_t reloaded;
static void reload(int signo) { reloaded=signo; }
static void closing(int signo) {
    (void)signo;int fd=open("/run/child-closed",O_WRONLY|O_CREAT|O_TRUNC,0600);
    if(fd>=0) { char byte='1';write(fd,&byte,1);close(fd); }
    _exit(0);
}
static void phase_write(int phase) {
    int fd=open("/run/init-phase",O_WRONLY|O_CREAT|O_TRUNC,0600);require(fd>=0,"phase open");
    char byte=(char)('0'+phase);require(write(fd,&byte,1)==1,"phase write");close(fd);
}
int main(int argc,char **argv) {
    setvbuf(stdout,NULL,_IONBF,0);
    require(argc==1 && !strcmp(argv[0],"/usr/bin/vinix-desktop"),"desktop args");
    require(getppid()==1 && getpgrp()==getpid(),"desktop owner/group");
    require(getenv("VINIX_SYSTEM_SESSION") && !strcmp(getenv("VINIX_SYSTEM_SESSION"),"1"),"desktop environment");
    require(fcntl(0,F_GETFD)>=0 && fcntl(1,F_GETFD)>=0 && fcntl(2,F_GETFD)>=0,"desktop console descriptors");
    int fd=open("/run/init-phase",O_RDONLY);char byte='0';if(fd>=0) { require(read(fd,&byte,1)==1,"phase read");close(fd); }
    if(byte=='0') {
        require(signal(SIGHUP,reload)!=SIG_ERR,"reload handler");phase_write(1);
        require(kill(1,SIGHUP)==0,"reload request");while(!reloaded) pause();require(reloaded==SIGHUP,"reload forwarded");
        puts("DESKTOP RELOAD FORWARDED: PASS");return 0;
    }
    if(byte=='1') {
        puts("DESKTOP RESTART: PASS");phase_write(2);
        int ready[2];require(pipe(ready)==0,"orphan gate");pid_t child=fork();require(child>=0,"desktop child");
        if(child==0) {
            close(ready[0]);require(signal(SIGTERM,closing)!=SIG_ERR,"child signal");
            char mark='1';write(ready[1],&mark,1);close(ready[1]);for(;;) pause();
        }
        close(ready[1]);require(read(ready[0],&byte,1)==1,"child ready");close(ready[0]);
        fd=open("/run/child-pid",O_WRONLY|O_CREAT|O_TRUNC,0600);require(fd>=0,"child pid open");
        require(write(fd,&child,sizeof(child))==sizeof(child),"child pid write");close(fd);
        require(kill(getpid(),SIGTERM)==0,"desktop signal exit");for(;;) pause();
    }
    require(byte=='2',"desktop restart phase");
    fd=open("/run/child-closed",O_RDONLY);require(fd>=0,"orphan group terminated");close(fd);
    fd=open("/run/child-pid",O_RDONLY);require(fd>=0,"orphan pid open");pid_t child;
    require(read(fd,&child,sizeof(child))==sizeof(child),"orphan pid read");close(fd);
    errno=0;require(kill(child,0)<0 && errno==ESRCH,"orphan reaped before restart");
    puts("DESKTOP INIT GUEST: PASS");for(;;) pause();
}
#endif
