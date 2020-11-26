//
//  GVAVParseHandler.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/25.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVAVParseHandler.h"


static const int kXDXParseSupportMaxFps     = 60;
static const int kXDXParseFpsOffSet         = 5;
static const int kXDXParseWidth1920         = 1920;
static const int kXDXParseHeight1080        = 1080;
static const int kXDXParseSupportMaxWidth   = 3840;
static const int kXDXParseSupportMaxHeight  = 2160;


@interface GVAVParseHandler ()
{
    /*  FFmpeg  */
    AVFormatContext* m_formatContext;
    int videoStreamIndex;
    int audioStreamIndex;
    
    /*  Video info  */
    int m_video_width, m_video_height, m_video_fps, m_isNetworkStream;
}
@end


@implementation GVAVParseHandler


#pragma mark - Public Api

- (instancetype)initWithFilePath:(NSString *)filePath isNetworkStream:(BOOL)isNetworkStream {
    if (self = [super init]) {
        m_isNetworkStream = isNetworkStream;
        [self prepareParseWithPath:filePath];
    }
    return self;
}

// 获取音视频流的 AVPacket，即编码后H264裸流或AAC裸流
- (void)startParseGetAVPackeWithCompletionHandler:(void (^)(BOOL isVideoFrame, BOOL isFinish, AVPacket packet))handler {
    
//    m_isStopParse = NO;
    dispatch_queue_t parseQueue = dispatch_queue_create("parse_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(parseQueue, ^{
        AVPacket    packet;
        while (1) {
//        while (!self->m_isStopParse) {
            if (!m_formatContext) {
                break;
            }
            
            av_init_packet(&packet);
            int size = av_read_frame(m_formatContext, &packet);
            if (size < 0 || packet.size < 0) {
//                self->m_isStopParse = YES;
                handler(YES, YES, packet);
//                NSLog(@"%s: Parse finish 解码音视频流完成",__func__);
                break;
            }
            
            if (packet.stream_index == videoStreamIndex) {
//                NSLog(@"Video Stream AVPacket DTS:%d, PTS:%d", packet.dts, packet.pts);
                handler(YES, NO, packet);
            } else {
//                NSLog(@"Audio Stream AVPacket DTS:%d, PTS:%d", packet.dts, packet.pts);
                handler(NO, NO, packet);
            }
            
            av_packet_unref(&packet);
        }
        
        [self freeAllResources];
    });
}

// 释放所有资源
- (void)freeAllResources {
    NSLog(@"%s: Free all resources !",__func__);
    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
        m_formatContext = NULL;
    }
    
//    if (m_bitFilterContext) { // 硬解码部分的资源
//        av_bitstream_filter_close(m_bitFilterContext);
//        m_bitFilterContext = NULL;
//    }
    
    //    if (m_bsfContext) {
    //        av_bsf_free(&m_bsfContext);
    //        m_bsfContext = NULL;
    //    }
}



#pragma mark - Private

- (void)prepareParseWithPath:(NSString *)path {
    // Create format context
    m_formatContext = [self createFormatContextbyFilePath:path];
    
    if (m_formatContext == NULL) {
        NSLog(@"%s: create format context failed.", __func__);  // 资源文件有问题
        return;
    }
    
    // Get video stream index
    videoStreamIndex = [self getAVStreamIndexWithFormatContext:m_formatContext
                                                   isVideoStream:YES];
    
    // Get video stream
    AVStream *videoStream = m_formatContext->streams[videoStreamIndex];
    m_video_width  = videoStream->codecpar->width;
    m_video_height = videoStream->codecpar->height;
    m_video_fps    = GetAVStreamFPSTimeBase(videoStream);
    NSLog(@"%s: video index:%d, width:%d, height:%d, fps:%d",__func__, videoStreamIndex, m_video_width, m_video_height, m_video_fps);
    
    BOOL isSupport = [self isSupportVideoStream:videoStream
                                  formatContext:m_formatContext
                                    sourceWidth:m_video_width
                                   sourceHeight:m_video_height
                                      sourceFps:m_video_fps];
    if (!isSupport) {
        NSLog(@"%s: Not support the video stream",__func__);
        return;
    }
    
    // Get audio stream index
    audioStreamIndex = [self getAVStreamIndexWithFormatContext:m_formatContext
                                                   isVideoStream:NO];
    NSLog(@"%s:audio index: %d", __func__, audioStreamIndex);
    
    // Get audio stream
    AVStream *audioStream = m_formatContext->streams[audioStreamIndex];
    
    isSupport = [self isSupportAudioStream:audioStream
                             formatContext:m_formatContext];
    if (!isSupport) {
        NSLog(@"%s: Not support the audio stream",__func__);
        return;
    }
}

