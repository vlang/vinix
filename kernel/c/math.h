#ifndef _MATH_H
#define _MATH_H

// V's float formatting helpers are emitted as `static inline` even under
// `-nofloat`, and they call into libm. The kernel never reaches them, so an
// unreferenced `static inline` is discarded and these never become link errors
// -- but the generated C still has to parse, and with `-target-libc-headers` V
// leaves the declaring to us.

double ceil(double x);
double floor(double x);
double fabs(double x);
double pow(double x, double y);

#endif
