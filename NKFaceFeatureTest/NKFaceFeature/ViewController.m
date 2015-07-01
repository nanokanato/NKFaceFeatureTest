//
//  ViewController.m
//  NKFaceFeatureTest
//
//  Created by nanoka____ on 2015/06/22.
//  Copyright (c) 2015年 nanoka____. All rights reserved.
//

#import "ViewController.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

/*========================================================
 ; ViewController
 ========================================================*/
@implementation ViewController{
    UIView *previewView;
    AVCaptureSession *captureSession;
    AVCaptureVideoPreviewLayer *previewLayer;
    AVCaptureVideoDataOutput *videoDataOutput;
    dispatch_queue_t videoDataOutputQueue;
    CIDetector *faceDetector;
}

/*--------------------------------------------------------
 ; dealloc : 解放
 ;      in :
 ;     out :
 --------------------------------------------------------*/
-(void)dealloc
{
    
}

/*--------------------------------------------------------
 ; viewDidAppear : Viewが読み込まれた時
 ;            in :
 ;           out :
 --------------------------------------------------------*/
-(void)viewDidAppear:(BOOL)animated
{
    //撮影開始
    [captureSession startRunning];
}

/*--------------------------------------------------------
 ; viewDidDesappear : Viewが非表示になった時
 ;            in :
 ;           out :
 --------------------------------------------------------*/
-(void)viewDidDisappear:(BOOL)animated
{
    //撮影中止
    [captureSession stopRunning];
}

/*--------------------------------------------------------
 ; viewDidLoad : 初回Viewが読み込まれた時
 ;          in :
 ;         out :
 --------------------------------------------------------*/
-(void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //顔認識準備
    NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
    faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
    
    //プレビュー
    previewView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    [self.view addSubview:previewView];
    
    //カメラ用意
    [self setupAVCapture];
}

/*--------------------------------------------------------
 ; setupAVCapture : カメラ準備
 ;             in :
 ;            out :
 --------------------------------------------------------*/
-(void)setupAVCapture
{
    //セクションの作成
    captureSession = [AVCaptureSession new];
    
    //デバイスの設定
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if ([captureSession canAddInput:deviceInput]) {
        [captureSession addInput:deviceInput];
        [captureSession beginConfiguration];
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
        [captureSession commitConfiguration];
    }
    
    //出力の設定
    videoDataOutput = [AVCaptureVideoDataOutput new];
    NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                       [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    if ( [captureSession canAddOutput:videoDataOutput] ){
        [captureSession addOutput:videoDataOutput];
    }
    [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    
    //プレビューのセット
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    CALayer *rootLayer = [previewView layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:previewLayer];
}

/*--------------------------------------------------------
 ; didOutputSampleBuffer : 撮影画像が送られてくる。
 ;                    in : (AVCaptureOutput *)captureOutput
 ;                   out :
 --------------------------------------------------------*/
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    //画像情報の取得
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
    if (attachments){
        CFRelease(attachments);
    }
    
    //顔認識
    NSDictionary *imageOptions = nil;
    int exifOrientation;
    enum {
        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1,
        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2,
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3,
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4,
        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5,
        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6,
        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7,
        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8
    };
    exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
    imageOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:exifOrientation] forKey:CIDetectorImageOrientation];
    NSArray *features = [faceDetector featuresInImage:ciImage options:imageOptions];
    
    //画像の描画領域の取得
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
    
    //描画
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self drawFaceBoxesForFeatures:features forVideoBox:clap];
    });
}

/*--------------------------------------------------------
 ; drawFaceBoxesForFeatures : 認識した顔に加工する
 ;                       in : (NSArray *)features
 ;                          : (CGRect)clap
 ;                      out :
 --------------------------------------------------------*/
