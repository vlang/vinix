// SPDX-License-Identifier: GPL-2.0-or-later
// Shared Mac/iOS ABI fixture for rectangle math and constant storage.
typedef _Bool Bool;
typedef struct { double x,y; } Point;
typedef struct { double width,height; } Size;
typedef struct { double x,y,width,height; } Rect;
extern int puts(const char *), printf(const char *,...);
extern const Point CGPointZero;
extern const Size CGSizeZero;
extern const Rect CGRectZero, CGRectNull, CGRectInfinite;
extern double CGRectGetMinX(Rect), CGRectGetMidX(Rect), CGRectGetMaxX(Rect), CGRectGetMinY(Rect), CGRectGetMidY(Rect), CGRectGetMaxY(Rect), CGRectGetWidth(Rect), CGRectGetHeight(Rect);
extern Rect CGRectStandardize(Rect), CGRectIntegral(Rect), CGRectInset(Rect,double,double), CGRectOffset(Rect,double,double), CGRectUnion(Rect,Rect), CGRectIntersection(Rect,Rect);
extern Bool CGRectContainsPoint(Rect,Point), CGRectContainsRect(Rect,Rect), CGRectIntersectsRect(Rect,Rect), CGRectEqualToRect(Rect,Rect), CGRectIsNull(Rect), CGRectIsEmpty(Rect), CGPointEqualToPoint(Point,Point), CGSizeEqualToSize(Size,Size);
#define CHECK(x) do { if (!(x)) { printf("IOS-GEOMETRY FAIL line %d: %s\n",__LINE__,#x); return 1; } } while(0)
static Bool raw_equal(Rect a,Rect b) { return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height; }
int main(void) {
    CHECK(CGPointZero.x == 0 && CGPointZero.y == 0 && CGSizeZero.width == 0 && CGSizeZero.height == 0);
    CHECK(raw_equal(CGRectZero,(Rect){0,0,0,0}));
    CHECK(CGRectNull.x == __builtin_inf() && CGRectNull.y == __builtin_inf() && CGRectNull.width == 0 && CGRectNull.height == 0);
    CHECK(CGRectInfinite.x == -0x1.fffffffffffffp+1022 && CGRectInfinite.y == CGRectInfinite.x && CGRectInfinite.width == 0x1.fffffffffffffp+1023 && CGRectInfinite.height == CGRectInfinite.width);
    CHECK(CGRectIsNull(CGRectNull) && CGRectIsEmpty(CGRectNull) && CGRectIsEmpty(CGRectZero));
    CHECK(CGPointEqualToPoint(CGPointZero,(Point){0,0}) && !CGPointEqualToPoint((Point){1,2},(Point){1,3}));
    CHECK(CGSizeEqualToSize((Size){2,3},(Size){2,3}) && !CGSizeEqualToSize((Size){2,3},(Size){2,-3}));
    Rect normal = {10,20,4,6}, reversed = {14,26,-4,-6};
    CHECK(CGRectGetMinX(reversed) == 10 && CGRectGetMaxX(reversed) == 14 && CGRectGetMidX(reversed) == 12);
    CHECK(CGRectGetMinY(reversed) == 20 && CGRectGetMaxY(reversed) == 26 && CGRectGetMidY(reversed) == 23);
    CHECK(CGRectGetWidth(reversed) == 4 && CGRectGetHeight(reversed) == 6 && !CGRectIsEmpty(reversed));
    CHECK(CGRectEqualToRect(normal,reversed) && raw_equal(CGRectStandardize(reversed),normal));
    CHECK(CGRectContainsPoint(normal,(Point){10,20}) && CGRectContainsPoint(reversed,(Point){11,21}));
    CHECK(!CGRectContainsPoint(normal,(Point){14,22}) && !CGRectContainsPoint(normal,(Point){12,26}));
    CHECK(!CGRectContainsPoint((Rect){10,20,0,6},(Point){10,21}) && !CGRectContainsPoint(CGRectNull,CGPointZero));
    CHECK(raw_equal(CGRectInset(reversed,-1,-2),(Rect){9,18,6,10}));
    CHECK(raw_equal(CGRectInset(normal,2,3),(Rect){12,23,0,0}));
    CHECK(CGRectIsNull(CGRectInset(normal,3,3)) && CGRectIsNull(CGRectInset(normal,1,4)));
    CHECK(raw_equal(CGRectOffset(reversed,1,2),(Rect){11,22,4,6}));
    CHECK(raw_equal(CGRectIntegral((Rect){1.2,2.8,0,0}),(Rect){1,2,1,1}));
    CHECK(raw_equal(CGRectIntegral((Rect){10.5,20.5,0,6.5}),(Rect){10,20,1,7}));
    Rect noncanonical_null = {__builtin_inf(),0,1,1};
    CHECK(CGRectIsNull(noncanonical_null) && CGRectIsEmpty(noncanonical_null) && CGRectEqualToRect(noncanonical_null,CGRectNull));
    CHECK(raw_equal(CGRectStandardize(noncanonical_null),CGRectNull));
    CHECK(raw_equal(CGRectIntegral(noncanonical_null),noncanonical_null));
    CHECK(raw_equal(CGRectInset(noncanonical_null,1,2),noncanonical_null));
    CHECK(raw_equal(CGRectOffset(noncanonical_null,1,2),noncanonical_null));
    CHECK(CGRectGetWidth(noncanonical_null) == 1 && CGRectGetHeight(noncanonical_null) == 1);
    Rect nan = {0,0,__builtin_nan(""),1};
    CHECK(!CGRectIsNull(nan) && !CGRectIsEmpty(nan) && !CGRectEqualToRect(nan,nan));
    CHECK(CGRectIsNull(CGRectInset(nan,1,2)) && !CGRectContainsPoint(nan,CGPointZero));
    CHECK(raw_equal(CGRectUnion(CGRectNull,reversed),reversed));
    CHECK(raw_equal(CGRectUnion((Rect){100,100,0,0},normal),(Rect){10,20,90,80}));
    CHECK(raw_equal(CGRectIntersection(normal,(Rect){14,20,4,6}),(Rect){14,20,0,6}));
    CHECK(!CGRectIntersectsRect(normal,(Rect){14,20,4,6}));
    CHECK(CGRectIsNull(CGRectIntersection(normal,(Rect){15,20,4,6})));
    CHECK(CGRectContainsRect(normal,(Rect){14,26,0,0}) && CGRectContainsRect(normal,CGRectNull));
    CHECK(raw_equal(CGRectUnion(normal,CGRectInfinite),CGRectInfinite));
    CHECK(raw_equal(CGRectIntersection(normal,CGRectInfinite),normal));
    // Exercise the HFA registers with four-/six-/eight-double argument lists
    // and negative sizes, integral edges, and fractional coordinates.
    for (int i=0;i<500;i++) {
        double x = (i%37)-18.25, y = (i%31)-15.75, w = 2*(i%5+1), h = 2*(i%7+1);
        Rect rect = {x+w,y+h,-w,-h}, standard = {x,y,w,h};
        CHECK(raw_equal(CGRectStandardize(rect),standard));
        CHECK(CGRectGetWidth(rect) == w && CGRectGetHeight(rect) == h && CGRectEqualToRect(rect,standard));
        CHECK(CGRectContainsPoint(rect,(Point){x+w/2,y+h/2}) && !CGRectContainsPoint(rect,(Point){x+w,y+h}));
        CHECK(raw_equal(CGRectInset(rect,0.5,0.25),(Rect){x+0.5,y+0.25,w-1,h-0.5}));
        CHECK(raw_equal(CGRectIntegral(rect),(Rect){x-0.75,y-0.25,w+1,h+1}));
        CHECK(CGRectContainsRect(rect,CGRectInset(rect,0.5,0.5)) && CGRectIntersectsRect(rect,standard));
        CHECK(raw_equal(CGRectIntersection(rect,CGRectOffset(rect,w/2,h/2)),(Rect){x+w/2,y+h/2,w/2,h/2}));
    }
    puts("IOS-GEOMETRY: native HFA arguments/results, constants, negative dimensions, half-open hit testing, null/empty edges and rectangle math");
    return 0;
}
