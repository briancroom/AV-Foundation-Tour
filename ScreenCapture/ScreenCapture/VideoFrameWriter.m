@import AVFoundation;
#import "VideoFrameWriter.h"

@interface VideoFrameWriter ()
@property (nonatomic, strong, readwrite) NSURL *outputFileURL;
@property (nonatomic) CGSize frameSize;
@property (nonatomic) int32_t framesPerSecond;

@property (nonatomic, getter=isWriting, readwrite) BOOL writing;

@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;

@property (nonatomic, assign) CGColorSpaceRef contextColorSpace;

@property (nonatomic) uint32_t upcomingFrameIndex;
@end

@implementation VideoFrameWriter

- (instancetype) initWithOutputFileURL:(NSURL *)outputFileURL frameSize:(CGSize)frameSize frameRate:(NSInteger)framesPerSecond {
    if (self = [super init]) {
        self.outputFileURL = outputFileURL;
        self.frameSize = frameSize;
        self.framesPerSecond = (int32_t)framesPerSecond;
        
        [[[NSFileManager alloc] init] removeItemAtURL:outputFileURL error:NULL];
        self.assetWriter = [[AVAssetWriter alloc] initWithURL:outputFileURL fileType:AVFileTypeQuickTimeMovie error:NULL];
        
        CGFloat scale = [UIScreen mainScreen].scale;
        NSDictionary *outputSettings = @{ AVVideoCodecKey: AVVideoCodecH264,
                                          AVVideoWidthKey: @(frameSize.width*scale),
                                          AVVideoHeightKey: @(frameSize.height*scale),
                                          AVVideoCompressionPropertiesKey: @{}};
        self.assetWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
        
        NSDictionary *pixelBufferAttributes = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
        self.pixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.assetWriterInput sourcePixelBufferAttributes:pixelBufferAttributes];
        
        self.contextColorSpace = CGColorSpaceCreateDeviceRGB();
        
        [self.assetWriter addInput:self.assetWriterInput];
        [self.assetWriter startWriting];
        [self.assetWriter startSessionAtSourceTime:CMTimeMake(0, 1)];
        self.writing = YES;
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (void) cleanup {
    CGColorSpaceRelease(self.contextColorSpace); self.contextColorSpace = nil;
    
    if (self.assetWriter.status == AVAssetWriterStatusWriting) {
        [self.assetWriter cancelWriting];
    }
    self.assetWriter = nil;
    self.assetWriterInput = nil;
    self.pixelBufferAdaptor = nil;
}

- (BOOL) writeFrameRenderedWithBlock:(void (^)(CGContextRef context))renderBlock {
    if (!self.writing || ![self.assetWriterInput isReadyForMoreMediaData]) {
        return NO;
    }
    
    CVPixelBufferRef pixelBuffer=NULL;
    CVPixelBufferPoolCreatePixelBuffer(NULL, self.pixelBufferAdaptor.pixelBufferPool, &pixelBuffer);
    
    if (!pixelBuffer) {
        return NO;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    CGFloat scale = [UIScreen mainScreen].scale;
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                                 CVPixelBufferGetWidth(pixelBuffer),
                                                 CVPixelBufferGetHeight(pixelBuffer),
                                                 8, // bits per component
                                                 CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                 self.contextColorSpace,
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    
    CGContextTranslateCTM(context, 0, CVPixelBufferGetHeight(pixelBuffer));
    CGContextScaleCTM(context, scale, -scale);
    
    renderBlock(context);
    
    [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(self.upcomingFrameIndex, self.framesPerSecond)];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CVPixelBufferRelease(pixelBuffer); pixelBuffer = NULL;
    
    self.upcomingFrameIndex++;
    
    return YES;
}

- (void) finalizeWritingWithCompletion:(void (^)(void))completion {
    if (self.writing) {
        self.writing = NO;
        [self.assetWriterInput markAsFinished];
        [self.assetWriter endSessionAtSourceTime:CMTimeMake(self.upcomingFrameIndex-1, self.framesPerSecond)];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSLog(@"Done writing to %@", self.outputFileURL);
            [self cleanup];
            if (completion) {
                completion();
            }
        }];
    }
    else if (completion) {
        completion();
    }
}
@end
