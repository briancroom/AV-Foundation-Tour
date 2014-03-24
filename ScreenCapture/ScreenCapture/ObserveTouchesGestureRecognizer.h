#import <UIKit/UIKit.h>

@interface ObservedTouch : NSObject
@property (nonatomic, readonly) CGPoint location;
@property (nonatomic, readonly) float decay;
@end

@interface ObservedTouchSequence : NSObject
@property (nonatomic, readonly) UIBezierPath *touchPoints;
@property (nonatomic, readonly) NSArray *pointTimes;
@end

@interface ObserveTouchesGestureRecognizer : UIGestureRecognizer

@property (nonatomic) NSTimeInterval touchLifetimeAfterEnding;

- (NSSet *) activeTouches;
- (NSArray *) touchSequences;

@end
