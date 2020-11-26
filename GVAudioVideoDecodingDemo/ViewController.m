//
//  ViewController.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/15.
//  Copyright © 2020 Sanchain. All rights reserved.
//  FFmpeg编译+h264解码+yuv渲染

/*
 * ------------------ 使用 ffmpeg-4.0.3 版本 ------------------
 */




#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

// FFmpeg Header File
//#ifdef __cplusplus
//extern "C" {
//#endif
    

#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/avstring.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

//#ifdef __cplusplus
//};
//#endif

#import "OpenGLView20.h"

//#import "XDXAudioQueuePlayer.h"
//#import "XDXQueueProcess.h"

int kXDXBufferSize = 4096;

@interface ViewController () {
    AVFormatContext* pFormatContext;
    AVCodecContext* pCodecCtx;  // 是视频解码的上下文，包含解码器
    AVFrame* pFrame;            // 解码后的视频帧数据，里面存的是YUV数据
    char* m_pBuffer;
    
    AVCodec *pCodec;
    enum AVCodecID codec_id;
    
    // 音频部分
    AVCodecContext  *m_audioCodecContext;
    AVFrame         *m_audioFrame;
}

@property (nonatomic, strong) OpenGLView20 *glView;

@end

@implementation ViewController


#pragma mark - Life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self.view addSubview:self.glView];
    [self.glView.layer setBorderWidth:1.0];
    [self.glView.layer setBorderColor:[UIColor redColor].CGColor];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                 [self decodeH264StreamOfLocalToYUV];
        //         [self decodeH265StreamOfLocalToYUV];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        //        [self decodeH264StreamOfNetworkToYUV];
        //        [self decodeH265StreamOfNetworkToYUV];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self decodeAACStreamOfLocalToPCM];
    });
    
    
    // Final Audio Player format : This is only for the FFmpeg to decode.
//    AudioStreamBasicDescription ffmpegAudioFormat = {
//        .mSampleRate         = 48000,
//        .mFormatID           = kAudioFormatLinearPCM,
//        .mChannelsPerFrame   = 2,
//        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
//        .mBitsPerChannel     = 16,
//        .mBytesPerPacket     = 4,
//        .mBytesPerFrame      = 4,
//        .mFramesPerPacket    = 1,
//    };
    
    // Configure Audio Queue Player
//    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithBufferSize:kXDXBufferSize];
//    [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
}


#pragma mark - ************* 1.本地音频码流解码部分 *************

/*
 *  解码AAC编码的音频码流为PCM数据
 */
