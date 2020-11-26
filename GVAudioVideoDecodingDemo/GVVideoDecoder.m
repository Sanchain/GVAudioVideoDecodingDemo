//
//  GVVideoDecoder.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/24.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVVideoDecoder.h"


@interface GVVideoDecoder ()
{
    // 视频部分
    AVFormatContext* m_formatContext;
//    char* m_pBuffer;
    AVCodecContext  *m_videoCodecContext;
    AVFrame         *m_videoFrame;         // 解码后的视频帧数据，里面存的是YUV数据
    
    //
    int got_picture;                    // 解码视频帧是否成功
    int n_frame;                        // 解码到第几帧
    int first_time;                     // 记录第一帧
    int m_videoStreamIndex;
    int avpacketCount;
    int avframeCount;
    double pts;
}

@property (nonatomic, weak) id<GVVideoDecodeDelegate> delegate ; //
@end


@implementation GVVideoDecoder

+ (instancetype)shareInstance {
    
    static GVVideoDecoder *audioDecoder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioDecoder = [[GVVideoDecoder alloc] init];
    });
    return audioDecoder;
}

- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext
                     videoStreamIndex:(int)videoStreamIndex
                             delegate:(id<GVVideoDecodeDelegate>)delegate {
    
    if (self = [super init]) {
        self.delegate = delegate;
        [self videoDecodeWithFormatContext:formatContext videoStreamIndex:videoStreamIndex];
    }
    return self;
}

