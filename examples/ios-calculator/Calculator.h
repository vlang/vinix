// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#if __has_include(<Foundation/Foundation.h>) && !defined(VINIX_MINIMAL_FOUNDATION)
#import <Foundation/Foundation.h>
#else
#import "api/Foundation.h"
#endif

enum { VXCalculatorSignKey = 256 };

@interface VXCalculator : NSObject {
    char _entry[32], _text[64];
    NSUInteger _length;
    double _value, _accumulator, _repeatRight;
    int _pending, _repeatOperation;
    BOOL _entering, _operandReady, _repeat, _error;
}
- (void)pressKey:(int)key;
- (const char *)displayText;
@end