- (void)decodeAACStreamOfLocalToPCM {

    // [1]打开文件 avformat_open_input()
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"audio" ofType:@"aac"];
    
   
    AVDictionary     *opts          = NULL;
    
    av_dict_set(&opts, "timeout", "1000000", 0);// 设置超时1秒
    
    pFormatContext = avformat_alloc_context();
    BOOL isSuccess = avformat_open_input(&pFormatContext, [filePath cStringUsingEncoding:NSUTF8StringEncoding], NULL, &opts) < 0 ? NO : YES;
    av_dict_free(&opts);
    if (!isSuccess) {
        if (pFormatContext) {
            avformat_free_context(pFormatContext);
        }
        return;
    }
    
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        avformat_close_input(&pFormatContext);
        return;
    }
    if (pFormatContext == NULL) {
        NSLog(@"create format context failed.");
        return;
    }
    
    // Get audio stream index
    int avStreamIndex = -1;
    for (int i = 0; i < pFormatContext->nb_streams; i++) {
        if (AVMEDIA_TYPE_AUDIO == pFormatContext->streams[i]->codecpar->codec_type) {
            avStreamIndex = i;
        }
    }
    // Get audio stream
    AVStream *audioStream = pFormatContext->streams[avStreamIndex];
    if (audioStream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        enum AVCodecID codecID = audioStream->codecpar->codec_id;
        NSLog(@"Current audio codec format is %s", avcodec_find_decoder(codecID)->name);
        // 本项目只支持AAC格式的音频
        if (codecID != AV_CODEC_ID_AAC) {
            NSLog(@"Only support AAC format for the demo.");
            return;
        }
    }
        
    // 查找 audio stream 相对应的解码器 avcodec_find_decoder(获取音频解码器上下文和解码器)
    m_audioCodecContext = pFormatContext->streams[avStreamIndex]->codec;
    AVCodec *codec = avcodec_find_decoder(m_audioCodecContext->codec_id);
    if (!codec) {
        NSLog(@"Not find audio codec");
        return;
    }
    if (avcodec_open2(m_audioCodecContext, codec, NULL) < 0) {
        NSLog(@"Can't open audio codec");
        return;
    }
    if (!m_audioCodecContext) {
        NSLog(@"create audio codec failed");
        return;
    }
    
    // Get audio frame
    m_audioFrame = av_frame_alloc();
    if (!m_audioFrame) {
        NSLog(@"alloc audio frame failed");
        avcodec_close(m_audioCodecContext);
    }
    
    // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是 AAC 裸流数据 ,即编码的视频帧数据
    dispatch_queue_t parseQueue = dispatch_queue_create("parse_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(parseQueue, ^{
        AVPacket    packet;
        while (1) { // 循环解码
            if (!pFormatContext) {
                break;
            }

            av_init_packet(&packet);
            int size = av_read_frame(pFormatContext, &packet);
            if (size < 0 || packet.size < 0) {
                NSLog(@"Parse finish");
                break;
            }
            
            // 解码 AVPacket -> AVFrame
            int result = avcodec_send_packet(m_audioCodecContext, &packet);
            if (result < 0) {
                NSLog(@"Send audio data to decoder failed.");
            } else {
                while (0 == avcodec_receive_frame(m_audioCodecContext, m_audioFrame)) {
                    Float64 ptsSec = m_audioFrame->pts* av_q2d(pFormatContext->streams[avStreamIndex]->time_base);
                    struct SwrContext *au_convert_ctx = swr_alloc();
                    au_convert_ctx = swr_alloc_set_opts(au_convert_ctx,
                                                        AV_CH_LAYOUT_STEREO,
                                                        AV_SAMPLE_FMT_S16,
                                                        48000,
                                                        m_audioCodecContext->channel_layout,
                                                        m_audioCodecContext->sample_fmt,
                                                        m_audioCodecContext->sample_rate,
                                                        0,
                                                        NULL);
                    swr_init(au_convert_ctx);
                    int out_linesize;
                    int out_buffer_size = av_samples_get_buffer_size(&out_linesize,
                                                                     m_audioCodecContext->channels,
                                                                     m_audioCodecContext->frame_size,
                                                                     m_audioCodecContext->sample_fmt,
                                                                     1);
                    
                    uint8_t *out_buffer = (uint8_t *)av_malloc(out_buffer_size);
                    // 解码
                    swr_convert(au_convert_ctx, &out_buffer, out_linesize, (const uint8_t **)m_audioFrame->data , m_audioFrame->nb_samples);
                    swr_free(&au_convert_ctx);
                    au_convert_ctx = NULL;
                    NSLog(@"AAC 码流解码成功后，DATA SIZE:%d", out_linesize);
                    //                    if ([self.delegate respondsToSelector:@selector(getDecodeAudioDataByFFmpeg:size:pts:isFirstFrame:)]) {
                    //                        [self.delegate getDecodeAudioDataByFFmpeg:out_buffer size:out_linesize pts:ptsSec isFirstFrame:m_isFirstFrame];
                    //                        m_isFirstFrame=NO;
                    //                    }
//                    [self addBufferToWorkQueueWithAudioData:out_buffer size:out_linesize];
                    // control rate
                    usleep(16.8*1000);
                    
                    av_free(out_buffer);
                }
                
                if (result != 0) {
                    NSLog(@"Decode finish.");
                }
            }
            
            av_packet_unref(&packet);
        }
        
        NSLog(@"Free all resources !");
        if (pFormatContext) {
            avformat_close_input(&pFormatContext);
        }
    });
}



#pragma mark - ************* 2.网络音频码流解码部分 *************




#pragma mark - ************* 3.本地视频码流解码部分 *************


#pragma mark - 解码H265编码的本地视频码流为YUV数据


/*
 *  解码H265编码的视频码流为YUV数据
 *  ffmpeg3以下版本的旧 API
 *  2k的解码渲染后，cpu:100%, 画面有卡顿
 *  4K的解码渲染后，画面有卡顿；1080P流畅
 */