- (void)videoDecodeWithFormatContext:(AVFormatContext *)formatContext videoStreamIndex:(int)videoStreamIndex {

    m_formatContext = formatContext;
    m_videoStreamIndex = videoStreamIndex;
    first_time = 1;
    
    // 查找 video stream 相对应的解码器 avcodec_find_decoder(获取音频解码器上下文和解码器)
    // 新API
    
    AVCodec *codec = NULL;
    const char *codecName = av_hwdevice_get_type_name(AV_HWDEVICE_TYPE_VIDEOTOOLBOX); // 硬解码
    enum AVHWDeviceType type = av_hwdevice_find_type_by_name(codecName);
    if (type != AV_HWDEVICE_TYPE_VIDEOTOOLBOX) {
        NSLog(@"%s: Not find hardware codec. current codec :%d", __func__, type);
        return;
    }
    // 音视频对应的stream_index
    int ret = av_find_best_stream(m_formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (ret < 0) {
        NSLog(@"av_find_best_stream faliture");
        return;
    }
    // 创建AVCodecContext结构体
    m_videoCodecContext = avcodec_alloc_context3(codec);
    if (!m_videoCodecContext){
        NSLog(@"avcodec_alloc_context3 faliture");
        return;
    }
    // 将音视频流信息拷贝到新的 AVCodecContext 结构体中
    ret = avcodec_parameters_to_context(m_videoCodecContext, m_formatContext->streams[m_videoStreamIndex]->codecpar);
    if (ret < 0){
        NSLog(@"avcodec_parameters_to_context faliture");
        return;
    }
    
    ret = InitHardwareDecoder(m_videoCodecContext, type);
    if (ret < 0){
        NSLog(@"hw_decoder_init faliture");
        return;
    }
    
    ret = avcodec_open2(m_videoCodecContext, codec, NULL);
    if (ret < 0) {
        NSLog(@"avcodec_open2 faliture");
        return;
    }
     
        
    // 旧 API 软解
//    m_videoCodecContext = m_formatContext->streams[m_videoStreamIndex]->codec;
//    AVCodec *codec = avcodec_find_decoder(m_videoCodecContext->codec_id);
//    if (!codec) {
//        NSLog(@"Not find video codec");
//        return;
//    }
//    if (avcodec_open2(m_videoCodecContext, codec, NULL) < 0) {
//        NSLog(@"Can't open video codec");
//        return;
//    }
//    if (!m_videoCodecContext) {
//        NSLog(@"create video codec failed");
//        return;
//    }
    
    
    // Get video frame
    m_videoFrame = av_frame_alloc();
    if (!m_videoFrame) {
        NSLog(@"alloc video frame failed");
        avcodec_close(m_videoCodecContext);
    }
}


// 解码H264裸流
- (void)startDecodeVideoDataWithAVPacket:(AVPacket *)packet {
    
    AVStream *videoStream = m_formatContext->streams[m_videoStreamIndex];
//    int fps = DecodeGetAVStreamFPSTimeBase(videoStream);
//    NSLog(@"解码视频帧的 fps :%d", fps);
    ++avpacketCount;
    int result = avcodec_send_packet(m_videoCodecContext, packet);
    if (result < 0) {
        NSLog(@"%s: Send video data to decoder failed.",__func__);
        
    } else {
        while (avcodec_receive_frame(m_videoCodecContext, m_videoFrame) == 0) {
            // 获取视频时钟
            if (m_videoFrame->best_effort_timestamp == AV_NOPTS_VALUE ){
                pts = 0;
            } else {
                pts = m_videoFrame->best_effort_timestamp;
            }
            pts *= av_q2d(videoStream->time_base);
            pts = synchronize_video(m_videoFrame, pts, videoStream);
            NSLog(@"视频时钟：%f, %f", pts, video_clock);
            
            ++avframeCount;
            // 读取到一帧音频或者视频
            // 处理解码后音视频 frame
            NSLog(@"视频 压缩帧解码后得到的原始帧的显示时间 PTS：%lld, 压缩帧的解码时间 DTS：%lld,  帧类型(emum AVPictureType)：%d, " , m_videoFrame->pts, packet->dts, m_videoFrame->pict_type);
//            NSLog(@"Video Packet count:%d, Frame count : %d", avpacketCount, avframeCount);

            // 查看视频帧的类型 I P B 帧
            switch(m_videoFrame->pict_type){
                case AV_PICTURE_TYPE_I: NSLog(@"Video Frame Type:I 帧");break;
                case AV_PICTURE_TYPE_P: NSLog(@"Video Frame Type:P 帧");break;
                case AV_PICTURE_TYPE_B: NSLog(@"Video Frame Type:B 帧");break;
                default: NSLog(@"Video Frame Type:Other\t");break;
            }
            
            // 软解码：处理YUV数据的方式
            //        [self parseYuvData];
            
            // 硬解码：处理YUV数据的方式：YUV原始数据封装为 CMSampleBufferRef
            [self hwdeviceDecode_handleAVFrameWithVideoStream:videoStream];
            
    //        usleep(1000);
        }
    }
}

// 硬解码：处理YUV数据的方式：YUV原始数据封装为 CMSampleBufferRef
- (void)hwdeviceDecode_handleAVFrameWithVideoStream:(AVStream *)videoStream {
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)m_videoFrame->data[3];
    CMTime presentationTimeStamp = kCMTimeInvalid;
    Float64 ptsSec = m_videoFrame->pts * av_q2d(videoStream->time_base);
    presentationTimeStamp = CMTimeMake(ptsSec*1000000, 1000000);
    CMSampleBufferRef sampleBufferRef = [self convertCVImageBufferRefToCMSampleBufferRef:(CVPixelBufferRef)pixelBuffer
                                                               withPresentationTimeStamp:presentationTimeStamp];

    if (sampleBufferRef) {
        if ([self.delegate respondsToSelector:@selector(getDecodeVideoDataByFFmpeg:)]) {
            [self.delegate getDecodeVideoDataByFFmpeg:sampleBufferRef];
            CFRelease(sampleBufferRef);
        }
    }
}

- (void)stopDecoder {
    [self freeAllResources];
}

- (void)freeAllResources {
    NSLog(@"释放所有的视频相关的资源");
    if (m_videoCodecContext) {
        avcodec_send_packet(m_videoCodecContext, NULL);
        avcodec_flush_buffers(m_videoCodecContext);
        
        if (m_videoCodecContext->hw_device_ctx) {
            av_buffer_unref(&m_videoCodecContext->hw_device_ctx);
            m_videoCodecContext->hw_device_ctx = NULL;
        }
        avcodec_close(m_videoCodecContext);
        m_videoCodecContext = NULL;
    }
    if (m_videoFrame) {
        av_free(m_videoFrame);
        m_videoFrame = NULL;
    }
}


#pragma mark - 处理解码后的YUV数据

/*
 软解码：处理YUV数据的方式
 */
