#import "QrcodePlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <libkern/OSAtomic.h>

//
// 二维码识别插件
//


// 屏幕分辨率枚举类型
typedef enum {
    veryLow,
    low,
    medium,
    high,
    veryHigh,
    ultraHigh,
    max,
} ResolutionPreset;

// 将屏幕分辨率枚举类型转换为字符串描述
static ResolutionPreset getResolutionPresetForString(NSString *preset) {
    if ([preset isEqualToString:@"veryLow"]) {
        return veryLow;
    } else if ([preset isEqualToString:@"low"]) {
        return low;
    } else if ([preset isEqualToString:@"medium"]) {
        return medium;
    } else if ([preset isEqualToString:@"high"]) {
        return high;
    } else if ([preset isEqualToString:@"veryHigh"]) {
        return veryHigh;
    } else if ([preset isEqualToString:@"ultraHigh"]) {
        return ultraHigh;
    } else if ([preset isEqualToString:@"max"]) {
        return max;
    } else {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey : [NSString
                                                                                 stringWithFormat:@"Unknown resolution preset %@", preset]
                                                    }];
        @throw error;
    }
}

// 将NSError转换为FlutterError
static FlutterError *getFlutterError(NSError *error) {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)error.code]
                               message:error.localizedDescription
                               details:error.domain];
}

// 相机操作封装
@interface FLTCam : NSObject<FlutterTexture,
                            AVCaptureVideoDataOutputSampleBufferDelegate,
                            AVCaptureAudioDataOutputSampleBufferDelegate,
                            FlutterStreamHandler>
@property(readonly, nonatomic) int64_t textureId;
@property(nonatomic, copy) void (^onFrameAvailable)();
@property BOOL enableAudio;
@property(nonatomic) FlutterEventChannel *eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCapturePhotoOutput *capturePhotoOutput;
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) AVCaptureInput *captureVideoInput;
@property(readonly, nonatomic) AVCaptureMetadataOutput *captureMetadataOutput;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;
@property(readonly, nonatomic) CGSize previewSize;
@property(readonly, nonatomic) CGSize captureSize;
@property(readonly, nonatomic) BOOL isStreamingImages;
@property(readonly, nonatomic) ResolutionPreset resolutionPreset;
@property(nonatomic) CMMotionManager *motionManager;
@property(assign, nonatomic) BOOL volatile isPreviewing;
@property(strong, nonatomic) FlutterMethodChannel *channel;
@property(strong, nonatomic) NSArray *codeFormats;


// 根据相机标识初始化对应相机设备
- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                       enableAudio:(BOOL)enableAudio
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                     methodChannel:(FlutterMethodChannel *)channel
                       codeFormats:(NSArray *)codeFormats
                             error:(NSError **)error;

// 开始预览
- (void)start;

// 停止预览
- (void)stop;

@end

@implementation FLTCam {
    dispatch_queue_t _dispatchQueue;
}

// Format used for video and image streaming.
FourCharCode const videoFormat = kCVPixelFormatType_32BGRA;

