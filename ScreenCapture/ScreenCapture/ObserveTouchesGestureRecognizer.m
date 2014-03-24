#import "ObserveTouchesGestureRecognizer.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface ObservedTouch ()
@property (nonatomic, readwrite) CGPoint location;
@property (nonatomic) NSTimeInterval endTimestamp;
@property (nonatomic) NSTimeInterval decayLength;
@property (nonatomic, weak) ObservedTouchSequence *observedTouchSequence;
@end

@implementation ObservedTouch
- (instancetype) init {
    if (self = [super init]) {
        self.endTimestamp = NAN;
    }
    return self;
}

- (float)decay {
    if (isnan(self.endTimestamp)) {
        return 0;
    }
    NSTimeInterval timeSinceEnd = [[NSProcessInfo processInfo] systemUptime]-self.endTimestamp;
    return MIN((timeSinceEnd)/self.decayLength, 1);
}

- (NSString *)description {
    return [[super description] stringByAppendingFormat:@" location: %@, decay: %g", NSStringFromCGPoint(self.location), self.decay];
}

@end


@interface ObservedTouchSequence ()
@property (nonatomic, strong, readwrite) UIBezierPath *touchPoints;
@property (nonatomic, strong, readwrite) NSMutableArray *pointTimes;
@end
@interface ObservedTouchSequence (Appending)
- (void) appendPoint:(CGPoint)point time:(NSTimeInterval)time;
@end

@implementation ObservedTouchSequence

- (id)init {
    if (self = [super init]) {
        self.pointTimes = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) appendPoint:(CGPoint)point time:(NSTimeInterval)time {
    if (!self.touchPoints) {
        self.touchPoints = [[UIBezierPath alloc] init];
        [self.touchPoints moveToPoint:point];
    }
    else {
        [self.touchPoints addLineToPoint:point];
    }
    [(NSMutableArray *)self.pointTimes addObject:@(time)];
}

@end


@interface ObserveTouchesGestureRecognizer () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMapTable *touches;
@property (nonatomic, strong) NSMutableArray *touchSequences;
@end

@implementation ObserveTouchesGestureRecognizer

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        self.cancelsTouchesInView = YES;
        self.delaysTouchesEnded = NO;
        self.delegate = self;
        
        self.touchLifetimeAfterEnding = 1;
        self.touches = [NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsOpaqueMemory|NSPointerFunctionsObjectPointerPersonality) valueOptions:NSPointerFunctionsStrongMemory];
        self.touchSequences = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSSet *)activeTouches {
    BOOL touchesDecayed = NO;
    
    NSMutableSet *touches = [[NSMutableSet alloc] init];
    for (ObservedTouch *touch in [self.touches objectEnumerator]) {
        if (touch.decay < 1) {
            [touches addObject:touch];
        }
        else {
            touchesDecayed = YES;
        }
    }
    
    if (touchesDecayed) {
        [self cleanupDecayedTouches];
    }
    return touches;
}

#pragma mark - Private

- (void) storeTouch:(UITouch *)touch {
    ObservedTouch *observedTouch = [self.touches objectForKey:touch];
    ObservedTouchSequence *touchSequence = observedTouch.observedTouchSequence;

    if (!observedTouch) {
        observedTouch = [[ObservedTouch alloc] init];
        [self.touches setObject:observedTouch forKey:touch];

        touchSequence = [[ObservedTouchSequence alloc] init];
        [(NSMutableArray *)self.touchSequences addObject:touchSequence];
        observedTouch.observedTouchSequence = touchSequence;
    }

    observedTouch.location = [touch locationInView:self.view];
    [touchSequence appendPoint:observedTouch.location time:touch.timestamp];
}

- (void) finishTouch:(UITouch *)touch {
    ObservedTouch *observedTouch = [self.touches objectForKey:touch];
    observedTouch.endTimestamp = touch.timestamp;
    observedTouch.decayLength = self.touchLifetimeAfterEnding;

    ObservedTouchSequence *touchSequence = observedTouch.observedTouchSequence;
    [touchSequence appendPoint:[touch locationInView:self.view] time:touch.timestamp];
}

- (void) cleanupDecayedTouches {
    NSHashTable *decayedTouchKeys = [NSHashTable hashTableWithOptions:NSPointerFunctionsOpaqueMemory|NSHashTableObjectPointerPersonality];
    for (id touchKey in [self.touches keyEnumerator]) {
        ObservedTouch *touch = [self.touches objectForKey:touchKey];
        if (touch.decay >= 1) {
            [decayedTouchKeys addObject:touchKey];
        }
    }
    
    for (id touchKey in decayedTouchKeys) {
        [self.touches removeObjectForKey:touchKey];
    }
}

#pragma mark - Touch Handling

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    for (UITouch *touch in touches) {
        [self storeTouch:touch];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    for (UITouch *touch in touches) {
        [self storeTouch:touch];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    for (UITouch *touch in touches) {
        [self finishTouch:touch];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    for (UITouch *touch in touches) {
        [self finishTouch:touch];
    }
}

#pragma mark - <UIGestureRecognizerDelegate>

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

@end
