// GHLFloatPanelHomeViewController — 卡片首页（1.0.21）
// 浅色毛玻璃卡片的首页：标题（导航栏大标题）＋搜索框（只过滤按键）＋两列按键
// （通用设置／首页／朋友／消息／我／播放互动／诊断反馈／关于），点按在卡片内导航栈上推。
// 卡片底部的「完成」按钮是卡片自己的（GHLFeatures.xm 里建），不在这里。
// 底栏切换（首页／朋友／消息／我）是探针：按标题匹配底栏，找不到就如实记日志。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GHLFloatPanelHomeViewController : UIViewController <UISearchBarDelegate>

@end

NS_ASSUME_NONNULL_END
