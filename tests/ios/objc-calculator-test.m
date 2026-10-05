// SPDX-License-Identifier: GPL-2.0-or-later
#import "../../examples/ios-calculator/Calculator.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void expect(const char *keys, const char *expected) {
    VXCalculator *calculator = [VXCalculator new];
    for (const char *key = keys; *key; key++) [calculator pressKey:*key == 's' ? VXCalculatorSignKey : *key];
    if (strcmp([calculator displayText], expected)) {
        fprintf(stderr, "FAIL %s: expected %s, got %s\n", keys, expected, [calculator displayText]);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        expect("7+5=", "12");
        expect("3-9=", "-6");
        expect("12*8=", "96");
        expect("81/9=", "9");
        expect("0.1+0.2=", "0.3");
        expect("0002.50+0.25=", "2.75");
        expect("2+3*4=", "20");
        expect("5+*2=", "10");
        expect("5+=", "10");
        expect("2+3===", "11");
        expect("2+3=7", "7");
        expect("2+3=C", "0");
        expect("200+10%=", "220");
        expect("200-10%=", "180");
        expect("200*10%=", "20");
        expect("50%=", "0.5");
        expect("2s+5=", "3");
        expect("s2+5=", "3");
        expect("2ss", "2");
        expect("5+s2=", "3");
        expect("1/0=", "Error");
        expect("1/0=+", "Error");
        expect("1/0=7+2=", "9");
        expect("1/0=C", "0");
        expect("0..25", "0.25");
        expect("1234567890123456", "123456789012345");
        VXCalculator *overflow = [VXCalculator new];
        [overflow pressKey:'9'];
        for (int i = 0; i < 12; i++) { [overflow pressKey:'*']; [overflow pressKey:'=']; }
        if (strcmp([overflow displayText], "Error")) return 1;
        puts("Objective-C Calculator: 27 arithmetic/input cases passed");
    }
    return 0;
}
