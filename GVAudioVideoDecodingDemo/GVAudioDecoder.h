//
//  GVAudioDecoder.h
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/23.
//  Copyright © 2020 Sanchain. All rights reserved.
//  音频解码器

#import <Foundation/Foundation.h>


#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/avstring.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>


@protocol GVAudioDecodeDelegate <NSObject>

/*
 音频裸流解码后的PCM数据
 @data PCM数据
 @size PCM数据长度
 @pts  帧的展示时间戳
 */
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size pts:(int64_t)pts;

@end

@interface GVAudioDecoder : NSObject

+ (instancetype)shareInstance;

- (void)audioDecodeWithInputFile:(NSString *)inputFile delegate:(id<GVAudioDecodeDelegate>)delegate;




- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext
                     audioStreamIndex:(int)audioStreamIndex
                             delegate:(id<GVAudioDecodeDelegate>)delegate;


- (void)audioDecodeWithFormatContext:(AVFormatContext *)formatContext
                    audioStreamIndex:(int)audioStreamIndex;
// 解码AAC音频流为PCM数据
- (void)startDecodeAudioDataWithAVPacket:(AVPacket *)packet;
- (void)stopDecoder;



/*
 G.711 音频码流
 */
//- (void)


@end

