// GHLMemoListViewController — 文案备忘录（1.0.24，清单 20 号，只做备忘）
// 本地存备忘列表：点行复制去粘贴，左滑删除，右上角 + 新增。
// 定时自动发送不做（要逆向私信发送入口，难度最高；App 切后台/被杀后定时器也不跑）。
// 存储：NSUserDefaults 的 GHL_KEY_MEMO_LIST，数组里是字典 @{@"text", @"date"}。
#import <UIKit/UIKit.h>

@interface GHLMemoListViewController : UIViewController

// 1.0.24：卡片内打开时为 YES——页底透明，共用卡片底的整张背景图（和关于/日志页同款）。
@property(nonatomic, assign) BOOL ghlInFloatPanel;

@end
