// SPDX-License-Identifier: GPL-2.0-or-later
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#else
#import "api/UIKit.h"
#endif
#import "Calculator.h"

typedef struct { const char *title, *spoken; int key, column, row, span; } Key;
static const Key keys[] = {
    {"AC", "All clear", 'C', 0, 0, 1}, {"±", "Change sign", VXCalculatorSignKey, 1, 0, 1},
    {"%", "Percent", '%', 2, 0, 1}, {"÷", "Divide", '/', 3, 0, 1},
    {"7", "7", '7', 0, 1, 1}, {"8", "8", '8', 1, 1, 1}, {"9", "9", '9', 2, 1, 1}, {"×", "Multiply", '*', 3, 1, 1},
    {"4", "4", '4', 0, 2, 1}, {"5", "5", '5', 1, 2, 1}, {"6", "6", '6', 2, 2, 1}, {"−", "Subtract", '-', 3, 2, 1},
    {"1", "1", '1', 0, 3, 1}, {"2", "2", '2', 1, 3, 1}, {"3", "3", '3', 2, 3, 1}, {"+", "Add", '+', 3, 3, 1},
    {"0", "0", '0', 0, 4, 2}, {".", "Decimal point", '.', 2, 4, 1}, {"=", "Equals", '=', 3, 4, 1},
};
enum { keyCount = sizeof(keys) / sizeof(keys[0]) };

@interface VXCalculatorViewController : UIViewController {
    VXCalculator *_calculator;
    UILabel *_display;
    UIButton *_buttons[keyCount];
}
@end

@implementation VXCalculatorViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    _calculator = [VXCalculator new];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1];
    _display = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    _display.text = [NSString stringWithUTF8String:"0"];
    _display.accessibilityLabel = [NSString stringWithUTF8String:"Result"];
    _display.textColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:1];
    _display.font = [UIFont systemFontOfSize:72 weight:-0.4];
    _display.textAlignment = NSTextAlignmentRight;
    _display.adjustsFontSizeToFitWidth = YES;
    _display.minimumScaleFactor = 0.25;
    [self.view addSubview:_display];
    for (int i = 0; i < keyCount; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = keys[i].key;
        [button setTitle:[NSString stringWithUTF8String:keys[i].title] forState:UIControlStateNormal];
        button.accessibilityLabel = [NSString stringWithUTF8String:keys[i].spoken];
        BOOL operation = keys[i].column == 3;
        BOOL utility = keys[i].row == 0 && !operation;
        UIColor *text = [UIColor colorWithRed:utility ? 0.05 : 1 green:utility ? 0.05 : 1 blue:utility ? 0.05 : 1 alpha:1];
        [button setTitleColor:text forState:UIControlStateNormal];
        button.backgroundColor = operation ? [UIColor colorWithRed:1 green:0.58 blue:0.06 alpha:1]
            : (utility ? [UIColor colorWithRed:0.68 green:0.68 blue:0.68 alpha:1]
                : [UIColor colorWithRed:0.20 green:0.20 blue:0.20 alpha:1]);
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        _buttons[i] = button;
        [self.view addSubview:button];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat gap = 12, margin = 18;
    CGFloat availableWidth = bounds.size.width - safe.left - safe.right - 2 * margin;
    CGFloat availableHeight = bounds.size.height - safe.top - safe.bottom - 2 * margin - 96;
    CGFloat unit = (availableWidth - 3 * gap) / 4;
    CGFloat heightLimit = (availableHeight - 4 * gap) / 5;
    if (unit > heightLimit) unit = heightLimit;
    if (unit < 20) unit = 20;
    CGFloat width = 4 * unit + 3 * gap;
    CGFloat left = safe.left + (bounds.size.width - safe.left - safe.right - width) / 2;
    CGFloat top = bounds.size.height - safe.bottom - margin - 5 * unit - 4 * gap;
    _display.frame = CGRectMake(left, safe.top + margin, width, top - safe.top - margin - gap);
    for (int i = 0; i < keyCount; i++) {
        _buttons[i].frame = CGRectMake(left + keys[i].column * (unit + gap), top + keys[i].row * (unit + gap),
            keys[i].span * unit + (keys[i].span - 1) * gap, unit);
        _buttons[i].layer.cornerRadius = unit / 2;
        _buttons[i].titleLabel.font = [UIFont systemFontOfSize:unit * 0.38 weight:0];
    }
}

- (void)buttonTapped:(UIButton *)button {
    [_calculator pressKey:(int)button.tag];
    _display.text = [NSString stringWithUTF8String:[_calculator displayText]];
}
@end

@interface VXAppDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation VXAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [VXCalculatorViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, [NSString stringWithUTF8String:"VXAppDelegate"]);
    }
}
