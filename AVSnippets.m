// Snippets illustrating how to use various AV Foundation facilities

@import AVFoundation;

@interface AVSnippets () <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, AVAudioRecorderDelegate>
@end

@implementation AVSnippets

- (void)audioPlayer {

    NSURL *fileURL;
    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
    audioPlayer.delegate = self; // inform of finishing, interruptions
    audioPlayer.numberOfLoops = 3;
    audioPlayer.meteringEnabled = YES; // then query average/peak power levels
    [audioPlayer play];
    // later...
    [audioPlayer stop];

}


- (void)audioRecorder {

    NSURL *fileURL;
    NSDictionary *audioSettings = @{ AVSampleRateKey: @(44100),
                                     AVNumberOfChannelsKey: @(1)
                                     // etc.
                                     };
    NSError *error;
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:audioSettings error:&error];
    recorder.delegate = self; // inform of finishing, error, interruptions
    recorder.meteringEnabled = YES; // then query average/peak power levels
    [recorder record];
    // later...
    [recorder stop];

}


- (void) assetReading {
    NSError *error;
    AVAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:@"/movie.mov"]];
    AVAssetTrack *assetTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];

    NSDictionary *outputSettings = @{}; // Indicate pixel depth, pixel ordering, etc.
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:assetTrack outputSettings:outputSettings];
    [reader addOutput:output];

    while (1) {
        CMSampleBufferRef sample = [output copyNextSampleBuffer];
        if (!sample) { break; }
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sample);

        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        void *bytes = CVPixelBufferGetBaseAddress(imageBuffer);
        // Work with pixel data
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        CFRelease(sample);
    }
}


- (void) assetWriting { // Screen Capture
    NSURL *outputURL;
    NSError *error;
    // 1
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeQuickTimeMovie error:&error];

    // 2
    NSDictionary *outputSettings = @{ AVVideoCodecKey: AVVideoCodecH264,
                                      AVVideoWidthKey: @(720),
                                      AVVideoHeightKey: @(480) };
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    [writer addInput:input];

    // 3
    [writer startWriting];
    [writer startSessionAtSourceTime:CMTimeMake(0, 1)];

    // 4
    NSDictionary *pixelBufferAttributes = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
    AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:input
                                                                                                          sourcePixelBufferAttributes:pixelBufferAttributes];


    // In a timer based loop...

    // 5
    CVPixelBufferRef pixelBuffer=NULL;
    CVPixelBufferPoolCreatePixelBuffer(NULL, pixelBufferAdaptor.pixelBufferPool, &pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    // 6
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                                 CVPixelBufferGetWidth(pixelBuffer),
                                                 CVPixelBufferGetHeight(pixelBuffer),
                                                 8, // bits per component
                                                 CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                 (CGColorSpaceRef)CFAutorelease(CGColorSpaceCreateDeviceRGB()),
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);

    CGContextTranslateCTM(context, 0, CVPixelBufferGetHeight(pixelBuffer));
    CGContextScaleCTM(context, 1, -1);

    // 7
    UIGraphicsPushContext(context);
    [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:NO];
    UIGraphicsPopContext();
    CGContextRelease(context);

    // 8
    [pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:kCMTimeZero];

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CVPixelBufferRelease(pixelBuffer); pixelBuffer = NULL;


    // When done
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMakeWithSeconds(5, 1)];
    [writer finishWritingWithCompletionHandler:^{
        // WOOHOO!
    }];
}


- (void)exportSession { // Add Watermark to Movie
    // 1
    AVAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:@"/a/movie/file.mov"]];
    AVAssetTrack *videoTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;

    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    exportSession.outputURL = [NSURL fileURLWithPath:@"/output/file.mov"];

    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:asset];

    // 2
    CALayer *watermarkLayer = [self watermarkLayer];
    AVVideoCompositionCoreAnimationTool *animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithAdditionalLayer:watermarkLayer asTrackID:2];
    videoComposition.animationTool = animationTool;

    // 3
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

    // 4
    AVMutableVideoCompositionLayerInstruction *watermarkLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstruction];
    watermarkLayerInstruction.trackID = 2;
    instruction.layerInstructions = @[watermarkLayerInstruction,
                                      [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack]];
    videoComposition.instructions = @[instruction];

    // 5
    exportSession.videoComposition = videoComposition;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        if (exportSession.status == AVAssetReaderStatusCompleted) {
            // yay!
        }
    }];
}


- (void)speechSynthesizer {

    AVSpeechSynthesizer *synthesizer = [[AVSpeechSynthesizer alloc] init];
    synthesizer.delegate = self; // inform of starting/stopping speaking utterances
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Hello World"];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-UK"];
    [synthesizer speakUtterance:utterance];
    
}


#pragma mark -

- (CALayer *)watermarkLayer { return [CALayer layer]; }

@end
