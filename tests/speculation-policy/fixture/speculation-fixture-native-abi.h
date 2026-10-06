/* Native declarations and the platform's assertion entry point. */
#ifndef VINIX_SPECULATION_FIXTURE_NATIVE_ABI_H
#define VINIX_SPECULATION_FIXTURE_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <speculation.h>
#ifdef __APPLE__
#define speculation_fixture_assert_failure(function, line, expression) \
    __assert_rtn(function, "policy.c", line, expression)
#else
#define speculation_fixture_assert_failure(function, line, expression) \
    __assert_fail(expression, "policy.c", line, function)
#endif
#endif
