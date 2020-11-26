//
//  GVModuleListController.m
//  GVAudioVideoDecodingDemo
//
//  Created by Sanchain on 2020/11/26.
//  Copyright © 2020 Sanchain. All rights reserved.
//

#import "GVModuleListController.h"

@interface GVModuleListController ()<UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView; //
@property (nonatomic, strong) NSArray *listDataSource; //

@end

@implementation GVModuleListController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self setupUI];
}

- (void)setupUI {
    [self.view addSubview:self.tableView];
    self.title = @"FFmpeg 音视频解码、渲染";
}


#pragma mark - UITableViewDelegate, UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.listDataSource.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 64.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    [cell.textLabel setText:self.listDataSource[indexPath.row]];
    [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    cell.textLabel.font = [UIFont systemFontOfSize:12.0];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
}


#pragma mark - 懒加载

- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
        [_tableView setTableFooterView:[UIView new]];
        [_tableView setDelegate:self];
        [_tableView setDataSource:self];
        [_tableView setShowsVerticalScrollIndicator:NO];
    }
    return _tableView;
}

- (NSArray *)listDataSource {
    if (!_listDataSource) {
        _listDataSource = @[
            @"解码本地 H264 视频码流 - YUV - 渲染",
            @"解码本地 H265 视频码流 - YUV - 渲染",
            @"解码本地 AAC  音频码流 - PCM - 渲染",
            @"解码网络 H264 视频码流 - YUV - 渲染",
            @"解码网络 AAC  音频码流 - PCM - 渲染",
            @"音视频同步：解码本地 H264/AAC 音视频流 - YUV/PCM - 渲染",
            @"音视频同步：解码网络 H264/AAC 音视频流 - YUV/PCM - 渲染"
        ];
    }
    return _listDataSource;
}

@end