// 相机初始化
-(instancetype)initWithCameraName:(NSString *)cameraName
                 resolutionPreset:(NSString *)resolutionPreset
                      enableAudio:(BOOL)enableAudio
                    dispatchQueue:(dispatch_queue_t)dispatchQueue
                    methodChannel:(FlutterMethodChannel *)channel
                      codeFormats:(NSArray *)codeFormats
                            error:(NSError *__autoreleasing *)error {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    
    @try {
        _resolutionPreset = getResolutionPresetForString(resolutionPreset);
    } @catch (NSError *e) {
        *error = e;
    }
    
    _enableAudio = enableAudio;
    _dispatchQueue = dispatchQueue;
    _captureSession = [[AVCaptureSession alloc] init];
    _captureDevice = [AVCaptureDevice deviceWithUniqueID:cameraName];
    
    NSError *localError = nil;
    _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice
                                                               error:&localError];
    if(localError) {
        *error = localError;
        return nil;
    }
    
    _captureVideoOutput = [AVCaptureVideoDataOutput new];
    _captureVideoOutput.videoSettings =
    @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(videoFormat)};
    [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    AVCaptureConnection *connection = [AVCaptureConnection connectionWithInputPorts:_captureVideoInput.ports
                                                                             output:_captureVideoOutput];
    
    if([_captureDevice position] == AVCaptureDevicePositionFront) {
        connection.videoMirrored = YES;
    }
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [_captureSession addInputWithNoConnections:_captureVideoInput];
    [_captureSession addOutputWithNoConnections:_captureVideoOutput];
    [_captureSession addConnection:connection];
    
    _capturePhotoOutput = [AVCapturePhotoOutput new];
    [_capturePhotoOutput setHighResolutionCaptureEnabled:YES];
    [_captureSession addOutput:_capturePhotoOutput];
    
    _motionManager = [[CMMotionManager alloc] init];
    [_motionManager startAccelerometerUpdates];
    
    [self setCaptureSessionPreset:_resolutionPreset];
    
    // 条码识别设置
    _channel = channel;
    _codeFormats = codeFormats;
    _captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [_captureSession addOutput:_captureMetadataOutput];
    
    NSDictionary<NSString *, AVMetadataObjectType> *availableFormats = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                                        AVMetadataObjectTypeCode39Code,@"code39",
                                                                        AVMetadataObjectTypeCode93Code,@"code93",
                                                                        AVMetadataObjectTypeCode128Code, @"code128",
                                                                        AVMetadataObjectTypeEAN8Code,  @"ean8",
                                                                        AVMetadataObjectTypeEAN13Code,@"ean13",
                                                                        AVMetadataObjectTypeEAN13Code,@"itf",
                                                                        AVMetadataObjectTypeUPCECode,@"upce",
                                                                        AVMetadataObjectTypeAztecCode,@"aztec",
                                                                        AVMetadataObjectTypeDataMatrixCode,@"datamatrix",
                                                                        AVMetadataObjectTypePDF417Code, @"pdf417",
                                                                        AVMetadataObjectTypeQRCode, @"qr",
                                                                        nil];
    
    NSMutableArray<AVMetadataObjectType> *reqFormats = [[NSMutableArray alloc] init];
    for(NSString *f in codeFormats) {
        NSLog(@"Support code format is %@", f);
        if([availableFormats valueForKey:f] != nil) {
            [reqFormats addObject:[availableFormats valueForKey:f]];
        }
    }

    [_captureMetadataOutput setMetadataObjectTypes:reqFormats];
    [_captureMetadataOutput setMetadataObjectsDelegate:self queue:_dispatchQueue];
    
    return self;
}

- (void)start {
    _isPreviewing = true;
    [_captureSession startRunning];
}

- (void)stop {
    _isPreviewing = false;
    [_captureSession stopRunning];
}

- (void)close {
    [_captureSession stopRunning];
    for(AVCaptureInput *input in [_captureSession inputs]) {
        [_captureSession removeInput:input];
    }
    for(AVCaptureOutput *output in [_captureSession outputs]) {
        [_captureSession removeOutput:output];
    }
}

// FlutterTexture协议方法实现
- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef pixelBuffer = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, nil, (void **)&_latestPixelBuffer)) {
        pixelBuffer = _latestPixelBuffer;
    }
    
    return pixelBuffer;
}

// FlutterStreamHandler协议方法实现
- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    // need to unregister stream handler when disposing the camera
    [_eventChannel setStreamHandler:nil];
    return nil;
}

// FlutterStreamHandler协议方法实现
- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

