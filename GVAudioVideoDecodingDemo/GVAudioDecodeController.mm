//
//  GVAudioDecodeController.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/9/23.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVAudioDecodeController.h"
#import "GVAudioDecoder.h"

#import "XDXAudioQueuePlayer.h"
#import "XDXQueueProcess.h"


#define kBufferSize 4096

@interface GVAudioDecodeController ()<GVAudioDecodeDelegate>

@end


@implementation GVAudioDecodeController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // 解码音频AAC码流
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"audio" ofType:@"aac"];
    [[GVAudioDecoder shareInstance] audioDecodeWithInputFile:filePath delegate:self];
    
    
    // 配置原生 Audio Queue Player
//    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithBufferSize:kBufferSize];
//    [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
}


#pragma mark - GVAudioDecodeDelegate

/*
 获取解码后的音频数据
 并用于在原生 Audio queue 队列里播放
 */
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size {
    
    NSLog(@"解码音频AAC码流的数据回调 size : %d", size);
    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
    if (node == NULL) {
        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
        return;
    }

    node->size = size;
    memcpy(node->data, data, size);
    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);

    NSLog(@"Test Data in ,  work size = %d, free size = %d !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size);
}

@end
