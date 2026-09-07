// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

@interface CalculatorController : NSObject <NSApplicationDelegate>
@end

static NSTextField *display;
static NSInteger accumulator;
static NSInteger input;
static NSInteger pending_operator;
static BOOL replace_input = YES;

@implementation CalculatorController

- (void)applicationDidFinishLaunching:(id)notification {
    (void)notification;
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 284, 364)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setTitle:@"Cocoa Calculator"];

    display = [NSTextField labelWithString:@"0"];
    [display setFrame:NSMakeRect(12, 296, 260, 56)];
    [display setAlignment:NSTextAlignmentRight];
    [[window contentView] addSubview:display];

	NSString *titles[] = {
		@"C", @"%", @"+/-", @"/",
		@"7", @"8", @"9", @"*",
		@"4", @"5", @"6", @"-",
		@"1", @"2", @"3", @"+",
		@"0", @"=",
    };
    NSInteger tags[] = {
        100, 101, 102, 14,
        7, 8, 9, 13,
        4, 5, 6, 12,
        1, 2, 3, 11,
		0, 15,
	};
	for (NSInteger i = 0; i < 18; i++) {
		NSInteger row = i / 4;
		NSInteger column = i == 17 ? 2 : i % 4;
        NSButton *button = [NSButton buttonWithTitle:titles[i]
            target:self action:@selector(buttonPressed:)];
        [button setTag:tags[i]];
		[button setFrame:NSMakeRect(12 + column * 67, 244 - row * 52,
									i >= 16 ? 126 : 59, 44)];
		[[window contentView] addSubview:button];
	}
    [window makeKeyAndOrderFront:nil];
}

- (void)buttonPressed:(NSButton *)sender {
    NSInteger tag = [sender tag];
    if (tag >= 0 && tag <= 9) {
        input = replace_input ? tag : input * 10 + tag;
        replace_input = NO;
    } else if (tag >= 11 && tag <= 14) {
        if (pending_operator && !replace_input) {
            if (pending_operator == 11) accumulator += input;
            if (pending_operator == 12) accumulator -= input;
            if (pending_operator == 13) accumulator *= input;
            if (pending_operator == 14 && input != 0) accumulator /= input;
        } else {
            accumulator = input;
        }
        pending_operator = tag;
        replace_input = YES;
    } else if (tag == 15) {
        if (pending_operator == 11) accumulator += input;
        if (pending_operator == 12) accumulator -= input;
        if (pending_operator == 13) accumulator *= input;
        if (pending_operator == 14 && input != 0) accumulator /= input;
        input = accumulator;
        pending_operator = 0;
        replace_input = YES;
    } else if (tag == 100) {
        accumulator = input = pending_operator = 0;
        replace_input = YES;
    } else if (tag == 101) {
        input /= 100;
    } else if (tag == 102) {
        input = -input;
    }
    [display setIntegerValue:input];
}

@end

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    NSApplication *application = [NSApplication sharedApplication];
    CalculatorController *controller = [CalculatorController new];
    [application setDelegate:controller];
    [application run];
    return 0;
}
