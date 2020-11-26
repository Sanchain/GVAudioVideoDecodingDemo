//
//  GVVideoDecodeController.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/24.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVVideoDecodeController.h"

#import "OpenGLView20.h"
#import "XDXPreviewView.h"

#import "GVVideoDecoder.h"
#import "GVAudioDecoder.h"

#import "XDXAudioQueuePlayer.h"
#import "XDXQueueProcess.h"

#import "GVAVParseHandler.h"


#define kBufferSize 4096



@interface GVVideoDecodeController ()<GVVideoDecodeDelegate, GVAudioDecodeDelegate>
@property (nonatomic, strong) OpenGLView20 *glView; //  OPENGL ES View
@property (nonatomic, strong) XDXPreviewView *previewView; // OPENGL ES View
@end



@implementation GVVideoDecodeController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initOpenGLView];
    [self configureAudioPlayer];
    
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // http://192.168.0.1/sd//front_norm/2020_09_27_094605_00.MP4
        // rtsp://192.168.0.1:554/livestream/5
//        GVAVParseHandler *parseHandler = [[GVAVParseHandler alloc] initWithFilePath:@"http://192.168.0.1/sd//front_norm/2020_09_28_145843_00.MP4" isNetworkStream:YES];
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"testH264.MOV" ofType:nil];
        GVAVParseHandler *parseHandler = [[GVAVParseHandler alloc] initWithFilePath:filePath isNetworkStream:NO];

        // 视频解码工具初始化
        GVVideoDecoder *videoDecoder = [[GVVideoDecoder alloc] initWithFormatContext:[parseHandler getFormatContext] videoStreamIndex:[parseHandler getVideoStreamIndex] delegate:self];
        
        // 音频解码工具初始化
        GVAudioDecoder *audioDecoder = [[GVAudioDecoder alloc] initWithFormatContext:[parseHandler getFormatContext] audioStreamIndex:[parseHandler getAudioStreamIndex] delegate:self];
        // 配置原生 Audio Queue Player
//        [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithBufferSize:kBufferSize];
//        [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
        
        // 获取音视频裸流数据 AVPacket
        static BOOL isFindIDR = NO;
        [parseHandler startParseGetAVPackeWithCompletionHandler:^(BOOL isVideoFrame, BOOL isFinish, AVPacket packet) {
            if (isFinish) {
                NSLog(@"音视频已全部解码完成的回调");
                isFindIDR = NO;
                [videoDecoder stopDecoder];
                [audioDecoder stopDecoder];
                return;
            }
            if (isVideoFrame) {
                if (packet.flags == 1 && isFindIDR == NO) {
                    isFindIDR = YES;
                    NSLog(@"发现了 IDR 帧");
                }
                
                if (!isFindIDR) {
                    return;
                }
                [videoDecoder startDecodeVideoDataWithAVPacket:&packet];
            } else {
                [audioDecoder startDecodeAudioDataWithAVPacket:&packet];
            }
        }];
    });
    
    //
//    [self decodeAudioStream];
}


#pragma mark - GVVideoDecodeDelegate Decode Callback
 
/*获取视频解码后的YUV数据
 @data        解码后的 YUV 数据
 @frameWidth  视频帧的宽度
 @frameHeight 视频帧的高度
 */
- (void)getDecodeVideoDataByFFmpeg:(void *)data frameWidth:(int)frameWidth frameHeight:(int)frameHeight {
    
    // 这是其中一个 OPENGL 渲染视图（不完善，音视频不同步）
    NSLog(@"OLD OPENGL ES 视频渲染");
    [self.glView setVideoSize:frameWidth height:frameHeight];
    [self.glView displayYUV420pData:data width:frameWidth height:frameHeight];
}

- (void)getDecodeVideoDataByFFmpeg:(CMSampleBufferRef)sampleBuffer {
    
//    NSLog(@"NEW OPENGL ES 视频渲染");
    CVPixelBufferRef pix = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self.previewView displayPixelBuffer:pix];
}


#pragma mark - GVAudioDecodeDelegate Decode Callback

/*YUV视频原始数据封装为CMSampleBufferRef数据结构并传给OpenGL以将视频渲染到屏幕上
 获取解码后的音频数据
 并用于在原生 Audio queue 队列里播放
 */
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size pts:(int64_t)pts {
    /*
    NSLog(@"解码音频AAC码流的数据回调 size : %d", size);
    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
    if (node == NULL) {
        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
        return;
    }
    node->pts  = pts;
    node->size = size;
    memcpy(node->data, data, size);
    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);

    NSLog(@"Test Data in ,  work size = %d, free size = %d !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size);
    */
    
    [self decodeAudioDataByFFmpeg:data size:size pts:pts];
}

- (void)decodeAudioDataByFFmpeg:(void *)data size:(int)size pts:(int64_t)pts {
    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
    if (node == NULL) {
//        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
        return;
    }
    node->pts  = pts;
    node->size = size;
    memcpy(node->data, data, size);
    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);
//    NSLog(@"Test Data in ,  work size = %d, free size = %d , pts:%lld !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size, pts);
}


#pragma mark - Configure

- (void)configureAudioPlayer {
    // Final Audio Player format : This is only for the FFmpeg to decode.
    AudioStreamBasicDescription ffmpegAudioFormat = {
        .mSampleRate         = 48000,
        .mFormatID           = kAudioFormatLinearPCM,
        .mChannelsPerFrame   = 2,
        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBitsPerChannel     = 16,
        .mBytesPerPacket     = 4,
        .mBytesPerFrame      = 4,
        .mFramesPerPacket    = 1,
    };
    
    // Final Audio Player format : This is only for audio converter format.
//    AudioStreamBasicDescription systemAudioFormat = {
//        .mSampleRate         = 48000,
//        .mFormatID           = kAudioFormatLinearPCM,
//        .mChannelsPerFrame   = 1,
//        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
//        .mBitsPerChannel     = 16,
//        .mBytesPerPacket     = 2,
//        .mBytesPerFrame      = 2,
//        .mFramesPerPacket    = 1,
//    };
    
    // Configure Audio Queue Player
    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithAudioFormat:&ffmpegAudioFormat bufferSize:kBufferSize];
    [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
}

- (void)initOpenGLView {
    // 初始化视频渲染视图1
    CGFloat width = self.view.bounds.size.width-40;
    CGFloat height = width*9/16;
//    self.previewView = [[XDXPreviewView alloc] initWithFrame:CGRectMake(20, 80, self.view.bounds.size.width-40, height)];
    self.previewView = [[XDXPreviewView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.previewView];
    
    // 初始化视频渲染视图2
    [self.view addSubview:self.glView];
    [self.glView.layer setBorderWidth:1.0];
    [self.glView.layer setBorderColor:[UIColor redColor].CGColor];
}



#pragma mark - 测试解码 音视频

- (void)decodeAudioStream {
    // 解码音频AAC码流
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"audio" ofType:@"aac"];
    [[GVAudioDecoder shareInstance] audioDecodeWithInputFile:filePath delegate:self];
    // 配置原生 Audio Queue Player
//    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithBufferSize:kBufferSize];
//    [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
}

#pragma mark - 懒加载

- (OpenGLView20 *)glView {
    if (!_glView) {
        // 初始化
        CGFloat width = self.view.bounds.size.width-40;
        CGFloat height = width*9/16;
        OpenGLView20 *glView = [[OpenGLView20 alloc] initWithFrame:CGRectMake(20, 80, self.view.bounds.size.width-40, height)];
        // 设置视频原始尺寸
        [glView setVideoSize:352 height:288];
        _glView = glView;
    }
    return _glView;
}


@end
//
