#import "PreviewView.h"

@implementation PreviewView

+ (Class)layerClass {
	return [AVCaptureVideoPreviewLayer class];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor blackColor];
        [self.layer setMasksToBounds:YES];
        [(AVCaptureVideoPreviewLayer*)self.layer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    }
    return self;
}

- (AVCaptureSession*)session
{
	return [(AVCaptureVideoPreviewLayer*)self.layer session];
}

- (void)setSession:(AVCaptureSession *)session
{
	[(AVCaptureVideoPreviewLayer*)self.layer setSession:session];
}

@end
