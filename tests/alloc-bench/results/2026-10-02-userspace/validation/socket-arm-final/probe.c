#define main original_core_main
#include "/Users/alex/code/vinix/build/useralloc-arm-core-v3/test.c"
#undef main
static void slab(const char *phase) {
 char buffer[4096]; int fd=open("/proc/slabinfo",O_RDONLY);
 printf("ARM-SOCKET-SLAB-BEGIN phase=%s\n",phase);
 if(fd>=0) { ssize_t n; while((n=read(fd,buffer,sizeof buffer))>0) fwrite(buffer,1,n,stdout); close(fd); }
 printf("ARM-SOCKET-SLAB-END phase=%s\n",phase);
}
int main(void) {
 setbuf(stdout,NULL);setbuf(stderr,NULL);
 int fd=open("/dev/console",O_WRONLY);if(fd>=0){dup2(fd,1);dup2(fd,2);close(fd);}
 mount("proc","/proc","proc",0,NULL);alarm(120);
 struct sysinfo before,after; slab("before");sysinfo(&before);
 puts("ARM-SOCKET-BEGIN calls=65536");int result=test_socket_interface_box_reclamation();
 sysinfo(&after);printf("ARM-SOCKET-MEMORY before=%lu after=%lu retained=%ld\n",before.freeram,after.freeram,(long)(before.freeram-after.freeram));slab("after");
 printf("ARM-SOCKET-DONE result=%d\n",result);for(;;)sleep(1);
}
