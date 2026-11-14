// GHLAboutViewController — 关于深色品牌页（1.0.13，方案四）
// 入口在设置主页「关于」分区的唯一行「关于顾海龙抖音」。
// 显式深色，不跟随系统：顶上雷鸣绿龙横幅＋金字标题＋灰字版本（点版本行复制版本/机型/iOS 版本），
// 两张深色金边卡（关于/联系＋加群大按钮；配置管理/更新日志/检查更新/声明，声明在最下面），
// 页底一行小灰字是声明摘要。
#import <UIKit/UIKit.h>

@class DYYYSettingViewController;

@interface GHLAboutViewController : UIViewController

// 配置三行（导出/导入/恢复默认）复用设置主页的逻辑，推本页时由设置主页填上。
@property(nonatomic, weak, nullable) DYYYSettingViewController *settingsViewController;

@end
