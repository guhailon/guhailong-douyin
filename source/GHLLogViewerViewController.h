// GHLLogViewerViewController — 抖音日志查看页（1.0.6）
// 入口在设置主页“常用功能”分区的“抖音日志”行，紧挨“下载管理”。
// 读 App 沙盒内 Documents/DYYY/GuHaiLongDouyin.log（GHLLogFilePath），
// 只显示最后约 200KB，文件不存在时显示“暂无日志”。
#import <UIKit/UIKit.h>

@interface GHLLogViewerViewController : UIViewController

// 1.0.22：卡片内打开时为 YES——页底/日志底改不透明（不铺自定义背景图、不透视频），
// 和设置列表/关于页同款（卡片里的页面内容要盖实）。
@property(nonatomic, assign) BOOL ghlInFloatPanel;

@end