- (void)parseYuvData {
    
    /*
     enum AVPixelFormat {
         AV_PIX_FMT_NONE = -1,
         AV_PIX_FMT_YUV420P,   ///< planar YUV 4:2:0, 12bpp, (1 Cr & Cb sample per 2x2 Y samples)
         AV_PIX_FMT_YUYV422,   ///< packed YUV 4:2:2, 16bpp, Y0 Cb Y1 Cr
         AV_PIX_FMT_RGB24,     ///< packed RGB 8:8:8, 24bpp, RGBRGB...
         AV_PIX_FMT_BGR24,     ///< packed RGB 8:8:8, 24bpp, BGRBGR...
         AV_PIX_FMT_YUV422P,   ///< planar YUV 4:2:2, 16bpp, (1 Cr & Cb sample per 2x1 Y samples)
         AV_PIX_FMT_YUV444P,   ///< planar YUV 4:4:4, 24bpp, (1 Cr & Cb sample per 1x1 Y samples)
         AV_PIX_FMT_YUV410P, = 6   ///< planar YUV 4:1:0,  9bpp, (1 Cr & Cb sample per 4x4 Y samples)
         AV_PIX_FMT_YUV411P,   ///< planar YUV 4:1:1, 12bpp, (1 Cr & Cb sample per 4x1 Y samples)
         AV_PIX_FMT_GRAY8,     ///<        Y        ,  8bpp
         AV_PIX_FMT_MONOWHITE, ///<        Y        ,  1bpp, 0 is white, 1 is black, in each byte pixels are ordered from the msb to the lsb
         AV_PIX_FMT_MONOBLACK, ///<        Y        ,  1bpp, 0 is black, 1 is white, in each byte pixels are ordered from the msb to the lsb
         AV_PIX_FMT_PAL8,      ///< 8 bits with AV_PIX_FMT_RGB32 palette
         AV_PIX_FMT_YUVJ420P = 12,  ///< planar YUV 4:2:0, 12bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV420P and setting color_range
         AV_PIX_FMT_YUVJ422P,  ///< planar YUV 4:2:2, 16bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV422P and setting color_range
         AV_PIX_FMT_YUVJ444P,  ///< planar YUV 4:4:4, 24bpp, full scale (JPEG), deprecated in favor of AV_PIX_FMT_YUV444P and setting color_range
    */
    NSLog(@"视频解码后，原始数据的类型为(emum AVPixelFormat)：%d, 是否为关键帧I帧：%d, 帧类型(emum AVPictureType)：%d, 编码帧序号:%d, 显示帧序号:%d , PTS：%lld" , m_videoFrame->format, m_videoFrame->key_frame, m_videoFrame->pict_type, m_videoFrame->coded_picture_number, m_videoFrame->display_picture_number, m_videoFrame->pts);
    // 由于AVFrame是ffmpeg的数据结构，要分别提取出Y、U、V三个通道的数据才能用于显示
    /******************************************************************
        这里需要注意的是，我们的视频文件解码后的AVFrame的data不能直接渲染，因为AVFrame里的数据是分散的，displayYUV420pData这里指明了数据格式为YUV420P，
        所以我们必须copy到一个连pFrame缓冲区，然后再进行渲染。
        ******************************************************************
     
        解码后YUV格式的视频像素数据保存在AVFrame的data[0]、data[1]、data[2]中。
        但是这些像素值并不是连续存储的，每行有效像素之后存储了一些无效像素。
        以亮度Y数据为例，data[0]中一共包含了linesize[0] * height个数据。
        但是出于优化等方面的考虑，linesize[0]实际上并不等于宽度width，而是一个比宽度大一些的值。
     */
    
    char *yuvBuffer = (char *)malloc(m_videoFrame->width * m_videoFrame->height * 3 / 2);
    AVPicture *pict;
    int w, h, i;
    char *y, *u, *v;
    pict = (AVPicture *)m_videoFrame;// 这里的frame就是解码出来的AVFrame
    w = m_videoFrame->width;
    h = m_videoFrame->height;
    y = yuvBuffer;
    u = y + w * h;
    v = u + w * h / 4;
    for (i=0; i<h; i++)
        memcpy(y + w * i, pict->data[0] + pict->linesize[0] * i, w);
    for (i=0; i<h/2; i++)
        memcpy(u + w / 2 * i, pict->data[1] + pict->linesize[1] * i, w / 2);
    for (i=0; i<h/2; i++)
        memcpy(v + w / 2 * i, pict->data[2] + pict->linesize[2] * i, w / 2);
    n_frame++;
    if (yuvBuffer == NULL) {
        NSLog(@"YUV Buffer 为空");
        NSLog(@"解码视频流 Decode %d frame failure", n_frame);
    } else {
        NSLog(@"解码视频流 Decode %d frame success", n_frame);
        if ([self.delegate respondsToSelector:@selector(getDecodeVideoDataByFFmpeg:frameWidth:frameHeight:)]) {
            [self.delegate getDecodeVideoDataByFFmpeg:yuvBuffer frameWidth:m_videoFrame->width frameHeight:m_videoFrame->height];
        }
        free(yuvBuffer);
    }
}


