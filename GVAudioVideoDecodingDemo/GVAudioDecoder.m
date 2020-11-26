//
//  GVAudioDecoder.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/23.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVAudioDecoder.h"



//typedef struct VideoState {
//    AVFormatContext *pFormatCtx;
//    int videoStream, audioStream;
//    
//    double audio_clock;
//    AVStream *audio_st;
////    PacketQueue audioq;
//    AVFrame audio_frame;
////    uint8_t audio_buf[(MAX_AUDIO_FRAME_SIZE * 3) / 2];
//    unsigned int audio_buf_size;
//    unsigned int audio_buf_index;
//    AVPacket audio_pkt;
//    uint8_t *audio_pkt_data;
//    int audio_pkt_size;
//    int audio_hw_buf_size;
//    double frame_timer;
//    double frame_last_pts;
//    double frame_last_delay;
//    double video_clock;
//    AVStream *video_st;
////    PacketQueue videoq;
//    
////    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
//    int pictq_size, pictq_rindex, pictq_windex;
//    
//    NSCondition *pictq_cond;
//    
//    char filename[1024];
//    int quit;
//    
//    AVIOContext *io_context;
//    struct SwsContext *sws_ctx;
//} VideoState;
//
//VideoState *global_video_state;

@interface GVAudioDecoder ()
{
    AVFormatContext* pFormatContext;
    AVCodecContext* pCodecCtx;  // 是视频解码的上下文，包含解码器
    AVFrame* pFrame;            // 解码后的视频帧数据，里面存的是YUV数据
    char* m_pBuffer;

    AVCodec *pCodec;
    enum AVCodecID codec_id;

    // 音频部分
    AVCodecContext  *m_audioCodecContext;
    AVFrame         *m_audioFrame;
    int m_audioStreamIndex;
    int avpacketCount;
    int avframeCount;
    double audio_clock;
}

@property (nonatomic, weak) id<GVAudioDecodeDelegate> delegate ; //

@end


@implementation GVAudioDecoder

+ (instancetype)shareInstance {
    
    static GVAudioDecoder *audioDecoder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioDecoder = [[GVAudioDecoder alloc] init];
    });
    return audioDecoder;
}

- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext audioStreamIndex:(int)audioStreamIndex delegate:(id<GVAudioDecodeDelegate>)delegate {
    
    if (self = [super init]) {
        self.delegate = delegate;
        [self audioDecodeWithFormatContext:formatContext audioStreamIndex:audioStreamIndex];
    }
    return self;
}

/*
 解码 AAC 裸流为PCM数据
 */
- (void)startDecodeAudioDataWithAVPacket:(AVPacket *)packet {
    AVStream *videoStream = pFormatContext->streams[m_audioStreamIndex];

    int result = avcodec_send_packet(m_audioCodecContext, packet);
    if (result < 0) {
        NSLog(@"%s: Send audio data to decoder failed.",__func__);
        
    } else {
        ++avpacketCount;
        // 音频时钟
        if (packet->pts != AV_NOPTS_VALUE) {
            audio_clock = av_q2d(videoStream->time_base) * packet->pts;
        }
//        NSLog(@"音频时钟 : %f", audio_clock);
        
        // 解码 AVPacket -> AVFrame
        // 一个AVFrame,包含多个音频帧
        while (0 == avcodec_receive_frame(m_audioCodecContext, m_audioFrame)) {
            ++avframeCount;
            
//            NSLog(@"Audio Packet count:%d, Frame count : %d", avpacketCount, avframeCount);
            // 音频重采样：转换为适合在音频播放器上播放
            Float64 ptsSec = m_audioFrame->pts* av_q2d(pFormatContext->streams[m_audioStreamIndex]->time_base);
            NSLog(@"音频 压缩帧解码后得到的原始帧的显示时间 PTS：%lld, 压缩帧的解码时间 DTS：%lld,  包含了 %d 个音频帧" , m_audioFrame->pts, packet->dts, m_audioFrame->nb_samples);
//            NSLog(@"音频解码后，原始数据的类型为(emum AVSampleFormat)：%d, 包含了 %d 个音频帧, pts:%f", m_audioFrame->format, m_audioFrame->nb_samples, ptsSec);
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
            swr_convert(au_convert_ctx, &out_buffer, out_linesize, (const uint8_t **)m_audioFrame->data , m_audioFrame->nb_samples);
            swr_free(&au_convert_ctx);
            
            int n = 2 * m_audioCodecContext->channels;
            audio_clock += (double) out_buffer_size / (double) (n * 48000); // 44100
            NSLog(@"音频时钟 : %f", audio_clock);
            
            
            au_convert_ctx = NULL;
            if ([self.delegate respondsToSelector:@selector(getDecodeAudioDataByFFmpeg:size:pts:)]) {
                [self.delegate getDecodeAudioDataByFFmpeg:out_buffer size:out_linesize pts:ptsSec];
            }
            // control rate
            usleep(14.5*1000); // 单位是微秒 这里并不是实现音视频同步的方法
//            usleep(9.5*1000); // 这里并不是实现音视频同步的方法，只是挂起线程
            av_free(out_buffer);
        }
        
        if (result != 0) {
            NSLog(@"%s: AAC Decode finish.",__func__);
        }
    }
}


