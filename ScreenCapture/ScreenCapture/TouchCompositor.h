#import <Foundation/Foundation.h>

@interface TouchCompositor : NSObject
- (void) compositeTouchSequences:(NSArray *)touchSequences initialTimestamp:(NSTimeInterval)initialTimestamp onVideoAtURL:(NSURL *)URL outputURL:(NSURL *)outputURL completion:(void (^)(NSError *error))completion;
@end
