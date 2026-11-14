// GHLImagePreviewViewController — 图集图片全屏翻页预览（1.0.23，长按面板「图片预览」）
// 黑底、左右滑动翻页、点一下关闭；图片异步下载，失败那页显示「加载失败」。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GHLImagePreviewViewController : UIViewController

- (instancetype)initWithImageURLs:(NSArray<NSURL *> *)imageURLs;

@end

NS_ASSUME_NONNULL_END
