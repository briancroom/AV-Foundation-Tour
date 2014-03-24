@import AVFoundation;
#import "TouchCompositor.h"
#import "ObserveTouchesGestureRecognizer.h"

@interface TouchCompositor ()
@property (nonatomic, strong) AVAssetExportSession *exportSession;
@end

@implementation TouchCompositor

- (void) compositeTouchSequences:(NSArray *)touchSequences initialTimestamp:(NSTimeInterval)initialTimestamp onVideoAtURL:(NSURL *)URL outputURL:(NSURL *)outputURL completion:(void (^)(NSError *error))completion {
    AVURLAsset *asset = [AVURLAsset assetWithURL:URL];
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];

    AVMutableComposition *composition = [[AVMutableComposition alloc] init];
    [composition insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofAsset:asset atTime:kCMTimeZero error:NULL];

    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    exportSession.outputURL = outputURL;

    [exportSession determineCompatibleFileTypesWithCompletionHandler:^(NSArray *compatibleFileTypes) {
        NSLog(@"Compatible types: %@", compatibleFileTypes);
    }];
    
    CALayer *touchesLayer = [self layerForTouchSequences:touchSequences initialTimestamp:initialTimestamp size:videoTrack.naturalSize];
    AVVideoCompositionCoreAnimationTool *animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithAdditionalLayer:touchesLayer asTrackID:2];

    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:asset];
    videoComposition.animationTool = animationTool;
    videoComposition.frameDuration = CMTimeMake(1, 30);

    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

    AVMutableVideoCompositionLayerInstruction *screenLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    AVMutableVideoCompositionLayerInstruction *touchesLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstruction];
    touchesLayerInstruction.trackID = 2;

    instruction.layerInstructions = @[ touchesLayerInstruction, screenLayerInstruction ];
    videoComposition.instructions = @[ instruction ];
    exportSession.videoComposition = videoComposition;

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        NSLog(@"Done: %ld", (long)exportSession.status);
        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            completion(nil);
        } else if (exportSession.status == AVAssetExportSessionStatusFailed) {
            completion(exportSession.error);
        }
    }];
    self.exportSession = exportSession;

    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(progressTimer:) userInfo:nil repeats:YES];
}

- (void)progressTimer:(NSTimer *)progressTimer {
    if (self.exportSession.status > AVAssetExportSessionStatusExporting) {
        [progressTimer invalidate];
    }
    else {
        NSLog(@"Progress: %f", self.exportSession.progress);
    }
}

- (CALayer *) layerForTouchSequences:(NSArray *)touchSequences initialTimestamp:(NSTimeInterval)initialTimestamp size:(CGSize)size {
    CALayer *touchesLayer = [[CALayer alloc] init];
    CGFloat scale = [UIScreen mainScreen].scale;
    touchesLayer.transform = CATransform3DMakeScale(scale, scale, 1);
    touchesLayer.frame = (CGRect){ CGPointZero, size };
    touchesLayer.sublayerTransform = CATransform3DMakeScale(1, -1, 1);

    for (ObservedTouchSequence *sequence in touchSequences) {
        CAShapeLayer *sequenceLayer = [[CAShapeLayer alloc] init];
        sequenceLayer.position = CGPointMake(-100, -100);
        sequenceLayer.fillColor = [UIColor greenColor].CGColor;
        sequenceLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-23, -23, 23*2, 23*2)].CGPath;
        [touchesLayer addSublayer:sequenceLayer];

        CAKeyframeAnimation *sequenceAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        sequenceAnimation.removedOnCompletion = NO;
        sequenceAnimation.fillMode = kCAFillModeForwards;
        sequenceAnimation.path = sequence.touchPoints.CGPath;
        sequenceAnimation.calculationMode = kCAAnimationDiscrete;
        sequenceAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];

        NSTimeInterval sequenceBeginTime = [[sequence.pointTimes firstObject] doubleValue];
        NSTimeInterval sequenceEndTime = [[sequence.pointTimes lastObject] doubleValue];
        sequenceAnimation.beginTime = sequenceBeginTime-initialTimestamp;
        sequenceAnimation.duration = sequenceEndTime-sequenceBeginTime;

        NSMutableArray *keyTimes = [[NSMutableArray alloc] init];
        for (NSNumber *pointTimeNumber in sequence.pointTimes) {
            NSTimeInterval pointTime = [pointTimeNumber doubleValue];
            [keyTimes addObject:@((pointTime-sequenceBeginTime)/sequenceAnimation.duration)];
        }
        sequenceAnimation.keyTimes = keyTimes;
        [sequenceLayer addAnimation:sequenceAnimation forKey:@"position"];

        CABasicAnimation *fadeOutAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeOutAnimation.removedOnCompletion = NO;
        fadeOutAnimation.fillMode = kCAFillModeForwards;
        fadeOutAnimation.toValue = @(0);
        fadeOutAnimation.beginTime = sequenceAnimation.beginTime+sequenceAnimation.duration;
        fadeOutAnimation.duration = 1;
        [sequenceLayer addAnimation:fadeOutAnimation forKey:@"opacity"];
    }

    return touchesLayer;
}

@end