// AVCaptureVideoDataOutputSampleBufferDelegate协议方法实现
// 预览图像输出
- (void)captureOutput:(AVCaptureOutput *)output
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if(output == _captureVideoOutput) {
        CVPixelBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFRetain(newBuffer);
        CVPixelBufferRef old = _latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(old
                                                 , newBuffer
                                                 , (void **)&_latestPixelBuffer)) {
            old = _latestPixelBuffer;
        }
        if(old != nil) {
            CFRelease(old);
        }
        if(_onFrameAvailable) {
            _onFrameAvailable();
        }
    }
    if(!CMSampleBufferDataIsReady(sampleBuffer)) {
        _eventSink(@{
                     @"event":@"error",
                     @"errorDescription":@"sample buffer is not ready, Skipping sample"
                     }
        );
        return;
    }
}

// 条码图片识别图像输出
- (void)captureOutput:(AVCaptureOutput *)output
                        didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
                        fromConnection:(AVCaptureConnection *)connection {
    if (metadataObjects != nil && [metadataObjects count] > 0) {
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
        if (_isPreviewing) {
            [self performSelectorOnMainThread:@selector(stopPreviewingWithResult:) withObject:[metadataObj stringValue] waitUntilDone:NO];
        }
    }
}


- (void)stopPreviewingWithResult:(NSString*)result {
    if (![result  isEqual: @""] && _isPreviewing) {
        [_channel invokeMethod:@"scanSuccess" arguments:result];
        [self stop];
    }
}

- (void)dealloc {
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
    [_motionManager stopAccelerometerUpdates];
}

// 设置相机分辨率
- (void)setCaptureSessionPreset:(ResolutionPreset)resolutionPreset {
    switch (resolutionPreset) {
        case max:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
                _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
                _previewSize =
                CGSizeMake(_captureDevice.activeFormat.highResolutionStillImageDimensions.width,
                           _captureDevice.activeFormat.highResolutionStillImageDimensions.height);
                break;
            }
        case ultraHigh:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset3840x2160;
                _previewSize = CGSizeMake(3840, 2160);
                break;
            }
        case veryHigh:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                _previewSize = CGSizeMake(1920, 1080);
                break;
            }
        case high:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
                _previewSize = CGSizeMake(1280, 720);
                break;
            }
        case medium:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
                _previewSize = CGSizeMake(640, 480);
                break;
            }
        case low:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset352x288]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset352x288;
                _previewSize = CGSizeMake(352, 288);
                break;
            }
        default:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetLow]) {
                _captureSession.sessionPreset = AVCaptureSessionPresetLow;
                _previewSize = CGSizeMake(352, 288);
            } else {
                NSError *error =
                [NSError errorWithDomain:NSCocoaErrorDomain
                                    code:NSURLErrorUnknown
                                userInfo:@{
                                           NSLocalizedDescriptionKey :
                                               @"No capture session available for current capture session."
                                           }];
                @throw error;
            }
    }
}

@end


@interface QrcodePlugin()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) FLTCam *camera;
@property(readonly, nonatomic) FlutterMethodChannel *channel;
@end

@implementation QrcodePlugin {
    // 插件方法执行队列，在其他的分发队列中执行来避免阻塞UI
    dispatch_queue_t _dispatchQueue;
}

// 向框架注册插件
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"com.qfpay.flutter.plugin/qrcode_plugin"
            binaryMessenger:[registrar messenger]];
  QrcodePlugin* instance = [[QrcodePlugin alloc] initWithRegistry:[registrar textures] messenger:[registrar messenger] methodChannel:channel];
    // 添加插件方法回调
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                       messenger:(NSObject<FlutterBinaryMessenger> *) messenger
                   methodChannel:(FlutterMethodChannel *)channel{
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registry = registry;
    _messenger = messenger;
    _channel = channel;
    return self;
}

// 插件方法回调实现
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if(_dispatchQueue == nil) {
        _dispatchQueue = dispatch_queue_create("com.qfpay.flutter.plugin.qrcode.dispatchqueue", NULL);
    }
    
    //通过额外的分发队列，实现插件方法的异步执行
    dispatch_async(_dispatchQueue, ^{[self handleMethodCallAsync:call result:result];});
}