- (void)audioDecodeWithFormatContext:(AVFormatContext *)formatContext audioStreamIndex:(int)audioStreamIndex {
    
    pFormatContext = formatContext;
    m_audioStreamIndex = audioStreamIndex;
    
    avframeCount = 0;
    avpacketCount = 0;
    
    // 查找 audio stream 相对应的解码器 avcodec_find_decoder(获取音频解码器上下文和解码器)
    m_audioCodecContext = formatContext->streams[audioStreamIndex]->codec;
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
    
    /*
    
    // 从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是 AAC 裸流数据 ,即编码的音频帧数据
    dispatch_queue_t parseQueue = dispatch_queue_create("parse_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(parseQueue, ^{
        AVPacket    packet;
        while (1) { // 循环解码
            if (!formatContext) {
                break;
            }

            av_init_packet(&packet);
            int size = av_read_frame(formatContext, &packet);
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
                    Float64 ptsSec = m_audioFrame->pts* av_q2d(formatContext->streams[audioStreamIndex]->time_base);
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
                    if ([self.delegate respondsToSelector:@selector(getDecodeAudioDataByFFmpeg:size:)]) {
                        [self.delegate getDecodeAudioDataByFFmpeg:out_buffer size:out_linesize];
                    }
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
        if (formatContext) {
            avformat_close_input(&formatContext);
        }
    });
    */
}

- (void)stopDecoder {
//    m_isFirstFrame   = YES;
    [self freeAllResources];
}

- (void)freeAllResources {
    NSLog(@"释放所有的音频相关的资源");
    if (m_audioCodecContext) {
        avcodec_send_packet(m_audioCodecContext, NULL);
        avcodec_flush_buffers(m_audioCodecContext);
        
        if (m_audioCodecContext->hw_device_ctx) {
            av_buffer_unref(&m_audioCodecContext->hw_device_ctx);
            m_audioCodecContext->hw_device_ctx = NULL;
        }
        avcodec_close(m_audioCodecContext);
        m_audioCodecContext = NULL;
    }
    
    if (m_audioFrame) {
        av_free(m_audioFrame);
        m_audioFrame = NULL;
    }
}


#pragma mark - C Method

//double get_audio_clock(VideoState *is) {
//    double pts;
//    int hw_buf_size, bytes_per_sec, n;
//
//    pts = is->audio_clock;
//    hw_buf_size = is->audio_buf_size - is->audio_buf_index;
//    bytes_per_sec = 0;
//
//    n = is->audio_st->codec->channels * 2;//2是指量化精度，一般是16bit = 2 B；
//
//    if (is->audio_st) {
//        bytes_per_sec = is->audio_st->codec->sample_rate * n;
//    }
//    if (bytes_per_sec) {
//        pts -= (double) hw_buf_size / bytes_per_sec;
//    }
//    return pts;
//}


#pragma mark - Public Api

/*
 解码AAC音频码流
 */
- (void)audioDecodeWithInputFile:(NSString *)inputFile delegate:(id<GVAudioDecodeDelegate>)delegate {
    
    self.delegate = delegate;
    
    // [1]打开文件 avformat_open_input()
    AVDictionary     *opts          = NULL;
    av_dict_set(&opts, "timeout", "1000000", 0);// 设置超时1秒
    
    // pFormatContext = avformat_alloc_context(); // 本地流初始化
    inputFile = @"rtsp://192.168.0.1:554/livestream/5"; //
    avformat_network_init(); // 网络流初始化
    
    // 本地文件裸流
    // BOOL isSuccess = avformat_open_input(&pFormatContext, [inputFile cStringUsingEncoding:NSUTF8StringEncoding], NULL, &opts) < 0 ? NO : YES;
    // 网络文件裸流
    BOOL isSuccess = avformat_open_input(&pFormatContext, [inputFile cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) < 0 ? NO : YES;
    av_dict_free(&opts);
    if (!isSuccess) {
        if (pFormatContext) {
            avformat_free_context(pFormatContext);
        }
        NSLog(@"无法打开音频流");
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
    
    // 从流中读取读取数据到Packet中 av_read_frame()，AVPacket存的是 AAC 裸流数据 ,即编码的视频帧数据
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
                // 音频重采样
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
                    if ([self.delegate respondsToSelector:@selector(getDecodeAudioDataByFFmpeg:size:pts:)]) {
                        [self.delegate getDecodeAudioDataByFFmpeg:out_buffer size:out_linesize pts:ptsSec];
                    }
                    // control rate
//                    usleep(16.8*1000);
                    usleep(14.5*1000);
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


@end
