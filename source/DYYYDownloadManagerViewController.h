// DYYYDownloadManagerViewController — 下载管理页（1.0.4）
// 入口在设置主页“常用功能”分区的“下载管理”行。
// 诚实说明：下载的视频/图片直接存进相册，DYYYManager 没有持久的下载记录，
// 所以这里做不出“已下载文件列表”；只做“成功下载次数统计（自 1.0.4 起）+ 临时缓存清理”。
#import <UIKit/UIKit.h>

@interface DYYYDownloadManagerViewController : UITableViewController
@end
