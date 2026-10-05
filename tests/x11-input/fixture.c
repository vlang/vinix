/* Independent XTEST trace fixture: events cover the original C bridge policy. */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

int xinput_bridge_main(void);
static int scenario, attempts, delays, pointer_index;
static void (*stop_handler)(int);
static unsigned char keys[1024];
static size_t key_count, key_index;
static Screen screen;
static _XPrivDisplay display;
static struct termios original;
struct packet { int32_t x,y,max_x,max_y; uint32_t buttons,pressed,released; int32_t scroll; };

int vxi_test_sigaction(int sig, const struct vxi_test_sigaction *action, struct vxi_test_sigaction *old) {
    (void)sig; (void)old; stop_handler=action->sa_handler; return 0;
}
int vxi_test_open(const char *name, int flags, ...) {
    assert(flags == (O_RDONLY|O_NONBLOCK));
    printf("open %s\n", name);
    if (scenario == 5) { errno=ENOENT; return -1; }
    return !strcmp(name,"/dev/console") ? 3 : 4;
}
int vxi_test_close(int fd) { printf("close %d\n",fd); return 0; }
int vxi_test_tcgetattr(int fd, struct termios *out) { assert(fd==3); *out=original; return 0; }
int vxi_test_tcsetattr(int fd,int mode,const struct termios *raw) {
    assert(fd==3 && mode==TCSANOW);
    if (!memcmp(raw,&original,sizeof(original))) puts("restore");
    else {
        assert(!(raw->c_iflag&(BRKINT|ICRNL|INPCK|ISTRIP|IXON)));
        assert(!(raw->c_oflag&OPOST) && (raw->c_cflag&CS8));
        assert(!(raw->c_lflag&(ECHO|ICANON|IEXTEN|ISIG)));
        assert(raw->c_cc[VMIN]==0 && raw->c_cc[VTIME]==0); puts("raw");
    }
    return 0;
}
ssize_t vxi_test_read(int fd,void *buffer,size_t cap) {
    if(fd==3) {
        if(key_index==key_count) return -1;
        size_t count=scenario==1 ? 1 : key_count-key_index;
        if(count>cap) count=cap;
        memcpy(buffer,keys+key_index,count); key_index+=count; return count;
    }
    assert(fd==4 && cap==sizeof(struct packet));
    if(scenario!=2 || pointer_index==192) return -1;
    unsigned i=(unsigned)pointer_index++;
    static const int positions[]={-100,0,50,100,200};
    static const int scroll[]={-33,-1,0,1,33};
    struct packet p={positions[i%5],positions[(i/5)%5],100,100,
                     i&7,(i/8)&7,(i/64)&7,scroll[(i/32)%5]};
    if(i==191) p.max_x=0;
    memcpy(buffer,&p,sizeof(p)); return sizeof(p);
}
int vxi_test_nanosleep(const struct timespec *delay,struct timespec *remaining) {
    (void)remaining; assert(delay->tv_sec==0 && delay->tv_nsec==10000000); delays++;
    if(scenario!=3 && delays>3 && key_index==key_count && (scenario!=2 || pointer_index==192)) stop_handler(SIGTERM);
    return 0;
}
Display *XOpenDisplay(const char *name) { assert(name==NULL); attempts++; if(scenario==3 || attempts<3) return NULL; return (Display *)display; }
int XCloseDisplay(Display *d) { assert(d==(Display *)display); puts("display-close"); return 0; }
XErrorHandler XSetErrorHandler(XErrorHandler handler) {
    XErrorEvent event={0}; event.error_code=9; event.request_code=8; event.minor_code=7;
    assert(handler((Display *)display,&event)==0); return NULL;
}
int XGetErrorText(Display *d,int code,char *buffer,int cap) { (void)d; assert(code==9 && cap==128); strcpy(buffer,"fixture error"); return 0; }
Bool XTestQueryExtension(Display *d,int *event,int *error,int *major,int *minor) { (void)d; *event=*error=*major=*minor=0; return scenario!=4; }
KeyCode XKeysymToKeycode(Display *d,KeySym symbol) { (void)d; printf("key %lu\n",symbol); return (KeyCode)(symbol%254+1); }
int XTestFakeKeyEvent(Display *d,unsigned code,Bool down,unsigned long delay) { (void)d; assert(delay==0); printf("keyevent %u %d\n",code,down); return 1; }
int XTestFakeButtonEvent(Display *d,unsigned button,Bool down,unsigned long delay) { (void)d; assert(delay==0); printf("button %u %d\n",button,down); return 1; }
Bool XQueryPointer(Display *d,Window root,Window *rr,Window *child,int *rx,int *ry,int *wx,int *wy,unsigned *mask) { (void)d; assert(root==42); *rr=root; *child=77; *rx=*ry=*wx=*wy=0; *mask=0; return True; }
int XSetInputFocus(Display *d,Window child,int revert,Time time) { (void)d; assert(child==77 && revert==RevertToPointerRoot && time==0); puts("focus"); return 0; }
int XWarpPointer(Display *d,Window src,Window dest,int sx,int sy,unsigned sw,unsigned sh,int x,int y) { (void)d; assert(src==0 && dest==42 && sx==0 && sy==0 && sw==0 && sh==0); printf("warp %d %d\n",x,y); return 0; }
int XFlush(Display *d) { (void)d; puts("flush"); return 0; }
int main(int argc,char **argv) {
    assert(argc==2); scenario=atoi(argv[1]);
    display=calloc(1,sizeof(*display)); assert(display); display->screens=&screen; screen.root=42; screen.width=100; screen.height=80;
    original.c_iflag=BRKINT|ICRNL|INPCK|ISTRIP|IXON;
    original.c_oflag=OPOST; original.c_lflag=ECHO|ICANON|IEXTEN|ISIG;
    if(scenario==0) { for(unsigned i=0;i<256;i++) keys[key_count++]=(unsigned char)i; }
    if(scenario==1) {
        static const unsigned char sequences[]="\033[A\033[B\033[C\033[D\033[H\033[F\033OP\033OQ\033OR\033OS\033OA\033OB\033OC\033OD\033OH\033OF\033[1~\033[2~\033[3~\033[4~\033[5~\033[6~\033[7~\033[8~\033[9~\033[12~\033X\033[1234567890123456\033";
        memcpy(keys,sequences,sizeof(sequences)-1); key_count=sizeof(sequences)-1;
    }
    int result=xinput_bridge_main();
    assert(result==((scenario==3||scenario==4)?1:0));
    printf("done %d %d\n",attempts,delays);
    free(display); return 0;
}