-(void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap
{
    //すでに追加されているレイヤー
    NSArray *sublayers = [NSArray arrayWithArray:[previewLayer sublayers]];
    NSInteger sublayersCount = [sublayers count];
    NSInteger currentSublayer = 0;
    
    //描画内容の用意
    NSString *faceLayerName = @"FaceLayer";
    NSString *rightEyeLayerName = @"RightEyeLayer";
    NSString *leftEyeLayerName = @"LeftEyeLayer";
    NSString *mouthLayerName = @"mouthLayer";
    NSString *noseLayerName = @"noseLayer";
    
    //CALayerのアニメーション開始
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    //レイヤーの非表示
    for ( CALayer *layer in sublayers ) {
        if ( [[layer name] isEqualToString:faceLayerName] ||
            [[layer name] isEqualToString:rightEyeLayerName] ||
            [[layer name] isEqualToString:leftEyeLayerName] ||
            [[layer name] isEqualToString:mouthLayerName] ||
            [[layer name] isEqualToString:noseLayerName]) {
            layer.hidden = YES;
        }
    }
    
    //描画領域の取得
    CGSize parentFrameSize = [self.view frame].size;
    NSString *gravity = [previewLayer videoGravity];
    CGRect previewBox = [ViewController videoPreviewBoxForGravity:gravity
                                                        frameSize:parentFrameSize
                                                     apertureSize:clap.size];
    
    //表示サイズとの比率
    CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
    CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
    
    //取得した顔認証のデータを解読
    for(CIFaceFeature *faceFeature in features ) {
        /*-----------------
         輪郭の位置を描画
         -----------------*/
        //輪郭の位置を取得
        CGRect faceRect = [faceFeature bounds];
        //
        CGFloat temp = faceRect.size.width;
        faceRect.size.width = faceRect.size.height;
        faceRect.size.height = temp;
        temp = faceRect.origin.x;
        faceRect.origin.x = faceRect.origin.y;
        faceRect.origin.y = temp;
        faceRect.size.width *= widthScaleBy;
        faceRect.size.height *= heightScaleBy;
        faceRect.origin.x *= widthScaleBy;
        faceRect.origin.y *= heightScaleBy;
        CALayer *faceLayer = nil;
        while ( !faceLayer && (currentSublayer < sublayersCount) ) {
            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
            if ( [[currentLayer name] isEqualToString:faceLayerName] ) {
                faceLayer = currentLayer;
                [currentLayer setHidden:NO];
            }
        }
        if (!faceLayer) {
            faceLayer = [CALayer new];
            faceLayer.borderWidth = 1.0;
            faceLayer.borderColor = [UIColor greenColor].CGColor;
            [faceLayer setName:faceLayerName];
            [previewLayer addSublayer:faceLayer];
        }
        [faceLayer setFrame:faceRect];
        
        /*---------------
         右目の位置を描画
         ---------------*/
        if(faceFeature.hasRightEyePosition){
            CGRect rightEyeRect;
            
            //画像上での中心座標を設定
            CGPoint rightEyePosition = CGPointMake(faceFeature.rightEyePosition.y, faceFeature.rightEyePosition.x);
            rightEyeRect.origin.x = rightEyePosition.x;
            rightEyeRect.origin.y = rightEyePosition.y;
            
            //サイズを設定
            CGSize rightEyeSize = CGSizeMake(faceLayer.bounds.size.width/1.1, faceLayer.bounds.size.height/1.7);
            rightEyeRect.origin.x -= rightEyeSize.width/2;
            rightEyeRect.origin.y -= rightEyeSize.height/2;
            rightEyeRect.size = rightEyeSize;
            
            //比率を変更
            rightEyeRect.size.width *= widthScaleBy;
            rightEyeRect.size.height *= heightScaleBy;
            rightEyeRect.origin.x *= widthScaleBy;
            rightEyeRect.origin.y *= heightScaleBy;
            
            //レイヤーを検索
            CALayer *rightEyeLayer = nil;
            while ( !rightEyeLayer && (currentSublayer < sublayersCount) ) {
                CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
                if ( [[currentLayer name] isEqualToString:rightEyeLayerName] ) {
                    rightEyeLayer = currentLayer;
                    currentLayer.hidden = NO;
                }
            }
            if (!rightEyeLayer) {
                rightEyeLayer = [CALayer new];
                rightEyeLayer.borderWidth = 1.0;
                rightEyeLayer.borderColor = [UIColor yellowColor].CGColor;
                [rightEyeLayer setName:rightEyeLayerName];
                [previewLayer addSublayer:rightEyeLayer];
            }
            [rightEyeLayer setFrame:rightEyeRect];
        }
        
        /*---------------
         左目の位置を描画
         ---------------*/
        if(faceFeature.hasLeftEyePosition){
            CGRect leftEyeRect;
            
            //画像上での中心座標を設定
            CGPoint leftEyePosition = CGPointMake(faceFeature.leftEyePosition.y, faceFeature.leftEyePosition.x);
            leftEyeRect.origin.x = leftEyePosition.x;
            leftEyeRect.origin.y = leftEyePosition.y;
            
            //サイズを設定
            CGSize leftEyeSize = CGSizeMake(faceLayer.bounds.size.width/1.1, faceLayer.bounds.size.height/1.7);
            leftEyeRect.origin.x -= leftEyeSize.width/2;
            leftEyeRect.origin.y -= leftEyeSize.height/2;
            leftEyeRect.size = leftEyeSize;
            
            //比率を変更
            leftEyeRect.size.width *= widthScaleBy;
            leftEyeRect.size.height *= heightScaleBy;
            leftEyeRect.origin.x *= widthScaleBy;
            leftEyeRect.origin.y *= heightScaleBy;
            
            //レイヤーを検索
            CALayer *leftEyeLayer = nil;
            while ( !leftEyeLayer && (currentSublayer < sublayersCount) ) {
                CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
                if ( [[currentLayer name] isEqualToString:leftEyeLayerName] ) {
                    leftEyeLayer = currentLayer;
                    currentLayer.hidden = NO;
                }
            }
            if (!leftEyeLayer) {
                leftEyeLayer = [CALayer new];
                leftEyeLayer.borderWidth = 1.0;
                leftEyeLayer.borderColor = [UIColor blueColor].CGColor;
                [leftEyeLayer setName:leftEyeLayerName];
                [previewLayer addSublayer:leftEyeLayer];
            }
            [leftEyeLayer setFrame:leftEyeRect];
        }
        
        /*---------------
         口の位置を描画
         ---------------*/
        if(faceFeature.hasMouthPosition){
            CGRect mouthRect;
            
            //画像上での中心座標を設定
            CGPoint mouthPosition = CGPointMake(faceFeature.mouthPosition.y, faceFeature.mouthPosition.x);
            mouthRect.origin.x = mouthPosition.x;
            mouthRect.origin.y = mouthPosition.y;
            
            //サイズを設定
            CGSize mouthSize = CGSizeMake(faceLayer.bounds.size.width/0.8, faceLayer.bounds.size.height/1.4);
            mouthRect.origin.x -= mouthSize.width/2;
            mouthRect.origin.y -= mouthSize.height/2;
            mouthRect.size = mouthSize;
            
            //比率を変更
            mouthRect.size.width *= widthScaleBy;
            mouthRect.size.height *= heightScaleBy;
            mouthRect.origin.x *= widthScaleBy;
            mouthRect.origin.y *= heightScaleBy;
            
            //レイヤーを検索
            CALayer *mouthLayer = nil;
            while ( !mouthLayer && (currentSublayer < sublayersCount) ) {
                CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
                if ( [[currentLayer name] isEqualToString:mouthLayerName] ) {
                    mouthLayer = currentLayer;
                    currentLayer.hidden = NO;
                }
            }
            if (!mouthLayer) {
                mouthLayer = [CALayer new];
                mouthLayer.borderWidth = 1.0;
                mouthLayer.borderColor = [UIColor redColor].CGColor;
                [mouthLayer setName:mouthLayerName];
                [previewLayer addSublayer:mouthLayer];
            }
            [mouthLayer setFrame:mouthRect];
        }
        /*---------------
         鼻の位置を描画
         ---------------*/
        if(faceFeature.hasRightEyePosition && faceFeature.hasLeftEyePosition && faceFeature.hasMouthPosition){
            //右目の中心座標
            CGPoint rightEyePosition = CGPointMake(faceFeature.rightEyePosition.y, faceFeature.rightEyePosition.x);
            rightEyePosition.x *= widthScaleBy;
            rightEyePosition.y *= heightScaleBy;
            
            //左目の中心座標
            CGPoint leftEyePosition = CGPointMake(faceFeature.leftEyePosition.y, faceFeature.leftEyePosition.x);
            leftEyePosition.x *= widthScaleBy;
            leftEyePosition.y *= heightScaleBy;
            
            //口の中心座標
            CGPoint mouthPosition = CGPointMake(faceFeature.mouthPosition.y, faceFeature.mouthPosition.x);
            mouthPosition.x *= widthScaleBy;
            mouthPosition.y *= heightScaleBy;
            
            //右目と左目の中点座標を求める
            CGFloat eyeCenterPositionX = (rightEyePosition.x+leftEyePosition.x)/2;
            CGFloat eyeCenterPositionY = (rightEyePosition.y+leftEyePosition.y)/2;
            CGPoint eyeCenterPosition = CGPointMake(eyeCenterPositionX, eyeCenterPositionY);
            
            //右目と左目でできる円弧の二等分線の角度を求める
            CGFloat eyeBisector = atan((leftEyePosition.y-rightEyePosition.y)/(leftEyePosition.x-rightEyePosition.x))+90;
            
            //左目と口の中点座標を求める
            CGFloat mouthAndLeftEyeCneterPositionX = (leftEyePosition.x+mouthPosition.x)/2;
            CGFloat mouthAndLeftEyeCneterPositionY = (leftEyePosition.y+mouthPosition.y)/2;
            CGPoint mouthAndLeftEyeCneterPosition = CGPointMake(mouthAndLeftEyeCneterPositionX, mouthAndLeftEyeCneterPositionY);
            
            //左目と口でできる円弧の二等分線の角度を求める
            CGFloat mouthAndLeftEyeBisector = atan((mouthPosition.y-leftEyePosition.y)/(mouthPosition.x-leftEyePosition.x))+90;
            
            //鼻の中心座標を取得
            CGFloat noseX = eyeCenterPosition.x+((mouthAndLeftEyeCneterPosition.y-eyeCenterPosition.y)-(mouthAndLeftEyeCneterPosition.x-eyeCenterPosition.x)*tan(mouthAndLeftEyeBisector))/(tan(eyeBisector)-tan(mouthAndLeftEyeBisector));
            CGFloat noseY = eyeCenterPosition.y+(noseX-eyeCenterPosition.x)*tan(eyeBisector);
            CGPoint nosePosition = CGPointMake(noseX, noseY);
            
            //中心座標補正
            CGSize noseSize = CGSizeMake(faceLayer.bounds.size.width/1.4*widthScaleBy, faceLayer.bounds.size.height/1.1*heightScaleBy);
            nosePosition.x += noseSize.width/2;
            nosePosition.y -= noseSize.height/8;
            CGRect noseRect;
            noseRect.origin = nosePosition;
            
            //鼻のサイズを設定
            noseRect.origin.x -= noseSize.width/2;
            noseRect.origin.y -= noseSize.height/2;
            noseRect.size = noseSize;
            
            //レイヤーを検索
            CALayer *noseLayer = nil;
            while ( !noseLayer && (currentSublayer < sublayersCount) ) {
                CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
                if ( [[currentLayer name] isEqualToString:noseLayerName] ) {
                    noseLayer = currentLayer;
                    currentLayer.hidden = NO;
                }
            }
            if (!noseLayer) {
                noseLayer = [CALayer new];
                noseLayer.borderWidth = 1.0;
                noseLayer.borderColor = [UIColor purpleColor].CGColor;
                [noseLayer setName:noseLayerName];
                [previewLayer addSublayer:noseLayer];
            }
            [noseLayer setFrame:noseRect];
        }
    }
    
    [CATransaction commit];
}

/*--------------------------------------------------------
 ; videoPreviewBoxForGravity : プレビューのサイズ取得
 ;                        in : (NSString *)gravity
 ;                           : (CGSize)frameSize
 ;                           : (CGSize)apertureSize
 ;                       out : (CGRect)videoBox
 --------------------------------------------------------*/
+(CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
	if([gravity isEqualToString:AVLayerVideoGravityResizeAspect]){
		if(viewRatio > apertureRatio){
			size.width = apertureSize.height * (frameSize.height / apertureSize.width);
			size.height = frameSize.height;
		}else{
			size.width = frameSize.width;
			size.height = apertureSize.width * (frameSize.width / apertureSize.height);
		}
	}

	CGRect videoBox;
	videoBox.size = size;
    if(size.width < frameSize.width){
		videoBox.origin.x = (frameSize.width - size.width) / 2;
    }else{
		videoBox.origin.x = (size.width - frameSize.width) / 2;
    }
	
    if(size.height < frameSize.height){
		videoBox.origin.y = (frameSize.height - size.height) / 2;
    }else{
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    }
    
	return videoBox;
}

@end