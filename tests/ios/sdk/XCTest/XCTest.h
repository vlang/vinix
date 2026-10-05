/* SPDX-License-Identifier: GPL-2.0-or-later */
// Execute the original upstream model assertions without an XCTest framework.
#pragma once
#import <Foundation/Foundation.h>
#define XCTestCase NSObject
#define XCTAssert(condition, ...) NSAssert(condition, __VA_ARGS__)
#define XCTAssertTrue(condition, ...) XCTAssert(condition, __VA_ARGS__)
#define XCTAssertFalse(condition, ...) XCTAssert(!(condition), __VA_ARGS__)
#define XCTAssertNotNil(object, ...) XCTAssert((object) != nil, __VA_ARGS__)
@interface NSObject (TestLifecycle)
- (void)setUp;
- (void)tearDown;
@end