#pragma mark - C method

AVBufferRef *hw_device_ctx = NULL;
static int InitHardwareDecoder(AVCodecContext *ctx, const enum AVHWDeviceType type) {
    // 创建硬件设备相关的上下文信息
    int err = av_hwdevice_ctx_create(&hw_device_ctx, type, NULL, NULL, 0);
    if (err < 0) {
        NSLog(@"Failed to create specified HW device.\n");
        return err;
    }
    ctx->hw_device_ctx = av_buffer_ref(hw_device_ctx);
    return err;
}

static int DecodeGetAVStreamFPSTimeBase(AVStream *st) {
    CGFloat fps, timebase = 0.0;
    
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    return fps;
}

static double video_clock = 0;

static double synchronize_video(AVFrame *src_frame, double pts, AVStream *avStream) {
    double frame_delay;
    if (pts!=0){
        video_clock = pts;
    } else {
        pts = video_clock;
    }
    
    frame_delay = av_q2d(avStream->codec->time_base);
    frame_delay += src_frame->repeat_pict * (frame_delay * 0.5);
    video_clock += frame_delay;
    return pts;
}

#pragma mark - Private

- (CMSampleBufferRef)convertCVImageBufferRefToCMSampleBufferRef:(CVImageBufferRef)pixelBuffer withPresentationTimeStamp:(CMTime)presentationTimeStamp {
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    CMSampleBufferRef newSampleBuffer = NULL;
    OSStatus res = 0;
    
    CMSampleTimingInfo timingInfo;
    timingInfo.duration              = kCMTimeInvalid;
    timingInfo.decodeTimeStamp       = presentationTimeStamp;
    timingInfo.presentationTimeStamp = presentationTimeStamp;
    
    CMVideoFormatDescriptionRef videoInfo = NULL;
    res = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    if (res != 0) {
        NSLog(@"%s: Create video format description failed!",__func__);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return NULL;
    }
    
    res = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                             pixelBuffer,
                                             true,
                                             NULL,
                                             NULL,
                                             videoInfo,
                                             &timingInfo, &newSampleBuffer);
    
    CFRelease(videoInfo);
    if (res != 0) {
        NSLog(@"%s: Create sample buffer failed!",__func__);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return NULL;
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return newSampleBuffer;
}


#pragma mark - 测试解码裸流的

/*解码h264裸流数据 （使用ffmpeg3.0之后的新API）
 @inputFile 输入的本地视频路径 或 网络流的地址，支持RTSP流协议
 @delegate  解码后的数据以代理来传递
 */
