#import <Foundation/Foundation.h>

@interface VideoFrameWriter : NSObject

@property (nonatomic, strong, readonly) NSURL *outputFileURL;
@property (nonatomic, getter=isWriting, readonly) BOOL writing;

- (instancetype) initWithOutputFileURL:(NSURL *)outputFileURL frameSize:(CGSize)frameSize frameRate:(NSInteger)framesPerSecond;

- (BOOL) writeFrameRenderedWithBlock:(void (^)(CGContextRef context))renderBlock;
- (void) finalizeWritingWithCompletion:(void (^)(void))completion;

@end