- (void)decodeH265StreamOfLocalToYUV {
    
    // [1]注册所支持的所有的文件（容器）格式及其对应的CODEC av_register_all()
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        av_register_all();
    });
    
    // [2]打开文件 avformat_open_input()
    pFormatContext = avformat_alloc_context();
    
    NSString *fileName = [[NSBundle mainBundle] pathForResource:@"video1080.h265" ofType:nil];
    if (fileName == nil)
    {
        NSLog(@"Couldn't open file:%@",fileName);
        return;
    }
    if (avformat_open_input(&pFormatContext, [fileName cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0)//[1]函数调用成功之后处理过的AVFormatContext结构体;[2]打开的视音频流的URL;[3]强制指定AVFormatContext中AVInputFormat的。这个参数一般情况下可以设置为NULL，这样FFmpeg可以自动检测AVInputFormat;[4]附加的一些选项，一般情况下可以设置为NULL。)
    {
        NSLog(@"无法打开文件");
        return;
    }
     
    /**************************************************************************************************************
     *  以上是对本地H264文件的解码，当然如果你要对网络实时传输的h264视频码流进行解码，需要初始化网络环境，同时修改路径，以RTSP为例
     **************************************************************************************************************
     *      avformat_network_init();
     *      //    ...(其余部分不变)
     *    char *in_filename = [[NSString stringWithFormat:@"rtsp://192.168.0.1:554/livestream/5"] cStringUsingEncoding:NSASCIIStringEncoding];
     **************************************************************************************************************
     */
    
    // [3]从文件中提取流信息 avformat_find_stream_info()
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        NSLog(@"无法提取流信息");
        return;
    }
    
    // [4]在多个数据流中找到视频流 video stream（类型为MEDIA_TYPE_VIDEO）
    int videoStream = -1;
    for (int i = 0; i < pFormatContext -> nb_streams; i++)
    {
        if (pFormatContext -> streams[i] -> codec -> codec_type == AVMEDIA_TYPE_VIDEO)
        {
            videoStream = i;
        }
    }
    if (videoStream == -1) {
        NSLog(@"Didn't find a video stream.");
        return;
    }
    
    // [5]查找 video stream 相对应的解码器 avcodec_find_decoder(获取视频解码器上下文和解码器)
    pCodecCtx = pFormatContext->streams[videoStream]->codec;
    AVCodec *pCodec = avcodec_find_decoder(AV_CODEC_ID_HEVC);
    if (pCodec == NULL) {
        NSLog(@"pVideoCodec not found. 没有发现解码器");
        return;
    }
    
    // [6]打开解码器 avcodec_open2()
    avcodec_open2(pCodecCtx, pCodec, NULL);
    
    // [7]为解码帧分配内存 av_frame_alloc()
    pFrame = av_frame_alloc();
    
    // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是H265裸流数据 ,即编码的视频帧数据
    int ret, got_picture;
    int y_size = pCodecCtx->width * pCodecCtx->height;
    AVPacket *packet = (AVPacket *)malloc(sizeof(AVPacket));
    av_new_packet(packet, y_size);
    printf("Video infomation：\n");


    /*
     ffmpeg3.x之前，使用以下API来解码 H265 码流
     */
    
    // 循环解码
    while (av_read_frame(pFormatContext, packet) >= 0) {
        
        if (packet->stream_index == videoStream) { // 解码视频的H265码流
            
            // 已经读取到了H265码流数据
            // [9]对 video 帧进行解码，调用 avcodec_decode_video2()
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet); // 作用是解码一帧视频数据。输入一个压缩编码的结构体AVPacket，输出一个解码后的结构体 AVFrame
            if(ret < 0) {
                printf("Decode Error.\n");
                return;
            }
            
            if (got_picture) {
                NSLog(@"Frame_number: %d", pCodecCtx->frame_number);
//                if (pCodecCtx->frame_number <= 2250) { // 渲染2250帧 ，以帧率为25fps
                    [self renderYuvData];
//                } else {
//                    NSLog(@"已解码渲染完成，共渲染 %d 帧", pCodecCtx->frame_number);
//                    av_free(pFrame);
//                    avcodec_close(pCodecCtx);
//                    avformat_close_input(&pFormatContext);
//
//                    break;
//                }
            }
        }
       av_free_packet(packet);
    }
}


