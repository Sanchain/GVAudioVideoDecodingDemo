//
//  GVAVParseHandler.h
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/25.
//  Copyright © 2020 Sanchain. All rights reserved.
//  使用 FFmpeg 解析音视频流，对外提供 AVFormatContext VideoStreamIndex AudioStreamIndex



#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/avstring.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>



@interface GVAVParseHandler : NSObject


- (instancetype)initWithFilePath:(NSString *)filePath isNetworkStream:(BOOL)isNetworkStream;

// 获取音视频流的 AVPacket，即编码后H264裸流或AAC裸流
- (void)startParseGetAVPackeWithCompletionHandler:(void (^)(BOOL isVideoFrame, BOOL isFinish, AVPacket packet))handler;


/*
 Get method
 */
- (AVFormatContext *)getFormatContext;
- (int)getVideoStreamIndex;
- (int)getAudioStreamIndex;

@end