- (void)handleMethodCallAsync:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString* methodName = call.method;
    NSLog(@"Flutter method call name is %@", methodName);
    
    if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else if([@"availableCameras" isEqualToString:call.method]) {
        // 获取可用相机列表
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                             discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                                                             mediaType:AVMediaTypeVideo
                                                             position:AVCaptureDevicePositionUnspecified];
        NSArray<AVCaptureDevice *> *devices = discoverySession.devices;
        NSLog(@"camera count is %ld", devices.count);
        NSMutableArray<NSDictionary<NSString*, NSObject *> *> *reply = [[NSMutableArray alloc] initWithCapacity:devices.count];
        for(AVCaptureDevice *device in devices) {
            NSString *lensFacing;
            switch ([device position]) {
                case AVCaptureDevicePositionBack:
                    lensFacing = @"back";
                    break;
                case AVCaptureDevicePositionFront:
                    lensFacing = @"front";
                    break;
                case AVCaptureDevicePositionUnspecified:
                    lensFacing = @"external";
                    break;
            }
            
            [reply addObject:@{@"name" : [device uniqueID],
             @"lensFacing" : lensFacing,
             @"sensorOrientation" : @90,}];
        }
        
        result(reply);
    } else if([@"initialize" isEqualToString:call.method]) {
        // 初始化相机并开始预览
        NSString *cameraName = call.arguments[@"cameraName"];
        NSString *resolutionPreset = call.arguments[@"resolutionPreset"];
        NSNumber *enableAudio = call.arguments[@"enableAudio"];
        NSArray *formats = call.arguments[@"codeFormats"];
        NSError *error;
        FLTCam *cam = [[FLTCam alloc] initWithCameraName:cameraName
                                        resolutionPreset:resolutionPreset
                                             enableAudio:[enableAudio boolValue]
                                           dispatchQueue:_dispatchQueue
                                           methodChannel:_channel
                                             codeFormats:formats
                                                   error:&error];
        NSLog(@"camera name is %@", cameraName);
        if(error) {
            result(getFlutterError(error));
        } else {
            if(_camera) {
                [_camera close];
            }
            int64_t textureId = [_registry registerTexture:cam];
            _camera = cam;
            cam.onFrameAvailable = ^{
                [_registry textureFrameAvailable:textureId];
            };
            FlutterEventChannel *eventChannel = [FlutterEventChannel
                                                 eventChannelWithName:[NSString stringWithFormat:@"com.qfpay.flutter.plugin/camera_event_%lld", textureId]
                                                                          binaryMessenger:_messenger];
            [eventChannel setStreamHandler:cam];
            cam.eventChannel = eventChannel;
            result(@{
                     @"textureId" : @(textureId),
                     @"previewWidth":@(cam.previewSize.width),
                     @"previewHeight":@(cam.previewSize.height),
                     @"captureWidth":@(cam.captureSize.width),
                     @"captureHeight":@(cam.captureSize.height),
                     });
            [cam start];
        }
    } else if([@"startPreview" isEqualToString: call.method]) {
        // 开始预览
        if(_camera) {
            [_camera start];
        }
    } else if([@"stopPreview" isEqualToString: call.method]) {
        // 停止预览
        if(_camera) {
            [_camera stop];
        }
    } else if([@"dispose" isEqualToString: call.method]) {
        // 页面销毁
        NSDictionary *argsMap = call.arguments;
        NSUInteger textureId = ((NSNumber *)argsMap[@"textureId"]).unsignedIntegerValue;
        
        [_registry unregisterTexture:textureId];
        [_camera close];
        _dispatchQueue = nil;
        result(nil);
    } else{
        result(FlutterMethodNotImplemented);
    }
}

@end