#pragma mark - 解码H264编码的本地视频码流为YUV数据

/*
 *  解码 H264 编码的视频码流为YUV数据
 *  ffmpeg3以下版本的旧 API
 *  测试结果：1080P播放速度正常、1440P播放速度整体加快
 */
- (void)decodeH264StreamOfLocalToYUV {
    
    // [1]注册所支持的所有的文件（容器）格式及其对应的CODEC av_register_all()
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        av_register_all();
    });
    
    // [2]打开文件 avformat_open_input()
    pFormatContext = avformat_alloc_context();
    
    NSString *fileName = [[NSBundle mainBundle] pathForResource:@"video.h264" ofType:nil];
    if (fileName == nil)
    {
        NSLog(@"Couldn't open file:%@",fileName);
        return;
    }
    if (avformat_open_input(&pFormatContext, [fileName cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0)//[1]函数调用成功之后处理过的AVFormatContext结构体;[2]打开的视音频流的URL;[3]强制指定AVFormatContext中AVInputFormat的。这个参数一般情况下可以设置为NULL，这样FFmpeg可以自动检测AVInputFormat;[4]附加的一些选项，一般情况下可以设置为NULL。)
    {
        NSLog(@"无法打开文件");
        return;
    }
     
    /**************************************************************************************************************
     *  以上是对本地H264文件的解码，当然如果你要对网络实时传输的h264视频码流进行解码，需要初始化网络环境，同时修改路径，以RTSP为例
     **************************************************************************************************************
     *      avformat_network_init();
     *      //    ...(其余部分不变)
     *    char *in_filename = [[NSString stringWithFormat:@"rtsp://192.168.0.1:554/livestream/5"] cStringUsingEncoding:NSASCIIStringEncoding];
     **************************************************************************************************************
     */
    
    // [3]从文件中提取流信息 avformat_find_stream_info()
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        NSLog(@"无法提取流信息");
        return;
    }
    
    // [4]在多个数据流中找到视频流 video stream（类型为MEDIA_TYPE_VIDEO）
    int videoStream = -1;
    for (int i = 0; i < pFormatContext -> nb_streams; i++)
    {
        if (pFormatContext -> streams[i] -> codec -> codec_type == AVMEDIA_TYPE_VIDEO)
        {
            videoStream = i;
        }
    }
    if (videoStream == -1) {
        NSLog(@"Didn't find a video stream.");
        return;
    }
    
    // [5]查找 video stream 相对应的解码器 avcodec_find_decoder(获取视频解码器上下文和解码器)
    pCodecCtx = pFormatContext->streams[videoStream]->codec;
    AVCodec *pCodec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (pCodec == NULL) {
        NSLog(@"pVideoCodec not found. 没有发现解码器");
        return;
    }
    
    // [6]打开解码器 avcodec_open2()
    avcodec_open2(pCodecCtx, pCodec, NULL);
    
    // [7]为解码帧分配内存 av_frame_alloc()
    pFrame = av_frame_alloc();
    
    // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是H264裸流数据 ,即编码的音视频帧数据
    int ret, got_picture;
    int y_size = pCodecCtx->width * pCodecCtx->height;
    AVPacket *packet = (AVPacket *)malloc(sizeof(AVPacket));
    av_new_packet(packet, y_size);
    printf("Video infomation：\n");


    /*
     ffmpeg3.x之前，使用以下API来解码 H264 码流
     */
    
    // 循环解码
    while (av_read_frame(pFormatContext, packet) >= 0) {
        
        if (packet->stream_index == videoStream) { // 解码视频的H264码流
            
            // 已经读取到了H264码流数据
            // [9]对 video 帧进行解码，调用 avcodec_decode_video2()
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet); // 作用是解码一帧视频数据。输入一个压缩编码的结构体AVPacket，输出一个解码后的结构体 AVFrame
            if(ret < 0) {
                printf("Decode Error.\n");
//                return;
            }
            
            if (got_picture) {
                NSLog(@"Frame_number: %d", pCodecCtx->frame_number);
                if (pCodecCtx->frame_number <= 2250) { // 渲染2250帧 ，以帧率为25fps
                    [self renderYuvData];
                } else {
                    NSLog(@"已解码渲染完成，共渲染 %d 帧", pCodecCtx->frame_number);
                    av_free(pFrame);
                    avcodec_close(pCodecCtx);
                    avformat_close_input(&pFormatContext);
                    
                    break;
                }
            } else {
                NSLog(@"解码 H264 本地视频码流失败");
            }
        }
       av_free_packet(packet);
    }
}


