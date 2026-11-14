//
//  DYYY
//
//  Copyright (c) 2024 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2024/10/04
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYSettingViewController : UIViewController

// 默认 init = 设置主页（白色卡片样式：头卡 + 搜索 + 10 个分类行 + 底部按钮）。
// initWithSectionIndex: = 某个分类的子页（白色单分组表，只显示该分区的开关/输入框/选择器）。
- (instancetype)initWithSectionIndex:(NSInteger)sectionIndex;

// 模态弹出时导航栏左上角“关闭”按钮的动作（DYYYSettings.xm 的直接入口用）。
- (void)ghlDismissSettings;

// 1.0.13：关于页（GHLAboutViewController）复用配置三行的入口（key 与逻辑不动）。
- (void)ghlExportAndShareFromIndexPath:(nullable NSIndexPath *)indexPath;
- (void)ghlPresentImportPicker;
- (void)ghlConfirmResetSettings;

@end

NS_ASSUME_NONNULL_END