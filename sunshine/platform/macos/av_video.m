#import "av_video.h"

@implementation AVVideo

// XXX: Currenty, this function only returns the screen IDs as names,
// which is not very helpfull to the user. The API to retrieve names
// was deprecated with 10.9+.
// However, there is a solution with little external code that can be used:
// https://stackoverflow.com/questions/20025868/cgdisplayioserviceport-is-deprecated-in-os-x-10-9-how-to-replace
+ (NSArray<NSDictionary *> *)displayNames {
  NSMutableArray *result = [[NSMutableArray alloc] init];

  CGDirectDisplayID displays[kMaxDisplays];
  uint32_t count;
  if(CGGetActiveDisplayList(kMaxDisplays, displays, &count) != kCGErrorSuccess) {
    return result;
  }

  for(uint32_t i = 0; i < count; i++) {
    [result addObject:@{
      @"id": [NSNumber numberWithUnsignedInt:displays[i]],
      @"name": [NSString stringWithFormat:@"%d", displays[i]]
    }];
  }

  return result;
}

- (id)initWithDisplay:(CGDirectDisplayID)displayID frameRate:(int)frameRate {
  return [self initWithDisplay:displayID frameRate:frameRate width:0 height:0];
}

- (id)initWithDisplay:(CGDirectDisplayID)displayID frameRate:(int)frameRate width:(int)width height:(int)height {
  self = [super init];

  self.capture = false;

  self.frameWidth       = width;
  self.frameHeight      = height;
  self.minFrameDuration = CMTimeMake(1, frameRate);
  self.captureStopped   = [[NSCondition alloc] init];

  self.session = [[AVCaptureSession alloc] init];

  AVCaptureScreenInput *screenInput = [[AVCaptureScreenInput alloc] initWithDisplayID:displayID];
  [screenInput setMinFrameDuration:self.minFrameDuration];

  if([self.session canAddInput:screenInput]) {
    [self.session addInput:screenInput];
  }
  else {
    [screenInput release];
    return nil;
  }

  AVCaptureVideoDataOutput *movieOutput = [[AVCaptureVideoDataOutput alloc] init];

  if(self.frameWidth > 0 && self.frameWidth > 0) {
    [movieOutput setVideoSettings:@{
      (NSString *)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA],
      (NSString *)kCVPixelBufferWidthKey: [NSNumber numberWithInt:self.frameWidth],
      (NSString *)kCVPixelBufferHeightKey: [NSNumber numberWithInt:self.frameHeight]
    }];
  }
  else {
    [movieOutput setVideoSettings:@{
      (NSString *)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]
    }];
  }

  dispatch_queue_attr_t qos       = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, DISPATCH_QUEUE_PRIORITY_HIGH);
  dispatch_queue_t recordingQueue = dispatch_queue_create("videoCaptureQueue", qos);

  [movieOutput setSampleBufferDelegate:self queue:recordingQueue];

  if([self.session canAddOutput:movieOutput]) {
    [self.session addOutput:movieOutput];
  }
  else {
    [movieOutput release];
    return nil;
  }

  self.videoConnection = [movieOutput connectionWithMediaType:AVMediaTypeVideo];

  return self;
}

- (void)dealloc {
  self.videoConnection = nil;
  [self.session stopRunning];
  [super dealloc];
}

- (bool)capture:(frameCallbackBlock)frameCallback {
  self.frameCallback = frameCallback;
  self.capture       = true;

  [self.session startRunning];

  return true;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection {
  if(connection == self.videoConnection && self.capture) {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t width   = CVPixelBufferGetWidth(pixelBuffer);
    size_t height  = CVPixelBufferGetHeight(pixelBuffer);

    CGContextRef cgContext = CGBitmapContextCreate(baseAddr, width, height, 8, CVPixelBufferGetBytesPerRow(pixelBuffer), CGColorSpaceCreateDeviceRGB(), kCGImageAlphaNoneSkipLast);

    CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);
    if(!self.frameCallback(cgImage)) {
      [self.session stopRunning];
      // this ensures that we do not try to forward frames that
      // are eventually still queued for processing
      self.capture = false;
      [self.captureStopped broadcast];
    }

    CFRelease(cgImage);
    CGContextRelease(cgContext);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  }
}

@end