// 学习ffmpeg3之后新的解码API
- (void)decodeH264Stream_ffmpeg4 {
    
    codec_id = AV_CODEC_ID_H264;
    
    // [1]注册所支持的所有的文件（容器）格式及其对应的CODEC av_register_all()
    void *opaque = NULL;
    av_demuxer_iterate(&opaque);
    //av_register_all();  被弃用
        
    // [2]打开文件 avformat_open_input()
    pFormatContext = avformat_alloc_context();
    NSString *fileName = [[NSBundle mainBundle] pathForResource:@"video.h264" ofType:nil];
    if (fileName == nil)
    {
        NSLog(@"Couldn't open file:%@",fileName);
        return;
    }
    if (avformat_open_input(&pFormatContext, [fileName cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0)//[1]函数调用成功之后处理过的AVFormatContext结构体;[2]打开的视音频流的URL;[3]强制指定AVFormatContext中AVInputFormat的。这个参数一般情况下可以设置为NULL，这样FFmpeg可以自动检测AVInputFormat;[4]附加的一些选项，一般情况下可以设置为NULL。)
    {
        NSLog(@"无法打开文件");
        return;
    }
        
        /**************************************************************************************************************
         *  以上是对本地H264文件的解码，当然如果你要对网络实时传输的h264视频码流进行解码，需要初始化网络环境，同时修改路径，以RTSP为例
         **************************************************************************************************************
         *      avformat_network_init();
         *      //    ...(其余部分不变)
         *    char *in_filename = [[NSString stringWithFormat:@"rtsp://192.168.100.1/video/h264"] cStringUsingEncoding:NSASCIIStringEncoding];
         **************************************************************************************************************
         */
        
    
    // 独立的解码上下文
    // AVCodecContext视频解码的上下文,为AVCodecContext分配内存
    pCodecCtx = avcodec_alloc_context3(pCodec); // 创建解码环境
    if (!pCodecCtx){
        printf("Could not allocate video codec context\n");
        return;
    }
    
    // 循环遍历所有流，找到视频流
    int videoStream = -1;
    for (int i = 0; i < pFormatContext->nb_streams; i++) {
        if (pFormatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStream = i;
            break;
        }
    }
    
    //将配置参数复制到AVCodecContext中
    avcodec_parameters_to_context(pCodecCtx, pFormatContext->streams[videoStream]->codecpar);

    //查找视频解码器
    pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
    if (!pCodec) {
        printf("Codec not found\n");
        return;
    }

    //打开解码器
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        printf("Could not open codec\n");
        return;
    }
    
    //初始化AVCodecParserContext
    AVCodecParserContext *pCodecParserCtx=NULL;
    pCodecParserCtx = av_parser_init(codec_id);
    if (!pCodecParserCtx){
        printf("Could not allocate video parser context\n");
        return ;
    }
    
    

    /*
    
    // [3]从文件中提取流信息 avformat_find_stream_info()
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        NSLog(@"无法提取流信息");
        return;
    }
        
        // [4]在多个数据流中找到视频流 video stream（类型为MEDIA_TYPE_VIDEO）
        int videoStream = -1;
        for (int i = 0; i < pFormatContext -> nb_streams; i++)
        {
            if (pFormatContext -> streams[i] -> codec -> codec_type == AVMEDIA_TYPE_VIDEO)
            {
                videoStream = i;
            }
        }
        if (videoStream == -1) {
            NSLog(@"Didn't find a video stream.");
            return;
        }
        
        // [5]查找 video stream 相对应的解码器 avcodec_find_decoder(获取视频解码器上下文和解码器)
        pCodecCtx = pFormatContext->streams[videoStream]->codec;
        AVCodec *pCodec = avcodec_find_decoder(AV_CODEC_ID_H264);
        if (pCodec == NULL) {
            NSLog(@"pVideoCodec not found. 没有发现解码器");
            return;
        }
        

        
        // [6]打开解码器 avcodec_open2()
        avcodec_open2(pCodecCtx, pCodec, NULL);
        
        // [7]为解码帧分配内存 av_frame_alloc()
        pFrame = av_frame_alloc();
        
        // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是H264裸流数据 ,即编码的音视频帧数据
        int ret, got_picture;
        int y_size = pCodecCtx->width * pCodecCtx->height;
        AVPacket *packet = (AVPacket *)malloc(sizeof(AVPacket));
    //    av_new_packet(packet, y_size);
        printf("Video infomation：\n");
        av_init_packet(packet);

        */
    
        /*
         ffmpeg3.x后，使用以下API来解码 H264 码流
         */
//        ret = avcodec_send_packet(pCodecCtx, packet);
//        if (ret < 0) {
//            fprintf(stderr, "Error sending a packet for decoding\n");
//            return;
//        }
//
//        while (ret >= 0) {
//
//            ret = avcodec_receive_frame(pCodecCtx, pFrame);
//            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
//                NSLog(@"End of file");
//                return;
//            } else if (ret < 0) {
//                fprintf(stderr, "Error during decoding\n");
//                return;
//            }
//            if (pCodecCtx->frame_number <= 2250) { // 2250 ，以帧率为25fps
//               [self renderYuvData];
//            } else {
//               NSLog(@"已解码渲染完成");
//               av_free(pFrame);
//               avcodec_close(pCodecCtx);
//               avformat_close_input(&pFormatContext);
//               break;
//            }
//    //        av_free_packet(packet);
//            printf("Saving frame %3d\n", pCodecCtx->frame_number);
//        }
}


#pragma mark - ************* 4.网络视频码流解码部分 *************

#pragma mark - 解码H265编码的网络视频码流为YUV数据

/*
 *海思实时拉流，推的是小码流，且小码流默认的编码为H264，故选用H264解码器
 *海思点播回放视频，也是小码流，且小码流默认的编码为H264，故选用H264解码器
 */
- (void)decodeH265StreamOfNetworkToYUV {
    
    // [1]注册所支持的所有的文件（容器）格式及其对应的CODEC av_register_all()
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        av_register_all();
    });
    
    // [2]打开网络流，初始化网络环境 avformat_open_input()
    // rtsp://192.168.0.1:554/livestream/5 rtsp 流协议
    // rtsp://192.168.25.1:8080/?action=stream rtsp
    // http://192.168.0.1/sd//front_norm/2020_09_22_115909_00.MP4 http 流协议
    // rtmp://r.ossrs.net:1935/live/livestream
    avformat_network_init();
    
    NSString *streamUrl = @"http://192.168.0.1/sd//front_norm/2020_09_22_140130_00.MP4"; //
    if (avformat_open_input(&pFormatContext, [streamUrl cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0)//[1]函数调用成功之后处理过的AVFormatContext结构体;[2]打开的视音频流的URL;[3]强制指定AVFormatContext中AVInputFormat的。这个参数一般情况下可以设置为NULL，这样FFmpeg可以自动检测AVInputFormat;[4]附加的一些选项，一般情况下可以设置为NULL。)
    {
        NSLog(@"无法打开网络音视频流");
        return;
    }
    
    // [3]从文件中提取流信息 avformat_find_stream_info()
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        NSLog(@"无法提取流信息");
        return;
    }
    
    // [4]在多个数据流中找到视频流 video stream（类型为MEDIA_TYPE_VIDEO）
    int videoStream = -1;
    for (int i = 0; i < pFormatContext -> nb_streams; i++)
    {
        if (pFormatContext -> streams[i] -> codec -> codec_type == AVMEDIA_TYPE_VIDEO)
        {
            videoStream = i;
        }
    }
    if (videoStream == -1) {
        NSLog(@"Didn't find a video stream.");
        return;
    }
    
    // [5]查找 video stream 相对应的解码器 avcodec_find_decoder(获取视频解码器上下文和解码器)
    pCodecCtx = pFormatContext->streams[videoStream]->codec;
    AVCodec *pCodec = avcodec_find_decoder(AV_CODEC_ID_H264); // AV_CODEC_ID_H264
    if (pCodec == NULL) {
        NSLog(@"pVideoCodec not found. 没有发现解码器");
        return;
    }
    
    // [6]打开解码器 avcodec_open2()
    avcodec_open2(pCodecCtx, pCodec, NULL);
    
    // [7]为解码帧分配内存 av_frame_alloc()
    pFrame = av_frame_alloc();
    
    // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是H265裸流数据 ,即编码的视频帧数据
    int ret, got_picture;
    int y_size = pCodecCtx->width * pCodecCtx->height;
    AVPacket *packet = (AVPacket *)malloc(sizeof(AVPacket));
    av_new_packet(packet, y_size);
    printf("Video infomation：\n");


    /*
     ffmpeg3.x之前，使用以下API来解码 H265 码流
     */
    
    // 循环解码
    while (av_read_frame(pFormatContext, packet) >= 0) {
        
        if (packet->stream_index == videoStream) { // 解码视频的 H265 码流
            
            // 已经读取到了 H265 码流数据
            // [9]对 video 帧进行解码，调用 avcodec_decode_video2()
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet); // 作用是解码一帧视频数据。输入一个压缩编码的结构体AVPacket，输出一个解码后的结构体 AVFrame
            if(ret < 0) {
                printf("Decode Error.\n");
//                return;
            }
            
            if (got_picture) {
                NSLog(@"Frame_number: %d", pCodecCtx->frame_number);
//                if (pCodecCtx->frame_number <= 2250) { // 2250 ，帧率为25fps
                    [self renderYuvData];
//                } else {
//                    NSLog(@"已解码渲染完成，共渲染 %d 帧", pCodecCtx->frame_number);
//                    av_free(pFrame);
//                    avcodec_close(pCodecCtx);
//                    avformat_close_input(&pFormatContext);
//
//                    break;
//                }
            } else {
                NSLog(@"解码 H265 网络视频码流失败");
            }
        }
       av_free_packet(packet);
    }
}



