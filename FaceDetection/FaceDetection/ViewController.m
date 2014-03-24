// Some of this code is derived from Apple's StacheCam demo, from WWDC 2012 session 520

@import AVFoundation;
#import "ViewController.h"
#import "PreviewView.h"

void displayErrorOnMainQueue(NSError *error, NSString *message)
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView* alert = [UIAlertView new];
		if(error) {
			alert.title = [NSString stringWithFormat:@"%@ (%zd)", message, error.code];
			alert.message = [error localizedDescription];
		} else {
			alert.title = message;
		}
		[alert addButtonWithTitle:@"Dismiss"];
		[alert show];
	});
}


@interface ViewController () <AVCaptureMetadataOutputObjectsDelegate>
@property (weak, nonatomic) IBOutlet PreviewView *previewView;
@property (weak, nonatomic) IBOutlet UILabel *centerLabel;
@property (weak, nonatomic) IBOutlet UILabel *rollLabel;
@property (weak, nonatomic) IBOutlet UILabel *yawLabel;

@property (strong, nonatomic) AVCaptureSession* session;
@property (strong, nonatomic) AVCaptureDevice* device;
@property (strong, nonatomic) AVCaptureMetadataOutput *metadataOutput;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupAVCapture];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[[(AVCaptureVideoPreviewLayer*)self.previewView.layer connection] setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
}


#pragma mark - AVFoundation Stuff

- (void) setupAVCapture
{
	self.session = [AVCaptureSession new];
	[self.session setSessionPreset:AVCaptureSessionPresetHigh]; // high-res stills, screen-size video
	self.previewView.session = self.session;
	
	[self updateCameraSelection];
	
	// For receiving AV Foundation face detection
	[self setupAVFoundationFaceDetection];
	
	[self.session startRunning];
}

- (void) setupAVFoundationFaceDetection
{
	self.metadataOutput = [AVCaptureMetadataOutput new];
	if ( ! [self.session canAddOutput:self.metadataOutput] ) {
		self.metadataOutput = nil;
		return;
	}
	
	// Metadata processing will be fast, and mostly updating UI which should be done on the main thread
	// So just use the main dispatch queue instead of creating a separate one
	[self.metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
	[self.session addOutput:self.metadataOutput];
	
	if ( ! [self.metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeFace] ) {
		// face detection isn't supported via AV Foundation
		[self teardownAVFoundationFaceDetection];
		return;
	}
	self.metadataOutput.metadataObjectTypes = @[ AVMetadataObjectTypeFace ];
	[self updateAVFoundationFaceDetection];
}

- (void) updateAVFoundationFaceDetection
{
	if ( self.metadataOutput )
		[[self.metadataOutput connectionWithMediaType:AVMediaTypeMetadata] setEnabled:YES];
}

- (void) teardownAVFoundationFaceDetection
{
	if ( self.metadataOutput )
		[self.session removeOutput:self.metadataOutput];
	self.metadataOutput = nil;
}

- (void) teardownAVCapture
{
	[self.session stopRunning];
	
	[self teardownAVFoundationFaceDetection];
	
	[self.device unlockForConfiguration];
	self.device = nil;
	self.session = nil;
}

- (AVCaptureDeviceInput*) pickCamera
{
	AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionFront;
	BOOL hadError = NO;
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			NSError *error = nil;
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:&error];
			if (error) {
				hadError = YES;
				displayErrorOnMainQueue(error, @"Could not initialize for AVMediaTypeVideo");
			} else if ( [self.session canAddInput:input] ) {
				return input;
			}
		}
	}
	if ( ! hadError ) {
		// no errors, simply couldn't find a matching camera
		displayErrorOnMainQueue(nil, @"No camera found for requested orientation");
	}
	return nil;
}

- (void) updateCameraSelection
{
	[self.session beginConfiguration];
	
	// have to remove old inputs before we test if we can add a new input
	NSArray* oldInputs = [self.session inputs];
	for (AVCaptureInput *oldInput in oldInputs)
		[self.session removeInput:oldInput];
	
	AVCaptureDeviceInput* input = [self pickCamera];
	if ( ! input ) {
		// failed, restore old inputs
		for (AVCaptureInput *oldInput in oldInputs)
			[self.session addInput:oldInput];
	} else {
		// succeeded, set input and update connection states
		[self.session addInput:input];
		self.device = input.device;
		
		NSError* err;
		if ( ! [self.device lockForConfiguration:&err] ) {
			NSLog(@"Could not lock device: %@",err);
		}
        
		[self updateAVFoundationFaceDetection];
	}
	
	[self.session commitConfiguration];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)faces fromConnection:(AVCaptureConnection *)connection {
    if ([faces count] > 0) {
        AVMetadataFaceObject *face = [faces lastObject];
        
        CGPoint centerPoint = CGPointMake(CGRectGetMidX(face.bounds), CGRectGetMidY(face.bounds));
        CGPoint topLeftPoint = CGPointMake(CGRectGetMinX(face.bounds), CGRectGetMinY(face.bounds));
        CGPoint bottomRightPoint = CGPointMake(CGRectGetMaxX(face.bounds), CGRectGetMaxY(face.bounds));
        self.centerLabel.text = [NSString stringWithFormat:@"Center: %.2f, %.2f (%.2f,%.2f, %.2f,%.2f)", centerPoint.x, centerPoint.y, topLeftPoint.x, topLeftPoint.y, bottomRightPoint.x, bottomRightPoint.y];
        self.rollLabel.text = [NSString stringWithFormat:@"Roll: %f", face.rollAngle];
        self.yawLabel.text = [NSString stringWithFormat:@"Yaw: %f", face.yawAngle];
        
        BOOL fullyInside = CGRectContainsRect(CGRectMake(0, 0, 1, 1), face.bounds);
        [self setLabelsToColor:fullyInside ? [UIColor greenColor] : [UIColor yellowColor]];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearLabels) object:nil];
	}
    else {
        [self clearLabels];
    }
}

- (void) clearLabels {
    self.centerLabel.text = @"Center:";
    self.rollLabel.text = @"Roll:";
    self.yawLabel.text = @"Yaw:";
    [self setLabelsToColor:[UIColor redColor]];
}

- (void) setLabelsToColor:(UIColor *)color {
    [@[self.centerLabel, self.rollLabel, self.yawLabel] makeObjectsPerformSelector:@selector(setTextColor:) withObject:color];
}

@end
