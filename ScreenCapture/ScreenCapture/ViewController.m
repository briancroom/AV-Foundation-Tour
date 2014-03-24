@import MediaPlayer;
#import "ViewController.h"
#import "VideoFrameWriter.h"
#import "ObserveTouchesGestureRecognizer.h"
#import "TouchCompositor.h"

static const CGFloat kTouchPointCircleRadius = 23;
@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UILabel *fpsLabel;
@property (nonatomic, strong) VideoFrameWriter *frameWriter;
@property (nonatomic, strong) ObserveTouchesGestureRecognizer *observeTouchesGestureRecognizer;
@property (nonatomic) NSTimeInterval initialTimestamp;
@property (nonatomic, strong) UIBezierPath *touchBezierPath;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.observeTouchesGestureRecognizer = [[ObserveTouchesGestureRecognizer alloc] initWithTarget:self action:@selector(spied)];
    [self.view addGestureRecognizer:self.observeTouchesGestureRecognizer];

    self.touchBezierPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-kTouchPointCircleRadius, -kTouchPointCircleRadius, kTouchPointCircleRadius*2, kTouchPointCircleRadius*2)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.frameWriter) {
        self.scrollView.contentSize = CGSizeMake(CGRectGetWidth(self.view.bounds)*3, CGRectGetHeight(self.view.bounds)*3);
        self.scrollView.contentOffset = CGPointMake(CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds));
        
        NSInteger framesPerSecond = 10;
        
        NSURL *fileURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"capture.mov"];
        CGSize frameSize = CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.height);
        self.frameWriter = [[VideoFrameWriter alloc] initWithOutputFileURL:fileURL frameSize:frameSize frameRate:framesPerSecond];

        self.initialTimestamp = [NSProcessInfo processInfo].systemUptime;

        NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/framesPerSecond target:self selector:@selector(captureFrame:) userInfo:Nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
}

- (void) captureFrame:(NSTimer *)timer {
    if (self.frameWriter.writing) {
        
        [self.frameWriter writeFrameRenderedWithBlock:^(CGContextRef context) {
            CFTimeInterval time = CACurrentMediaTime();
            
            UIGraphicsPushContext(context);
            
            [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:NO];

            UIGraphicsPopContext();
            
            time = CACurrentMediaTime()-time;
            self.fpsLabel.text = [NSString stringWithFormat:@"Render time: %f ms", time*1000];
        }];
        
    }
    else {
        [timer invalidate];
    }
}

- (void) spied {}

- (IBAction)addTapped {
    UIView *rect = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
    rect.userInteractionEnabled = NO;
    rect.center = CGPointMake(arc4random()%(int)CGRectGetWidth(self.scrollView.bounds)+CGRectGetMinX(self.scrollView.bounds),
                              arc4random()%(int)CGRectGetHeight(self.scrollView.bounds)+CGRectGetMinY(self.scrollView.bounds));
    rect.backgroundColor = [UIColor colorWithRed:(arc4random()%256)/256.0f green:(arc4random()%256)/256.0f blue:(arc4random()%256)/256.0f alpha:1];
    [self.scrollView addSubview:rect];
}

- (IBAction)doneTapped {
    [self.frameWriter finalizeWritingWithCompletion:^{
        double delayInSeconds = 1;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            TouchCompositor *touchCompositor = [[TouchCompositor alloc] init];
            NSURL *fileURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"composited.mov"];

            [touchCompositor compositeTouchSequences:[self.observeTouchesGestureRecognizer touchSequences]
                                    initialTimestamp:self.initialTimestamp
                                        onVideoAtURL:self.frameWriter.outputFileURL
                                           outputURL:fileURL
                                          completion:^(NSError *error) {
                                              if (!error) {
                                                  [self showMovieAtURL:fileURL];
                                              }
                                              else {
                                                  NSLog(@"Error: %@", error);
                                              }
                                          }];
        });
    }];
}

- (void) showMovieAtURL:(NSURL *)movieURL {
    double delayInSeconds = 0.5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        MPMoviePlayerViewController *controller = [[MPMoviePlayerViewController alloc] initWithContentURL:movieURL];
        [self presentMoviePlayerViewControllerAnimated:controller];
        [[NSNotificationCenter defaultCenter] removeObserver:controller name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    });
}
@end