#pragma mark - 解码H264编码的网络视频码流为YUV数据

- (void)decodeH264StreamOfNetworkToYUV {
    
    // [1]注册所支持的所有的文件（容器）格式及其对应的CODEC av_register_all()
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        av_register_all();
    });
    
    // [2]打开网络流，初始化网络环境 avformat_open_input()
    // rtsp://192.168.0.1:554/livestream/5 rtsp 流协议
    // rtsp://192.168.25.1:8080/?action=stream rtsp
    // http://192.168.0.1/sd//front_norm/2020_09_18_112214_00.MP4 http 流协议
    // rtmp://r.ossrs.net:1935/live/livestream
    avformat_network_init();
    
    NSString *streamUrl = @"http://192.168.0.1/sd//front_norm/2020_09_18_112214_00.MP4";
    if (avformat_open_input(&pFormatContext, [streamUrl cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0)//[1]函数调用成功之后处理过的AVFormatContext结构体;[2]打开的视音频流的URL;[3]强制指定AVFormatContext中AVInputFormat的。这个参数一般情况下可以设置为NULL，这样FFmpeg可以自动检测AVInputFormat;[4]附加的一些选项，一般情况下可以设置为NULL。)
    {
        NSLog(@"无法打开网络音视频流");
        return;
    }
    
    // [3]从文件中提取流信息 avformat_find_stream_info()
    if (avformat_find_stream_info(pFormatContext, NULL) < 0) {
        NSLog(@"无法提取流信息");
        return;
    }
    
    // [4]在多个数据流中找到视频流 video stream（类型为MEDIA_TYPE_VIDEO）
    int videoStream = -1;
    for (int i = 0; i < pFormatContext -> nb_streams; i++)
    {
        if (pFormatContext -> streams[i] -> codec -> codec_type == AVMEDIA_TYPE_VIDEO)
        {
            videoStream = i;
        }
    }
    if (videoStream == -1) {
        NSLog(@"Didn't find a video stream.");
        return;
    }
    
    // [5]查找 video stream 相对应的解码器 avcodec_find_decoder(获取视频解码器上下文和解码器)
    pCodecCtx = pFormatContext->streams[videoStream]->codec;
    AVCodec *pCodec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (pCodec == NULL) {
        NSLog(@"pVideoCodec not found. 没有发现解码器");
        return;
    }
    
    // [6]打开解码器 avcodec_open2()
    avcodec_open2(pCodecCtx, pCodec, NULL);
    
    // [7]为解码帧分配内存 av_frame_alloc()
    pFrame = av_frame_alloc();
    
    // [8]从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是H264裸流数据 ,即编码的音视频帧数据
    int ret, got_picture;
    int y_size = pCodecCtx->width * pCodecCtx->height;
    AVPacket *packet = (AVPacket *)malloc(sizeof(AVPacket));
    av_new_packet(packet, y_size);
    printf("Video infomation：\n");


    /*
     ffmpeg3.x之前，使用以下API来解码 H264 码流
     */
    
    // 循环解码
    while (av_read_frame(pFormatContext, packet) >= 0) {
        
        if (packet->stream_index == videoStream) { // 解码视频的H264码流
            
            // 已经读取到了H264码流数据
            // [9]对 video 帧进行解码，调用 avcodec_decode_video2()
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet); // 作用是解码一帧视频数据。输入一个压缩编码的结构体AVPacket，输出一个解码后的结构体 AVFrame
            if(ret < 0) {
                printf("Decode Error.\n");
                return;
            }
            
            if (got_picture) {
                NSLog(@"Frame_number: %d", pCodecCtx->frame_number);
//                if (pCodecCtx->frame_number <= 2250) { // 2250 ，帧率为25fps
                    [self renderYuvData];
//                } else {
//                    NSLog(@"已解码渲染完成，共渲染 %d 帧", pCodecCtx->frame_number);
//                    av_free(pFrame);
//                    avcodec_close(pCodecCtx);
//                    avformat_close_input(&pFormatContext);
//
//                    break;
//                }
            } else {
                NSLog(@"解码H264网络视频码流失败");
            }
        }
       av_free_packet(packet);
    }
}