- (void)videoDecodeWithInputFile:(NSString *)inputFile delegate:(id<GVVideoDecodeDelegate>)delegate {

    
    self.delegate = delegate;
    got_picture = 0;
    n_frame = 0;
    first_time = 1;
    
    // [1]打开文件 avformat_open_input()
    AVDictionary     *opts          = NULL;
    av_dict_set(&opts, "timeout", "1000000", 0);// 设置超时1秒
    
    // m_formatContext = avformat_alloc_context(); // 本地流初始化
//    inputFile = @"rtsp://192.168.0.1:554/livestream/5"; //
    avformat_network_init(); // 网络流初始化
    
    // 本地文件裸流
    // BOOL isSuccess = avformat_open_input(&m_formatContext, [inputFile cStringUsingEncoding:NSUTF8StringEncoding], NULL, &opts) < 0 ? NO : YES;
    // 网络文件裸流
    BOOL isSuccess = avformat_open_input(&m_formatContext, [inputFile cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) < 0 ? NO : YES;
    
    av_dict_free(&opts);
    if (!isSuccess) {
        if (m_formatContext) {
            avformat_free_context(m_formatContext);
        }
        NSLog(@"无法打开视频流");
        return;
    }
    
    if (avformat_find_stream_info(m_formatContext, NULL) < 0) {
        avformat_close_input(&m_formatContext);
        return;
    }
    if (m_formatContext == NULL) {
        NSLog(@"Create format context failed.");
        return;
    }
    
    // Get video stream index
    int avStreamIndex = -1;
//    int audioStreamIndex = -1;
    for (int i = 0; i < m_formatContext->nb_streams; i++) {
        if (AVMEDIA_TYPE_VIDEO == m_formatContext->streams[i]->codecpar->codec_type) {
            avStreamIndex = i;
        }
//        if (AVMEDIA_TYPE_AUDIO == m_formatContext->streams[i]->codecpar->codec_type) {
//            audioStreamIndex = i;
//        }
        NSLog(@"avStreamIndex :%d, i:%d", avStreamIndex, i);
    }
    
    // Get video stream
    AVStream *videoStream = m_formatContext->streams[avStreamIndex];
    if (videoStream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
        enum AVCodecID codecID = videoStream->codecpar->codec_id;
        NSLog(@"Current video codec format is %s", avcodec_find_decoder(codecID)->name);
        // 本项目只支持AAC格式的音频
        if (codecID != AV_CODEC_ID_H264) {
            NSLog(@"Only support video format for the demo.");
            return;
        }
    }
        
    // 查找 video stream 相对应的解码器 avcodec_find_decoder(获取音频解码器上下文和解码器)
    m_videoCodecContext = m_formatContext->streams[avStreamIndex]->codec;
    AVCodec *codec = avcodec_find_decoder(m_videoCodecContext->codec_id);
    if (!codec) {
        NSLog(@"Not find video codec");
        return;
    }
    if (avcodec_open2(m_videoCodecContext, codec, NULL) < 0) {
        NSLog(@"Can't open video codec");
        return;
    }
    if (!m_videoCodecContext) {
        NSLog(@"create video codec failed");
        return;
    }
    
    // Get video frame
    m_videoFrame = av_frame_alloc();
    if (!m_videoFrame) {
        NSLog(@"alloc video frame failed");
        avcodec_close(m_videoCodecContext);
    }
    
    // 从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是 H264/H265 裸流数据 ,即编码的视频帧数据
    AVPacket    packet;
    while (1) { // 循环解码
        if (!m_formatContext) {
            break;
        }

        av_init_packet(&packet);
        int size = av_read_frame(m_formatContext, &packet);
        if (size < 0 || packet.size < 0) {
            NSLog(@"Parse finish 已全部解码");
            break;
        }
        
        if (packet.stream_index == avStreamIndex) {
            NSLog(@"将解码视频流");
            // 解码 AVPacket -> AVFrame
            int result = avcodec_send_packet(m_videoCodecContext, &packet);
            if (result < 0) {
                NSLog(@"Send video data to decoder failed.");
                
            } else {
                while (avcodec_receive_frame(m_videoCodecContext, m_videoFrame) == 0) {
                    // 读取到一帧音频或者视频
                    // 处理解码后音视频 frame
                    // 读取到一帧视频，处理解码后视频frame
                    if (first_time) {
                        NSLog(@"\nCodec Full Name:%s\n", m_videoCodecContext->codec->long_name);
                        NSLog(@"Width:%d\nHeight:%d\n\n", m_videoCodecContext->width,m_videoCodecContext->height);
                        first_time = 0;
                    }
                    // Y, U, V 原始数据
                    [self parseYuvData];
                    av_packet_unref(&packet);
                    // control rate
    //                    usleep(16.8*1000);
                    if (result != 0) {
                        NSLog(@"Decode finish.");
                    }
                }
            }
            
        }
    }
        
    NSLog(@"Free all resources !");
    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
    }
}



@end
