/* SPDX-License-Identifier: ISC */
/* Run the same independent device fixture in native target processes. */
#define main wifi_fixture_main
#include "ctl_fixture.c"
#undef main
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static void bundle_file(const char *name, size_t size, unsigned char value) {
    char path[128]; snprintf(path,sizeof(path),"/tmp/wifi-ctl-fixture/%s",name);
    FILE *file=fopen(path,"wb"); assert(file);
    for(size_t i=0;i<size;i++) assert(fputc(value,file)!=EOF);
    assert(!fclose(file));
}
static void scenario(const char *name, int expected) {
    fflush(NULL);
    pid_t child=fork(); assert(child>=0);
    if(!child) {
        char *args[]={"fixture",(char *)name,"/tmp/wifi-ctl-fixture",NULL};
        int result=wifi_fixture_main(!strncmp(name,"load",4)?3:2,args);
        exit(result);
    }
    int status; assert(waitpid(child,&status,0)==child);
    assert(WIFEXITED(status)&&WEXITSTATUS(status)==expected);
}
int main(void) {
    const char *cases[]={"status","on","off","networks","invalid","scan","join","join-timeout","stop"};
    for(size_t i=0;i<sizeof(cases)/sizeof(cases[0]);i++)scenario(cases[i],0);
    assert(!mkdir("/tmp/wifi-ctl-fixture",0700));
    bundle_file("manifest.bin",128,0);
    FILE *manifest=fopen("/tmp/wifi-ctl-fixture/manifest.bin","r+b");assert(manifest);
    assert(fputc(3,manifest)!=EOF);assert(!fclose(manifest));
    const char *names[]={"firmware.bin","nvram.txt","clm.blob","txcap.blob"};
    for(unsigned i=0;i<4;i++)bundle_file(names[i],i?100:5000,(unsigned char)(i+1));
    scenario("load",0);bundle_file("txcap.blob",0,0);scenario("load-bad",1);
    puts("VINIX_WIFI_CTL_VM_PASS");fflush(stdout);
    for(;;)pause();
}
