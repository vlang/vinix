#ifndef VINIX_VNC_DARWIN_ALIAS_H
#define VINIX_VNC_DARWIN_ALIAS_H
/* Declaration-only SDK boundary: Darwin x86 annotates select with $1050. */
#if defined(__APPLE__) && defined(__x86_64__)
int vnf_select(int, fd_set *, void *, void *, void *) __asm__("_vnf_select$1050");
#endif
#endif
