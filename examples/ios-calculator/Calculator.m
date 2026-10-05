// SPDX-License-Identifier: GPL-2.0-or-later
#import "Calculator.h"

#if __has_include(<stdio.h>)
#include <stdio.h>
#include <stdlib.h>
#else
extern int snprintf(char *, unsigned long, const char *, ...);
extern double strtod(const char *, char **);
#endif

static void copyText(char *destination, const char *source) {
    while ((*destination++ = *source++)) {}
}

@implementation VXCalculator
- (instancetype)init {
    self = [super init];
    if (self) [self clear];
    return self;
}

- (void)clear {
    _value = _accumulator = _repeatRight = 0;
    _pending = _repeatOperation = 0;
    _entering = _operandReady = _repeat = _error = NO;
    _length = 1;
    copyText(_entry, "0");
    copyText(_text, "0");
}

- (double)currentValue {
    return _entering ? strtod(_entry, 0) : _value;
}

- (void)refresh {
    if (_error) copyText(_text, "Error");
    else if (_entering) copyText(_text, _entry);
    else snprintf(_text, sizeof(_text), "%.12g", _value);
}

- (void)setValue:(double)value {
    _value = value;
    _entering = NO;
    _error = !__builtin_isfinite(value);
    if (_error) { _pending = 0; _repeat = NO; }
    [self refresh];
}

- (double)calculateLeft:(double)left right:(double)right operation:(int)operation {
    switch (operation) {
        case '+': return left + right;
        case '-': return left - right;
        case '*': return left * right;
        case '/': return right == 0 ? __builtin_nan("") : left / right;
        default: return right;
    }
}

- (void)pressKey:(int)key {
    if (key == 'C') { [self clear]; return; }
    if (_error) {
        if ((key >= '0' && key <= '9') || key == '.' || key == VXCalculatorSignKey) [self clear];
        else return;
    }
    if ((key >= '0' && key <= '9') || key == '.') {
        if (!_entering) { copyText(_entry, "0"); _length = 1; _entering = YES; }
        _operandReady = YES;
        _repeat = NO;
        if (key == '.') {
            for (NSUInteger i = 0; i < _length; i++) if (_entry[i] == '.') return;
        } else {
            if ((_length == 1 && _entry[0] == '0') ||
                (_length == 2 && _entry[0] == '-' && _entry[1] == '0')) {
                _entry[_length - 1] = (char)key;
                [self refresh];
                return;
            }
            int digits = 0;
            for (NSUInteger i = 0; i < _length; i++) if (_entry[i] >= '0' && _entry[i] <= '9') digits++;
            if (digits >= 15) return;
        }
        if (_length < sizeof(_entry) - 2) {
            _entry[_length++] = (char)key;
            _entry[_length] = 0;
        }
        [self refresh];
        return;
    }
    if (key == VXCalculatorSignKey) {
        if (_pending && !_operandReady) { _value = 0; _entering = NO; }
        if (_entering) {
            if (_entry[0] == '-') {
                for (NSUInteger i = 0; i < _length; i++) _entry[i] = _entry[i + 1];
                _length--;
            } else {
                for (NSUInteger i = _length + 1; i > 0; i--) _entry[i] = _entry[i - 1];
                _entry[0] = '-';
                _length++;
            }
        } else {
            _value = -_value;
            if (_value == 0) { copyText(_entry, "-0"); _length = 2; _entering = YES; }
        }
        _operandReady = YES;
        _repeat = NO;
        [self refresh];
        return;
    }
    if (key == '%') {
        double value = [self currentValue] / 100;
        if (_pending == '+' || _pending == '-') value *= _accumulator;
        _operandReady = YES;
        _repeat = NO;
        [self setValue:value];
        return;
    }
    if (key == '+' || key == '-' || key == '*' || key == '/') {
        double value = [self currentValue];
        if (_pending && _operandReady) {
            value = [self calculateLeft:_accumulator right:value operation:_pending];
            [self setValue:value];
            if (_error) return;
        }
        _accumulator = value;
        _pending = key;
        _operandReady = _entering = _repeat = NO;
        [self setValue:value];
        return;
    }
    if (key == '=') {
        double value = [self currentValue];
        if (_pending) {
            _repeatRight = _operandReady ? value : _accumulator;
            _repeatOperation = _pending;
            _repeat = YES;
            value = [self calculateLeft:_accumulator right:_repeatRight operation:_pending];
            _pending = 0;
        } else if (_repeat) {
            value = [self calculateLeft:value right:_repeatRight operation:_repeatOperation];
        }
        _operandReady = YES;
        [self setValue:value];
    }
}

- (const char *)displayText { return _text; }
@end
