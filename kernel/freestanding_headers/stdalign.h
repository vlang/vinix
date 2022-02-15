#ifndef __STDALIGN_H__
#define __STDALIGN_H__

#define alignas(a) _Alignas(a)
#define alignof(t) _Alignof(t)

#define __alignas_is_defined 1
#define __alignof_is_defined 1

#endif