#pragma mark - ************************* 播放解码后的音频数据 **************************


- (void)addBufferToWorkQueueWithAudioData:(void *)data  size:(int)size {
    
//    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
//    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
//    if (node == NULL) {
//        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
//        return;
//    }
//
//    node->size = size;
//    memcpy(node->data, data, size);
//    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);
//
//    NSLog(@"Test Data in ,  work size = %d, free size = %d !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size);
}


#pragma mark - ************************* OpenGL 渲染 YUV 数据 ************************

- (void)renderYuvData {
    
    NSLog(@"OpenGL 渲染 YUV 数据");
    
    // [10]由于AVFrame是ffmpeg的数据结构，要分别提取出Y、U、V三个通道的数据才能用于显示
    /*************************************************************************************************************************
     * 这里需要注意的是，我们的视频文件解码后的AVFrame的data不能直接渲染，因为AVFrame里的数据是分散的，displayYUV420pData这里指明了数据格式为YUV420P，
     * 所以我们必须copy到一个连pFrame缓冲区，然后再进行渲染。
     * *************************************************************************************************************************
     */
    char *yuvBuffer = (char *)malloc(pFrame->width * pFrame->height * 3 / 2);
    AVPicture *pict;
    int w, h, i;
    char *y, *u, *v;
    pict = (AVPicture *)pFrame;// 这里的frame就是解码出来的AVFrame
    w = pFrame->width;
    h = pFrame->height;
    y = yuvBuffer;
    u = y + w * h;
    v = u + w * h / 4;
    for (i=0; i<h; i++)
        memcpy(y + w * i, pict->data[0] + pict->linesize[0] * i, w);
    for (i=0; i<h/2; i++)
        memcpy(u + w / 2 * i, pict->data[1] + pict->linesize[1] * i, w / 2);
    for (i=0; i<h/2; i++)
        memcpy(v + w / 2 * i, pict->data[2] + pict->linesize[2] * i, w / 2);
    if (yuvBuffer == NULL) {
        NSLog(@"YUV Buffer 为空");
//      return yuvBuffer;
    } else {
//      dispatch_async(dispatch_get_global_queue(0, 0), ^{
//        sleep(3);
          /****************************************************
           * 渲染 YUV 数据
           ***************************************************/
          [self.glView setVideoSize:pFrame->width height:pFrame->height];
          [self.glView displayYUV420pData:yuvBuffer width:pFrame -> width height:pFrame ->height];
        free(yuvBuffer);
//      });
    }
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