- (AVFormatContext *)createFormatContextbyFilePath:(NSString *)filePath {
    if (filePath == nil) {
        NSLog(@"%s: file path is NULL",__func__);
        return NULL;
    }
    
    AVFormatContext  *formatContext = NULL;
    AVDictionary     *opts          = NULL;
    
    av_dict_set(&opts, "timeout", "1000000 ", 0);// 设置超时1秒
    BOOL isSuccess = NO;
    if (m_isNetworkStream) {
        avformat_network_init(); // 网络流初始化
        isSuccess = avformat_open_input(&formatContext, [filePath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) < 0 ? NO : YES;

    } else {
        formatContext = avformat_alloc_context(); // 本地文件初始化
        isSuccess = avformat_open_input(&formatContext, [filePath cStringUsingEncoding:NSUTF8StringEncoding], NULL, &opts) < 0 ? NO : YES;
    }
    
    av_dict_free(&opts);
    if (!isSuccess) {
        if (formatContext) {
            avformat_free_context(formatContext);
        }
        return NULL;
    }
    
    if (avformat_find_stream_info(formatContext, NULL) < 0) {
        avformat_close_input(&formatContext);
        return NULL;
    }
    
    return formatContext;
}


- (int)getAVStreamIndexWithFormatContext:(AVFormatContext *)formatContext isVideoStream:(BOOL)isVideoStream {
    
    int avStreamIndex = -1;
    for (int i = 0; i < formatContext->nb_streams; i++) {
        if ((isVideoStream ? AVMEDIA_TYPE_VIDEO : AVMEDIA_TYPE_AUDIO) == formatContext->streams[i]->codecpar->codec_type) {
            avStreamIndex = i;
        }
    }
    
    if (avStreamIndex == -1) {
        NSLog(@"%s: Not find video stream",__func__);
        return NULL;
    } else {
        return avStreamIndex;
    }
}


- (BOOL)isSupportVideoStream:(AVStream *)stream
               formatContext:(AVFormatContext *)formatContext
                 sourceWidth:(int)sourceWidth
                sourceHeight:(int)sourceHeight
                   sourceFps:(int)sourceFps {
    
    if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {   // Video
        enum AVCodecID codecID = stream->codecpar->codec_id;
        NSLog(@"%s: Current video codec format is %s",__func__, avcodec_find_decoder(codecID)->name);
        // 目前只支持H264、H265(HEVC iOS11)编码格式的视频文件
        if ((codecID != AV_CODEC_ID_H264 && codecID != AV_CODEC_ID_HEVC) || (codecID == AV_CODEC_ID_HEVC && [[UIDevice currentDevice].systemVersion floatValue] < 11.0)) {
            NSLog(@"%s: Not suuport the codec",__func__);
            return NO;
        }
        
        // iPhone 8以上机型支持有旋转角度的视频
        AVDictionaryEntry *tag = NULL;
        tag = av_dict_get(formatContext->streams[videoStreamIndex]->metadata, "rotate", tag, 0);
        if (tag != NULL) {
            int rotate = [[NSString stringWithFormat:@"%s",tag->value] intValue];
            if (rotate != 0 /* && >= iPhone 8P*/) {
                NSLog(@"%s: Not support rotate for device ",__func__);
            }
        }
        
        /*
         各机型支持的最高分辨率和FPS组合:
         
         iPhone 6S: 60fps -> 720P
         30fps -> 4K
         
         iPhone 7P: 60fps -> 1080p
         30fps -> 4K
         
         iPhone 8: 60fps -> 1080p
         30fps -> 4K
         
         iPhone 8P: 60fps -> 1080p
         30fps -> 4K
         
         iPhone X: 60fps -> 1080p
         30fps -> 4K
         
         iPhone XS: 60fps -> 1080p
         30fps -> 4K
         */
        
        // 目前最高支持到60FPS
        if (sourceFps > kXDXParseSupportMaxFps + kXDXParseFpsOffSet) {
            NSLog(@"%s: Not support the fps",__func__);
            return NO;
        }
        
        // 目前最高支持到3840*2160
        if (sourceWidth > kXDXParseSupportMaxWidth || sourceHeight > kXDXParseSupportMaxHeight) {
            NSLog(@"%s: Not support the resolution",__func__);
            return NO;
        }
        
        // 60FPS -> 1080P
        if (sourceFps > kXDXParseSupportMaxFps - kXDXParseFpsOffSet && (sourceWidth > kXDXParseWidth1920 || sourceHeight > kXDXParseHeight1080)) {
            NSLog(@"%s: Not support the fps and resolution",__func__);
            return NO;
        }
        
        // 30FPS -> 4K
        if (sourceFps > kXDXParseSupportMaxFps / 2 + kXDXParseFpsOffSet && (sourceWidth >= kXDXParseSupportMaxWidth || sourceHeight >= kXDXParseSupportMaxHeight)) {
            NSLog(@"%s: Not support the fps and resolution",__func__);
            return NO;
        }
        
        // 6S
//        if ([[XDXAnywhereTool deviceModelName] isEqualToString:@"iPhone 6s"] && sourceFps > kXDXParseSupportMaxFps - kXDXParseFpsOffSet && (sourceWidth >= kXDXParseWidth1920  || sourceHeight >= kXDXParseHeight1080)) {
//            log4cplus_error(kModuleName, "%s: Not support the fps and resolution",__func__);
//            return NO;
//        }
        return YES;
    } else {
        return NO;
    }
    
}

- (BOOL)isSupportAudioStream:(AVStream *)stream formatContext:(AVFormatContext *)formatContext {
    
    if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        enum AVCodecID codecID = stream->codecpar->codec_id;
        NSLog(@"%s: Current audio codec format is %s",__func__, avcodec_find_decoder(codecID)->name);
        // 本项目只支持AAC格式的音频
        if (codecID != AV_CODEC_ID_AAC) {
            NSLog(@"%s: Only support AAC format for the demo.",__func__);
            return NO;
        }
        return YES;
    } else {
        return NO;
    }
}

#pragma mark Get Method

- (AVFormatContext *)getFormatContext {
    return m_formatContext;
}

- (int)getVideoStreamIndex {
    return videoStreamIndex;
}

- (int)getAudioStreamIndex {
    return audioStreamIndex;
}


#pragma mark - C Function

// 获取视频的帧率
static int GetAVStreamFPSTimeBase(AVStream *st) {
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
@end
