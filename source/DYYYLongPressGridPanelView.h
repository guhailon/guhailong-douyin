// 顾海龙抖音长按下载面板：网格风格（1.0.9）
// 深色毛玻璃底板 + 三列金色图标网格 + 顶部金色龙头（复用 GHLLogoImage()，圆形金边，和设置页头卡同一套）。
// 本视图不持有任何 AWELongPressPanelBaseViewModel（它们的 action block 捕获了面板控制器，持有会造成循环引用）：
// 只收一份轻量数据（每项 title + actionType），点按时再从 dataArray 的弱引用里按 actionType 找回原 viewModel 执行。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLongPressGridPanelView : UIView

// items：每项 @{@"title": NSString, @"actionType": NSNumber}，顺序即 dataArray 里的顺序；
// itemActionHandler：点按某格时调用，参数为该格的 actionType，由 Hook 方负责找回 viewModel 并执行它的 action；
// hasNativeItems：是否还有抖音原生项（有则末尾加一个“更多”，点开回到原生面板）；
// revealNativeHandler：点“更多”回到原生面板后调用（Hook 方用来记住这次不再盖网格）；
// dismissHandler：下滑手势触发时调用（由 Hook 方传入，走 AWELongPressPanelManager 正常收起）。
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items
               hasNativeItems:(BOOL)hasNativeItems
            itemActionHandler:(void (^)(NSInteger actionType))itemActionHandler
           revealNativeHandler:(nullable void (^)(void))revealNativeHandler
               dismissHandler:(nullable void (^)(void))dismissHandler;

@end

NS_ASSUME_NONNULL_END
