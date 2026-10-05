/* Each process starts with the production bridge's original fixed globals. */
#include <sys/wait.h>
#include "expected.h"
/* The mock declarations above consumed unistd.h before names were restored. */
int close(int);
ssize_t read(int, void *, size_t);
int main(void) {
    setvbuf(stdout,NULL,_IONBF,0); setvbuf(stderr,NULL,_IONBF,0);
    for (int scenario=0;scenario<6;scenario++) {
        int channel[2]; assert(pipe(channel)==0);
        pid_t child=fork(); assert(child>=0);
        if(child==0) {
            close(channel[0]); assert(dup2(channel[1],STDOUT_FILENO)>=0); close(channel[1]);
            char value[]={(char)('0'+scenario),0}; char *args[]={"fixture",value,NULL};
            int result=xinput_fixture_main(2,args); fflush(stdout); fflush(stderr); _exit(result);
        }
        close(channel[1]); unsigned char bytes[256]; uint64_t hash=14695981039346656037ull;
        for(;;) { ssize_t n=read(channel[0],bytes,sizeof(bytes)); assert(n>=0); if(n==0) break; for(ssize_t i=0;i<n;i++) hash=(hash^bytes[i])*1099511628211ull; }
        close(channel[0]); int status; assert(waitpid(child,&status,0)==child); assert(WIFEXITED(status)&&WEXITSTATUS(status)==0);
        if(hash!=expected_traces[scenario]) { printf("X11 INPUT FAIL: scenario=%d trace=%llx expected=%llx\n",scenario,(unsigned long long)hash,(unsigned long long)expected_traces[scenario]); _exit(1); }
    }
    puts("X11 INPUT GUEST PASS");
    for(;;) pause();
}
