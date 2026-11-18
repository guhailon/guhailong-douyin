// GHLAboutViewController — 关于深色品牌页（1.0.13，方案四）
// 入口是设置主页「关于」分类行（1.0.15 起直接进本页，不再经过只有一行的「关于」子页）。
// 显式深色，不跟随系统：顶上展翅绿龙横幅（1.0.15）＋金字标题＋灰字版本（点版本行复制版本/机型/iOS 版本），
// 两张深色金边卡（关于/联系＋加群大按钮；重启抖音/更换横幅背景/更新日志/声明，声明在最下面），
// 页底一行小灰字是声明摘要。
#import <UIKit/UIKit.h>

@interface GHLAboutViewController : UIViewController

// 1.0.24：在卡片里打开时由设置主页填 YES——页底透明、卡半透明白，共用卡片底图。
@property(nonatomic, assign) BOOL ghlInFloatPanel;

@end
