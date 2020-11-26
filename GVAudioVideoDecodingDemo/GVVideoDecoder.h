//
//  GVVideoDecoder.h
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/24.
//  Copyright © 2020 Sanchain. All rights reserved.
//  H264视频码流解码器，解码为AVFrame的YUV数据

#import <Foundation/Foundation.h>

#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/avstring.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

#import <CoreMedia/CMSampleBuffer.h>



@protocol GVVideoDecodeDelegate <NSObject>

/*获取视频解码后的YUV数据
 @data        解码后的 YUV 数据
 @frameWidth  视频帧的宽度
 @frameHeight 视频帧的高度
 */
- (void)getDecodeVideoDataByFFmpeg:(void *)data frameWidth:(int)frameWidth frameHeight:(int)frameHeight;

// 将YUV视频原始数据封装为CMSampleBufferRef数据结构并传给OpenGL以将视频渲染到屏幕上
- (void)getDecodeVideoDataByFFmpeg:(CMSampleBufferRef)sampleBuffer;

@end



@interface GVVideoDecoder : NSObject

+ (instancetype)shareInstance;

/*
 @inputFile 输入的本地视频路径 或 网络流的地址，支持RTSP流协议
 @delegate  解码后的数据以代理来传递
 */
- (void)videoDecodeWithInputFile:(NSString *)inputFile delegate:(id<GVVideoDecodeDelegate>)delegate;



//
- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext videoStreamIndex:(int)videoStreamIndex delegate:(id<GVVideoDecodeDelegate>)delegate;

// 解码H264裸流
- (void)startDecodeVideoDataWithAVPacket:(AVPacket *)packet;
- (void)stopDecoder;

@end


