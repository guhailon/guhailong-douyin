// 顾海龙抖音 (GHL) — 新增功能实现
// 基于 DYYY (MIT, Copyright (c) 2024 huami) 的个人二创，免费使用，仅限学习交流。
// 原 MIT 声明与 huami 版权行保留在 LICENSE 文件中，未做任何改动。
//
// 约定：
// - 所有开关都受 NSUserDefaults 控制，关掉即恢复默认行为。
// - 拿不准的 hook 点只写日志探针，不硬猜、不做假实现。
// - 诊断日志写到 Documents/DYYY/GuHaiLongDouyin.log（App 沙盒内；旧路径 /var/mobile/Library/Logs/ 写不出去，只作兜底）
#import "GHLFeatures.h"
#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYManager.h"
#import "DYYYUtils.h"
#import "DYYYFloatingButtonCoordinator.h"
#import "DYYYFloatClearButton.h"
#import "DYYYBottomAlertView.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingViewController.h"
#import "GHLAboutViewController.h"
#import "GHLImagePreviewViewController.h"
#import "GHLLogViewerViewController.h"
#import "GHLMemoListViewController.h"
#import "DYYYToast.h"
#import "DYYYOptionsSelectionView.h"
#import "DYYYBackupPickerDelegate.h"
#import "DYYYCustomInputView.h"
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ReplayKit/ReplayKit.h>
#import <objc/runtime.h>

@class GHLFeatures;

@interface GHLFeatures : NSObject <UIGestureRecognizerDelegate>
@end

// 前向声明（part 4 定义，part 2 的左滑返回要用）
static UIViewController *GHLTopViewController(void);

// 前向声明（1.0.19 卡片面板＝設定頁本身做成卡片，实现在巡检定时器前面一节；
// @implementation GHLFeatures 里的点按回调在它前面，要先声明）
static void GHLToggleFloatPanel(void);
static void GHLHideFloatPanel(void);
static void GHLFloatPanelHandleDimTap(UITapGestureRecognizer *gesture);
static void GHLRefreshFloatPanelButton(void);

// 前向声明（1.0.21 主线程卡住看门狗：定义在巡检定时器一节，%ctor 里先启动，要先声明）
static void GHLStartMainThreadWatchdog(void);

#pragma mark - 基础工具

BOOL GHLGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

NSString *GHLGetString(NSString *key) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

BOOL GHLKeywordFilterEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_KEYWORD_FILTER];
    if (!value) return YES; // 没设置过默认开，保持上游已有过滤行为不变
    return [value boolValue];
}

BOOL GHLFollowSystemDarkEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_FOLLOW_SYSTEM_DARK];
    if (!value) return YES; // 没设置过默认开
    return [value boolValue];
}

static dispatch_queue_t GHLLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      queue = dispatch_queue_create("com.guhailong.douyin.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// 1.0.21：最近一条日志（主线程看门狗读来当“最近活动”；写在日志串行队列里，
// 读也走同一队列，线程安全——看门狗在后台线程读，不能直接碰这个指针）。
static NSString *ghlLastLogMessage = nil;
// 1.0.24：最近一条“非看门狗报警”的日志——看门狗自己的报警行会把上一条报警
// 嵌进去（-10.log 里 19 行报警越嵌越长，最后一条全是报警套报警，“最近活动”
// 完全看不出冻住前在干什么）；报警行读这个，冻住前的最后活动才留得住。
static NSString *ghlLastNonWatchdogMessage = nil;
static NSString *GHLLastLogMessage(void) {
    __block NSString *message = nil;
    dispatch_sync(GHLLogQueue(), ^{
      message = ghlLastLogMessage;
    });
    return message;
}
static NSString *GHLLastNonWatchdogMessage(void) {
    __block NSString *message = nil;
    dispatch_sync(GHLLogQueue(), ^{
      message = ghlLastNonWatchdogMessage;
    });
    return message;
}

// 1.0.6：诊断日志主路径（App 沙盒内 Documents/DYYY/，配置导出已证明能写）。
NSString *GHLLogFilePath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!documents) return nil;
    return [documents stringByAppendingPathComponent:@"DYYY/GuHaiLongDouyin.log"];
}

void GHLLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] [GHL] %@\n", [[NSDate date] description], message];
    NSLog(@"%@", line);
    dispatch_async(GHLLogQueue(), ^{
      ghlLastLogMessage = message; // 1.0.21：主线程看门狗的“最近活动”就从这里读。
      // 1.0.24：报警行自己不算活动（不然报警嵌报警，见上面注释）。
      if (![message hasPrefix:@"主线程卡住"]) ghlLastNonWatchdogMessage = message;
      @try {
          // 1.0.6：主路径改到 App 自己的 Documents/DYYY/（沙盒内可写，配置导出已证明能写）；
          // 旧路径 /var/mobile/Library/Logs/ 在沙盒里写不出去，只作次选兜底。
          NSString *primaryPath = GHLLogFilePath();
          NSMutableArray<NSString *> *paths = [NSMutableArray array];
          if (primaryPath) [paths addObject:primaryPath];
          [paths addObject:@"/var/mobile/Library/Logs/GuHaiLongDouyin.log"];
          for (NSString *path in paths) {
              NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
              if (!handle) {
                  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                  if ([line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]) return;
                  continue;
              }
              [handle seekToEndOfFile];
              [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
              [handle closeFile];
              return;
          }
      } @catch (__unused NSException *exception) {
      }
    });
}

void GHLRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

#pragma mark - 当前视频 / 播放器

AWEAwemeModel *GHLCurrentAwemeModel(void) {
    @try {
        UIViewController *controller = [DYYYFloatingButtonCoordinator currentInteractionController];
        if ([controller respondsToSelector:@selector(model)]) {
            id model = [(AWEPlayInteractionViewController *)controller model];
            if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) return model;
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

#pragma mark - 1.0.4 悬浮按钮自定义

// 在 keyWindow 的视图树里找清屏按钮实例（协调器不对外暴露实例，只能这样找）。
static HideUIButton *GHLFindHideButton(void) {
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
    while (stack.count > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:[HideUIButton class]]) return (HideUIButton *)view;
        [stack addObjectsFromArray:view.subviews];
    }
    return nil;
}

// 执行一个悬浮按钮动作；返回 YES 表示已处理，调用方跳过默认行为。
// 动作候选只给已经存在的功能：下载当前视频、清屏、倍速切换、弹幕开关、截图去水印。
BOOL GHLPerformFloatButtonAction(NSString *action) {
    if (!action || [action isEqualToString:GHL_FLOAT_ACTION_DEFAULT]) return NO;
    if ([action isEqualToString:GHL_FLOAT_ACTION_DOWNLOAD]) {
        GHLDownloadCurrentVideoWithProgress();
    } else if ([action isEqualToString:GHL_FLOAT_ACTION_CLEAR]) {
        HideUIButton *clearButton = GHLFindHideButton();
        if (clearButton && clearButton.window) {
            [clearButton handleTap];
        } else {
            [DYYYUtils showToast:@"清屏按钮当前不可用"];
        }
    } else if ([action isEqualToString:GHL_FLOAT_ACTION_SPEED]) {
        UIViewController *controller = [DYYYFloatingButtonCoordinator currentInteractionController];
        if (controller && [controller respondsToSelector:@selector(speedButtonTapped:)]) {
            @try {
                [(id)controller speedButtonTapped:nil];
            } @catch (__unused NSException *exception) {
                [DYYYUtils showToast:@"切换倍速失败"];
            }
        } else {
            [DYYYUtils showToast:@"当前没有可切换倍速的视频"];
        }
    } else if ([action isEqualToString:GHL_FLOAT_ACTION_DANMAKU]) {
        BOOL on = GHLGetBool(@"DYYYCommentShowDanmaku") || GHLGetBool(GHL_KEY_COMMENT_DANMAKU);
        [[NSUserDefaults standardUserDefaults] setBool:!on forKey:@"DYYYCommentShowDanmaku"];
        [[NSUserDefaults standardUserDefaults] setBool:!on forKey:GHL_KEY_COMMENT_DANMAKU];
        [DYYYUtils showToast:!on ? @"弹幕已开" : @"弹幕已关"];
    } else if ([action isEqualToString:GHL_FLOAT_ACTION_SCREENSHOT]) {
        AWEAwemeModel *model = GHLCurrentAwemeModel();
        if (!model) {
            [DYYYUtils showToast:@"当前没有视频"];
            return YES;
        }
        double seconds = GHLCurrentPlayerTime();
        if (seconds < 0) seconds = 0;
        GHLSaveCleanScreenshotForAwemeModel(model, seconds);
    } else {
        return NO;
    }
    return YES;
}

// 1.0.5 手势自定义：执行一个手势动作；返回 YES 表示已处理。
// 动作候选只给已经存在的功能（前 5 个复用悬浮按钮那套）+ 静音开关 + 下一个视频。
// 前向声明（实现在下面“手势”一节，切下一个视频和边缘滑动共用）。
static void GHLScrollFeedToNextVideo(void);

// 前向声明（实现在下面“1.0.23 第二批”一节；@implementation GHLFeatures 里的
// 手势/按钮回调在它前面，要先声明）。
static void GHLHandleIMDoubleTapReply(void);
static void GHLHandleIMAvatarLongPress(UITableView *table, CGPoint point);
static void GHLHandleAISegmentChanged(UISegmentedControl *segment);
static void GHLHandleAIParseStart(UIButton *button);

BOOL GHLPerformGestureAction(NSString *action) {
    if (!action || [action isEqualToString:GHL_FLOAT_ACTION_DEFAULT]) return NO;
    if (GHLPerformFloatButtonAction(action)) return YES;
    if ([action isEqualToString:GHL_GESTURE_ACTION_MUTE]) {
        // 静音开关：抖音头文件里没有静音接口，直接开关已定位的 AVPlayer 的 muted（公开 API，
        // 快进/截图用的就是这个播放器）。只管当前视频，切视频后新播放器默认有声，要再按一次。
        AVPlayer *player = GHLFindPlayingAVPlayer();
        if (!player) {
            [DYYYUtils showToast:@"当前没有视频"];
            return YES;
        }
        player.muted = !player.muted;
        [DYYYUtils showToast:player.muted ? @"已静音" : @"已取消静音"];
        return YES;
    }
    if ([action isEqualToString:GHL_GESTURE_ACTION_NEXT]) {
        GHLScrollFeedToNextVideo();
        return YES;
    }
    return NO;
}

// 更新日志文本（1.0.1–1.0.11 各一行真实改动，以 git log 为准）。
NSString *GHLChangelogText(void) {
    return @"1.0.1：修主设置页两行空白，功能设置标注改小字两行显示。\n"
           @"1.0.2：设置主页改白色单步直达，龙头招牌，语音四项探针。\n"
           @"1.0.3：龙头重裁居中，分区改名常用功能/自动功能，关于加 QQ 号和 QQ 群。\n"
           @"1.0.4：导入/导出配置、恢复默认配置、下载管理、语音包收藏、深色模式、悬浮按钮自定义、更新日志、加群按钮、龙头和背景可换、界面视觉统一。\n"
           @"1.0.5：设置主页头卡改成毛玻璃，背景图从头卡里透出来；手势自定义（三击/双指双击/左滑/右滑）。\n"
           @"1.0.6：诊断日志改写到 App 自己的 Documents/DYYY/ 文件夹，沙盒里也能写出来；设置里加「顾海龙日志」，点进去能看日志、刷新、清空、分享。\n"
           @"1.0.7：修底栏朋友和加号藏不住（不认类名改名、标签为空、按钮被容器包着都能认；头像下的关注加号按位置认），底栏诊断写进顾海龙日志。\n"
           @"1.0.8：颜色行改系统调色盘，主题预设一键换（金龙/冰蓝/樱粉/暗夜），侧边栏图标大小/间距/圆角底，进度条加粗圆角默认金色，头像金边（关注实心/未关注细边），弹幕字号/描边/透明度+多时自动变淡，底栏毛玻璃+选中态金色；双击爱心换图标仍是探针（爱心动画类没找到，只记日志，需真机验证）。\n"
           @"1.0.9：长按下载面板换成我们自己的网格面板（深色毛玻璃、三列金色图标、顶部金色龙头；更多回原生面板；精简模式和隐藏列表照常生效）。\n"
           @"1.0.10：修网格面板盖不上（数据改强引用持有到收起，dataArray 一到就主线程补盖一次；每个失败分支都记诊断日志，下次没盖上日志直接写明哪一关没过）。\n"
           @"1.0.11：长按项开关默认全开（12 个 DYYY 开关，没存过值时才默认开，亲手关掉的不会被覆盖），普通视频的网格从 2 行（6 项）变成 4 行（9 项+更多；格子收小到 92pt，下面还有时显示滚动条）；面板设置里加「长按面板头像」，能从相册任意换头像或恢复默认龙头，换完下一次长按就生效，不用重启抖音；网格盖上时的日志补上各项标题。\n"
           @"1.0.12：导出/导入/恢复默认配置三行从功能设置搬到新增的「关于」分区（逻辑不动）；「关于」和「基于DYYY」合并成「关于顾海龙抖音」一行；新增「声明」，措辞是草稿（皇上可改）；底部按钮只剩 MIT 声明和更新日志。\n"
           @"1.0.13：关于改成深色品牌页（雷鸣绿龙横幅＋金字标题，两张深色金边卡：关于/联系/QQ群＋配置管理/更新日志/检查更新/声明，声明在最下面，页底小灰字声明摘要）；检查更新联网比对源里的版本号；点版本行复制版本/机型/iOS 版本；配置管理加重启抖音；关于弹窗和底部 MIT/更新日志按钮废弃。\n"
           @"1.0.14：关于入口行拿掉右边的「查看关于」，点整行直接进关于页（只留右箭头）；关于页标题/版本行按横幅里龙头中心对齐（龙头在图里偏左，之前字相对龙头偏右）；QQ 行标签改成「QQ：QQ群交流：」+ 号码，点按复制不变；原作者行改成「原作者（huami）」，下面加一行只展示的「现作者（顾海龙总监）」。\n"
           @"1.0.15：关于入口一层直达（设置主页点「关于」直接进品牌页，中间那个只有一行的「关于」子页拿掉）；关于页横幅换成展翅绿龙（雷雨海面＋红眼睛，标题按实测龙头中心 x=358 对齐），横幅背景能自己换（相册选图存到 Documents/DYYY/ghl-about-banner.jpg，也能恢复默认）；修画中画＋后台播放（监听 token 存下来不再立刻失效，触发改到切后台前一刻 WillResignActive，进后台兜底一次，系统回调如实记日志；播放器查找放宽到全部窗口递归找图层＋播放器控制器 KVC 探针，没图层时用播放器新建图层再建画中画，查找经过写进顾海龙日志）；长按网格去掉「更多」，原生项也进网格，长按只出网格（超 4 行可上下滑）。\n"
       @"1.0.16：长按网格原生项（倍速/清屏播放/投屏等）改走原生选中，不再直接调 action（点了没反应就是缺面板控制器上下文）；点按入口和成功分支补日志；原生项图标补关键字映射（倍速/清屏/投屏/定时等各有图标，不再全是下载箭头）；面板首屏露 5 行、滚动对齐行高、下滑收起只在列表顶端才认；画中画兜底：抖音自有播放器没有系统播放器可挂时，用当前视频链接自起一个 AVPlayer 做画中画（会从头播，接不上进度；链接可能是短效签名，过期播不了；后台/锁屏/与原视频声音冲突待真机验证）；画中画查找记调用方，B 路加运行时控制器类名 dump；顾海龙日志从设置页常用功能移到关于页第二张卡（检查更新之后、声明之前）；日志查看器截断处防半个中文字符。"
           @"1.0.17：直播画中画：直播间没有普通视频的播放地址，D 路兜底加直播分支——进直播间/点画中画时探一次 room model 的拉流地址栏位（只记栏位名＋长度＋前 60 字），拿到 HLS（.m3u8）就走同一套自起播放器做画中画（从头播，接不上直播进度；拉流地址可能是短效签名；后台/锁屏/声音冲突待真机验证）；只有 FLV/RTMP 时如实记一行，不转封装；B 路探针遇到「键存在但值不是播放器/图层」时补记一行；画中画查找日志加一行是否在直播间。\n"
           @"1.0.18：视频页左上角加龙头浮动钮，点开快捷面板（深色毛玻璃卡：标题＋搜索框＋两列按钮＋完成；通用设置／首页／朋友／消息／我／播放互动／诊断反馈／关于；搜索只过滤面板按钮；播放互动里直接列画中画＋后台播放／记忆倍速／快进手势三个开关；设置页「悬浮按钮」分区可关）；直播探针下探一层（上次只探到 IESLiveRoomService 服务外壳，这次再探它里面的 roomModel 等容器键一层），探针改后台线程跑（画中画查找那路 5 秒超时，超时按拿不到地址处理）；另加计时日志（只记日志不改行为，用来定位画面冻住的原因：巡检每跳耗时＋上跳间隔、视频页布局钩子每秒次数＋耗时）；后台听视频日志降噪（status 真变了才记一行）。\n"
           @"1.0.19：卡片面板换成设置页本身做成卡片（皇上确认：不要 1.0.18 那张深色导航卡片）——点龙头浮动钮打开一张浮动卡片，卡片里就是真正的设置页（白卡头＋搜索框＋分区列表全是设置页自己的，分区行点进子页在卡片内的导航栈上推，不展开全屏；点卡片外／点「关闭」关掉）；面板打开/关闭/点浮动钮都记日志，日志里能看到有没有点开过；画中画修两处实锤：合成图层以前只建不挂进窗口，系统根本不启动（1.0.18 日志 8 次调用 0 成功、7 次没回调），现在图层挂到窗口右下角 2×2 的小宿主上再启动；兜底播放器以前画中画失败/没回调后还留着继续放（退出抖音后声音一直讲的根因），现在失败就停、8 秒没回调看门狗停、切后台 3 秒没接上也停，并记「兜底播放器：已停止」；长按网格点「画中画播放」先把 sheet 收掉再找播放器（以前 sheet 盖着，查找看不到 feed 的播放器）。\n"
           @"1.0.20：卡片点不了修好（遮罩点按手势以前把卡片里所有轻点都取消了，现在手势只认卡片外的触摸，行/开关/按钮都能点）；卡片改成影片的深色毛玻璃＋底部「完成」按钮（里面还是设置页本身）；所有入口都开卡片（浮动钮、抖音设置行、双指长按，通通不再全屏）；双指长按叫出卡片；卡片记住上次停在哪一页，重开回到那页；「后台音频」拆成两个开关（切后台触发画中画／后台听视频）；日志页加「复制日志」文字按钮＋搜索框；画中画宿主改成 320×180 可见尺寸再测、C 路补时间戳（修 1 秒误杀）、切后台触发加 10 秒冷却。\n"
           @"1.0.21：卡片改浅色玻璃＋按键（影片的按键感＋照片里文件夹那种浅色毛玻璃：卡片首页是标题＋搜索框＋两列按键，通用设置进设置列表、播放互动进「常用功能」分区、诊断反馈进日志、关于进关于页，首页／朋友／消息／我切底栏是探针；长按面板和关于页也改同款浅色玻璃，关于页对齐重查一遍）；双指长按只开卡片，不再触发倍速；画中画：A 路排除自己的宿主图层（修自己图层被当成系统播放器捡起来的竞态）、KVO 就绪后回主线程再调 start、切后台重复触发 10 秒内直接丢弃；兜底播放器加硬上限：调 start 后 3 秒没系统回调就必停，后台任务结束时没出来也停（修 8.log 实锤：没窗口的兜底一直响到会话结束）；主线程卡住看门狗（抓冻住的证据，冻住原因还没定死）；划掉后台还在响：WillTerminate 尽力停兜底＋停画中画，切后台触发时记一行音频状态。\n"
           @"1.0.22：卡片玻璃重做（1.0.21 渲染出来是平灰块不是玻璃：遮罩黑 0.5 压暗一半改成 0.12，糊换更透的 ExtraLight、淡白 tint 降到 0.06，卡片收小不再近全屏；长按面板同款）；底栏四键探针改递归全树找底栏控制器（以前只查 rootVC 一层，17 次点按全死在没找到控制器），找到记控制器类名和 tab 标题列表；卡片里推上去的页面（设置列表／关于／日志）改不透明、导航栏也不透明（以前半透明，上一页的按键和 QQ 号从下面透出来，关于页滚到顶还被导航栏盖住；玻璃只留给卡片外壳和首页）；设置行右边被卡片裁掉修好（表按 view 最终尺寸排、宽变了重建行）；设置行太透背后视频透出来修好（行底改不透明）；日志页文字右边被裁修好、打开总停在最上面那段旧日志修好（等排版完再滚到底，重读记一行）；常用功能最底下一行被「完成」按钮盖住一半修好（列表底部留白）。\n"
           @"1.0.23：卡片改回照片那款 A——8 按键首页拿掉，点开卡片直接就是设置列表，浅色实心卡不再追毛玻璃，金底「完成」保留，记页保留；跳过 AD 章节是探测（广告章节识别字段没确认，开关开后只在日志里 dump 章节模型字段，不跳过，等真机日志定下字段再接）；评论文字变蓝（开关，只改正文颜色，用户名/时间不动，正文标签是启发式定位，需真机验证）；长按面板新增获取作品数据（弹窗显示＋复制到剪贴板）和图片预览（图集全屏翻页看，点一下关闭）；复制下载链接和解析保存不用加——咱们已经有了（687 复制无水印链接、673 接口保存＋666 保存视频／668 保存音频）。\n"
           @"1.0.23（第二批，影片功能）：自动连播（播满当前视频时长切下一个，直播间不跑）；推荐页跳过购物视频（带购物标签的推荐视频直接跳过）；长按面板可换背景图、材质三选一（磨砂／液态玻璃／清透玻璃；真液态玻璃要 iOS 26，iOS 16 上液态玻璃用加粗材质近似）、排列可调（每排 2/3/4 个／横向等列／自定义列数）、背景模糊度可调（默认 58）、格子微透明；评论区仅复制评论文字（长按评论只复制正文）；首页全屏播放、发图发视频默认勾选原图（改名对齐已有功能）；显示功能按钮（关闭／倍速／快进三档，快进点一下 +10 秒）；解析图片增加保存视频按钮（图集「制作视频」改叫「保存视频」）；消息防撤回是探测（与原来 (24) 同功能，只改名；撤回处理类没定位到，只记日志）；仅看一次开启下载按钮是探测（没找到可验证的 hook 点，开关开后 dump 相关类名记日志）；双击消息快捷回复（消息页双击聚焦输入框，输入框是启发式找的，需真机验证）；消息界面点加号弹出相册图片是探测（开关开后 dump 输入栏按钮类名记日志，等真机日志定 hook 点）；续火花自动发消息（长按联系人头像触发，模板在设置里填、用 | 分隔多条，多条时目前只发第 1 条，发送按钮找不到时只填文字不自动发）；玻璃评论面板（评论面板改 ExtraLight 毛玻璃，评论／AI 解析双页签在面板顶部，AI 解析要自己填 OpenAI 兼容接口的 Key＋地址＋模型，没填 Key 时只显示配置提示）；插件配置页（关于页加清除缓存、Telegram 暂未开通提示行，其余版本／更新日志／QQ群／自定义图片早有了）；底部悬浮毛玻璃胶囊栏（底栏改悬浮圆角毛玻璃条）。\n"
           @"1.0.24：长按面板字重影修好（网格盖上后把底下抖音原生长按列表藏起来，收起恢复；糊 58%、格子微透明不变）；设置卡背景图改全屏（自定义背景图铺满整个卡片背后，导航栏、列表、完成按钮都在图上，行底半透明白）；语音包和在线音色并成一个统一语音包页（内置／在线／导入同在一张表，统一搜索，文件夹分组，导入导出，点行试听；导入的录音点一下就播放，不能用来合成文字）；双击下载（视频左半边双击直接保存、右半边弹菜单；双击弹窗可精简成只留下载）；首页下移（底栏高度可调）和底部字体大小可调；语音包导入（mp4/mov 选入后转音频进语音包，音频直接复制）；下载面板可调（长按网格格子高度／左右边距／格子透明度／格子颜色都能在设置里调）；保存相册详细（保存时附作品信息：视频 ID、时长、点赞/评论/分享/收藏/播放数、音乐名；开关在常用功能，默认关）；文案备忘录（本地备忘列表，点行复制，左滑删除；定时自动发送不做）；保存他人语音仍是探测（评论语音的类没定位到，保存路径建不出来，只记日志，等真机探针）；接口保存默认接 Lee 给的原画质接口（装完不用填就能点，设置里能改能清空；解析多字段容错，首次解析成功把 data 的字段名记进日志，没真视频验过成功格式，以日志为准）；关于页 QQ 行改成个人号「QQ：2309103548」（2309103548 是个人 QQ，群是 1130823454）；冻住调查：静态＋日志分析结论写进日志（巡检耗时随时间平坦、主线程是突然堵住 111 秒、音视频是缓冲排空后慢慢停；看门狗补记巡检停滞和冻住前最后活动；冻住本身这版没修）。\n"
           @"1.0.25：关于页拿掉两行（恢复横幅、版本检查都不再提供；远程模式那项不动）；日志改名「抖音日志」（关于页那行、日志页标题、复制日志的日志行都改）；按作者记倍速的功能整个取消（设置行、开关、记录和恢复逻辑都拿掉）；长按重影重做（每次打开网格都重藏原生列表，收起时网格拿掉、原生列表恢复显示，点开子页返回不再误判收起）；评论语音保存接线修好（设置页开关终于连到长按菜单的保存代码，本地文件优先复制）；评论语音保存探针：长按语音评论时记 audioFilePath 与 content（为下版保存准备）；底栏高度加钳制（错填大数不再压没视频，启动时记一行底栏高度日志）。\n"
           @"1.0.26：长按面板黑修好一半——毛玻璃下面垫一层不透白底，底板不再依赖背后糊什么，藏表照样藏、重影照样不回来；模糊度钳下限 20（防调到 0 全透）；每次长按都记一行面板设置（材质／模糊度／格子颜色／透明度／背景图有无）和一行面板 bounds＋首格 frame（格子看不见时日志能定论是布局还是渲染；浅色底只解决底黑那半，格子本身看不见的根因还没钉死，等真机点按测试）；快捷面板背景图每次长按都刷新（换图不用杀掉重开，存图成功／失败也记日志）；空文件夹也显示分区（建成功弹提示）；在线音色长按加「下载试听音频」（存进「我的导入」，存的只是一句固定试听句的录音，不是音色本身，离线不能合成任意文字）；在线列表拉取失败时分区脚注留提示，不再静默失败。";
}

// ===== 画中画查找（1.0.15 重写）=====
// 皇上 20:14：点「画中画播放」一直报“没找到播放的视频”，哪怕视频正在播——
// 旧 finder 只在 keyWindow 里找一层 AVPlayerLayer，他那版抖音的播放器根本不在那儿。
// 新 finder 分三路，按顺序试（详细日志只在画中画要用的那次记，平时调用不记，
// 免得 2 秒巡检（直播静音开着时）把日志刷爆）：
//   A. 全部窗口（所有 scene 的窗口，不只 keyWindow）里递归找 AVPlayerLayer
//      （图层树也递归——旧代码只查 view.layer.sublayers 一层，包在容器图层里的就漏了）；
//   B. 播放器控制器（AWEAwemePlayVideoViewController 等）里 KVC 探针找 AVPlayer / AVPlayerLayer
//      （键名按惯例猜，每个键都 try/catch，拿不到就记一行，不崩）；
//   C. 有 AVPlayer 没图层时，用播放器新建一个 AVPlayerLayer 再建 PiP 控制器（见 GHLStartPiP）。
//   D. （1.0.16 兜底）A/B/C 全空时，用当前视频链接自起一个 AVPlayer 做画中画
//      （见 GHLStartFallbackPiP；从头播，接不上进度，链接可能是短效签名）。
//      直播分支（1.0.17）：在直播间时从 room model 取 HLS 拉流地址走同一套兜底；
//      只有 FLV/RTMP 时记一行，不转封装。
// 什么都没找到时，日志写明现场（窗口数、各类图层数、探针结果），方便下一步判断——
// 比如满屏都是 AVSampleBufferDisplayLayer，就说明这版抖音走自有播放器渲染，
// 系统画中画挂不上现有播放器，才走 D 路兜底。

// 前向声明（实现在下面）。
static void GHLFindPlayerViewControllersInVC(UIViewController *vc, NSMutableArray *out);

// 全部窗口（去重）：sharedApplication.windows 再加每个 UIWindowScene 的 windows。
static NSArray<UIWindow *> *GHLAllAppWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window && ![windows containsObject:window]) [windows addObject:window];
    }
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window && ![windows containsObject:window]) [windows addObject:window];
            }
        }
    }
    return windows;
}

// 1.0.21：A 路排除自己的宿主图层——宿主 view 和合成图层的声明必须放在 finder 前面
// （以前在 600 行以后，finder 看不到，自己的兜底图层会被当成系统播放器捡起来，
// 8.log 18:21:26 实锤的竞态：前一次 D 路兜底还在 KVO 加载，A 路把它捡起来又调了一次 start）。
static UIView *ghlPiPLayerHostView = nil; // 合成图层宿主 view（挂在窗口里，320x180）
static AVPlayerLayer *ghlPiPSyntheticLayer = nil; // C/D 路新建的图层（控制器会留住，这里再强引用一份）

// 递归收图层：AVPlayerLayer 直接收；AVSampleBufferDisplayLayer / Metal / GL 图层只计数
// （诊断用：它们出现说明抖音在用自有播放器渲染，而不是 AVPlayerLayer）。
static void GHLCollectPlayerLayersInLayer(CALayer *layer, NSMutableArray<AVPlayerLayer *> *out, NSInteger *sampleBufferLayerCount, NSInteger *metalLayerCount) {
    if (!layer) return;
    for (CALayer *sublayer in layer.sublayers ?: @[]) {
        if ([sublayer isKindOfClass:[AVPlayerLayer class]]) {
            // 1.0.21：跳过自己的宿主图层——那是上次 D 路兜底自起播放器的图层，
            // 不是抖音系统的播放器；捡起来再调 start 就是 8.log 里的竞态。
            if (sublayer == (CALayer *)ghlPiPSyntheticLayer || sublayer.superlayer == ghlPiPLayerHostView.layer) continue;
            [out addObject:(AVPlayerLayer *)sublayer];
        } else if ([sublayer isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
            if (sampleBufferLayerCount) (*sampleBufferLayerCount)++;
        } else if ([sublayer isKindOfClass:[CAMetalLayer class]] || [sublayer isKindOfClass:[CAEAGLLayer class]]) {
            if (metalLayerCount) (*metalLayerCount)++;
        }
        GHLCollectPlayerLayersInLayer(sublayer, out, sampleBufferLayerCount, metalLayerCount);
    }
}

static void GHLCollectPlayerLayersInView(UIView *view, NSMutableArray<AVPlayerLayer *> *out, NSInteger *sampleBufferLayerCount, NSInteger *metalLayerCount) {
    if (!view) return;
    GHLCollectPlayerLayersInLayer(view.layer, out, sampleBufferLayerCount, metalLayerCount);
    for (UIView *subview in view.subviews) {
        GHLCollectPlayerLayersInView(subview, out, sampleBufferLayerCount, metalLayerCount);
    }
}

// A 路：在全部窗口里找 AVPlayerLayer（verbose 时记详细日志）。
// 优先正在播的（rate > 0），其次带播放器的，最后任意一个。
static AVPlayerLayer *GHLFindPlayingAVPlayerLayerVerbose(BOOL verbose, NSInteger *outSampleBufferLayerCount, NSInteger *outMetalLayerCount) {
    __block AVPlayerLayer *found = nil;
    __block AVPlayerLayer *firstWithPlayer = nil;
    __block AVPlayerLayer *firstLayer = nil;
    __block NSInteger windowCount = 0;
    __block NSInteger withPlayerCount = 0;
    __block NSInteger sampleBufferCount = 0;
    __block NSInteger metalCount = 0;
    void (^collect)(void) = ^{
      @try {
          NSArray<UIWindow *> *windows = GHLAllAppWindows();
          windowCount = (NSInteger)windows.count;
          NSMutableArray<AVPlayerLayer *> *layers = [NSMutableArray array];
          NSMutableArray<NSString *> *windowClasses = [NSMutableArray array];
          for (UIWindow *window in windows) {
              if (!window) continue;
              [windowClasses addObject:NSStringFromClass([window class])];
              GHLCollectPlayerLayersInView(window, layers, &sampleBufferCount, &metalCount);
          }
          for (AVPlayerLayer *layer in layers) {
              AVPlayer *player = layer.player;
              if (!firstLayer) firstLayer = layer;
              if (player) {
                  withPlayerCount++;
                  if (!firstWithPlayer) firstWithPlayer = layer;
                  if (player.rate > 0) {
                      found = layer;
                      break;
                  }
              }
          }
          if (!found) found = firstWithPlayer ?: firstLayer;
          if (verbose) {
              GHLLog(@"画中画查找 A 路：扫了 %ld 个窗口（%@），AVPlayerLayer %lu 个（带播放器 %ld 个）/ AVSampleBufferDisplayLayer %ld 个 / Metal 或 GL 图层 %ld 个，结论：%@",
                     (long)windowCount, [windowClasses componentsJoinedByString:@"、"],
                     (unsigned long)layers.count, (long)withPlayerCount,
                     (long)sampleBufferCount, (long)metalCount,
                     found ? (found.player && found.player.rate > 0 ? @"找到正在播的图层" : @"找到图层（没在播或没挂播放器）") : @"一个 AVPlayerLayer 都没有");
          }
      } @catch (__unused NSException *exception) {
          if (verbose) GHLLog(@"画中画查找 A 路：遍历窗口时异常");
      }
    };
    if ([NSThread isMainThread]) {
        collect();
    } else {
        dispatch_sync(dispatch_get_main_queue(), collect);
    }
    if (outSampleBufferLayerCount) *outSampleBufferLayerCount = sampleBufferCount;
    if (outMetalLayerCount) *outMetalLayerCount = metalCount;
    return found;
}

AVPlayerLayer *GHLFindPlayingAVPlayerLayer(void) {
    return GHLFindPlayingAVPlayerLayerVerbose(NO, NULL, NULL);
}

// 1.0.16：运行时 VC 类名全 dump（判别播放器控制器是不是改名了——B 路只认 3 个类名，
// 控制器改名会让 B 路永远 0 个；这一行打出来就能看到底有没有播放器控制器、叫什么）。
// 只在 verbose 时调（画中画查找那次），平时不记。
static void GHLCollectAllViewControllerClassesInVC(UIViewController *vc, NSMutableSet<NSString *> *out) {
    if (!vc || !out) return;
    [out addObject:NSStringFromClass([vc class])];
    for (UIViewController *child in vc.childViewControllers) {
        GHLCollectAllViewControllerClassesInVC(child, out);
    }
    if (vc.presentedViewController) GHLCollectAllViewControllerClassesInVC(vc.presentedViewController, out);
}

// B 路：在播放器控制器上 KVC 探针找 AVPlayer / AVPlayerLayer（verbose 时记结果）。
// 键名是按惯例猜的：拿不到就记一行，不崩；拿到了先验类再用。
static AVPlayer *GHLProbePlayerFromPlayerVCs(BOOL verbose, AVPlayerLayer **outLayer) {
    static NSArray<NSString *> *playerKeys = nil;
    static NSArray<NSString *> *layerKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      playerKeys = @[@"player", @"avPlayer", @"videoPlayer", @"currentPlayer", @"playerController", @"videoController", @"mediaPlayer", @"enginePlayer"];
      layerKeys = @[@"playerLayer", @"videoLayer", @"avPlayerLayer"];
    });
    __block AVPlayer *foundPlayer = nil;
    __block AVPlayerLayer *foundLayer = nil;
    void (^probe)(void) = ^{
      @try {
          NSArray<UIWindow *> *windows = GHLAllAppWindows();
          NSMutableArray *playerVCs = [NSMutableArray array];
          NSMutableArray<NSString *> *vcClasses = [NSMutableArray array];
          for (UIWindow *window in windows) {
              UIViewController *root = window.rootViewController;
              while (root.presentedViewController) root = root.presentedViewController;
              GHLFindPlayerViewControllersInVC(root, playerVCs);
          }
          for (UIViewController *vc in playerVCs) {
              [vcClasses addObject:NSStringFromClass([vc class])];
          }
          if (verbose) {
              GHLLog(@"画中画查找 B 路：播放器控制器 %lu 个（%@）", (unsigned long)playerVCs.count, playerVCs.count > 0 ? [vcClasses componentsJoinedByString:@"、"] : @"无");
              // 1.0.16：窗口里控制器类名全 dump（B 路 0 个时看看到底有没有播放器控制器、叫什么）——
              // 40 个封顶，免得一行太长；只在画中画查找那次记。
              NSMutableSet<NSString *> *allVCClasses = [NSMutableSet set];
              for (UIWindow *window in windows) {
                  UIViewController *root = window.rootViewController;
                  while (root.presentedViewController) root = root.presentedViewController;
                  GHLCollectAllViewControllerClassesInVC(root, allVCClasses);
              }
              NSArray<NSString *> *sortedVCClasses = [[allVCClasses allObjects] sortedArrayUsingSelector:@selector(compare:)];
              if (sortedVCClasses.count > 40) sortedVCClasses = [sortedVCClasses subarrayWithRange:NSMakeRange(0, 40)];
              GHLLog(@"画中画查找 B 路：窗口里控制器共 %lu 类：%@", (unsigned long)allVCClasses.count, [sortedVCClasses componentsJoinedByString:@"、"]);
          }
          // 1.0.17：键存在但值不是播放器/图层时补记一行（之前是盲点：只记命中，键存在但类型不对时静默跳过）。
          // 只在 verbose 时记，8 条封顶，免得刷屏。
          __block NSInteger mismatchLogCount = 0;
          for (UIViewController *vc in playerVCs) {
              if (foundPlayer || foundLayer) break;
              for (NSString *key in layerKeys) {
                  @try {
                      id value = [vc valueForKey:key];
                      if ([value isKindOfClass:[AVPlayerLayer class]]) {
                          foundLayer = (AVPlayerLayer *)value;
                          if (verbose) GHLLog(@"画中画查找 B 路：%@ 上 KVC 键 %@ 拿到 AVPlayerLayer", NSStringFromClass([vc class]), key);
                          break;
                      } else if (value && verbose && mismatchLogCount < 8) {
                          mismatchLogCount++;
                          GHLLog(@"画中画查找 B 路：%@ 上 KVC 键 %@ 存在，但值是 %@（不是 AVPlayerLayer）", NSStringFromClass([vc class]), key, NSStringFromClass([value class]));
                      }
                  } @catch (__unused NSException *exception) {
                  }
              }
              if (foundLayer) break;
              for (NSString *key in playerKeys) {
                  @try {
                      id value = [vc valueForKey:key];
                      if ([value isKindOfClass:[AVPlayer class]]) {
                          foundPlayer = (AVPlayer *)value;
                          if (verbose) GHLLog(@"画中画查找 B 路：%@ 上 KVC 键 %@ 拿到 AVPlayer", NSStringFromClass([vc class]), key);
                          break;
                      } else if (value && verbose && mismatchLogCount < 8) {
                          mismatchLogCount++;
                          GHLLog(@"画中画查找 B 路：%@ 上 KVC 键 %@ 存在，但值是 %@（不是 AVPlayer）", NSStringFromClass([vc class]), key, NSStringFromClass([value class]));
                      }
                  } @catch (__unused NSException *exception) {
                  }
              }
          }
          if (verbose && !foundPlayer && !foundLayer) {
              GHLLog(@"画中画查找 B 路：KVC 探针什么都没拿到");
          }
      } @catch (__unused NSException *exception) {
          if (verbose) GHLLog(@"画中画查找 B 路：遍历控制器时异常");
      }
    };
    if ([NSThread isMainThread]) {
        probe();
    } else {
        dispatch_sync(dispatch_get_main_queue(), probe);
    }
    if (outLayer) *outLayer = foundLayer;
    return foundPlayer;
}

// 画中画专用：A 路（图层）→ B 路（控制器探针），返回 AVPlayer；
// 有图层时通过 outLayer 一起返回（没有时 outLayer 置 nil，调用方用播放器新建图层）。
// 详细日志只在这里记（平时快进/静音/截图调用的安静版不记，免得刷屏）。
static AVPlayer *GHLFindPlayingAVPlayerForPiP(AVPlayerLayer **outLayer) {
    AVPlayerLayer *layer = GHLFindPlayingAVPlayerLayerVerbose(YES, NULL, NULL);
    AVPlayer *player = layer.player;
    if (player) {
        if (outLayer) *outLayer = layer;
        return player;
    }
    if (layer) {
        // 图层找到了但上面没挂播放器：记一笔，再走 B 路。
        GHLLog(@"画中画查找：找到 AVPlayerLayer 但 player 是 nil，继续 B 路探针");
    }
    AVPlayerLayer *probeLayer = nil;
    AVPlayer *probePlayer = GHLProbePlayerFromPlayerVCs(YES, &probeLayer);
    if (probeLayer) {
        if (outLayer) *outLayer = probeLayer;
        return probeLayer.player;
    }
    if (probePlayer) {
        if (outLayer) *outLayer = nil;
        return probePlayer;
    }
    if (outLayer) *outLayer = nil;
    GHLLog(@"画中画查找：A 路 B 路都没找到播放器（图层和 KVC 探针都是空）");
    return nil;
}

AVPlayer *GHLFindPlayingAVPlayer(void) {
    return GHLFindPlayingAVPlayerLayer().player;
}

double GHLCurrentPlayerTime(void) {
    AVPlayer *player = GHLFindPlayingAVPlayer();
    if (!player || !player.currentItem) return -1;
    return CMTimeGetSeconds(player.currentTime);
}

void GHLSeekCurrentPlayerBySeconds(double seconds) {
    AVPlayer *player = GHLFindPlayingAVPlayer();
    if (!player || !player.currentItem) {
        GHLLog(@"快进：没找到正在播放的播放器");
        return;
    }
    CMTime current = player.currentTime;
    CMTime duration = player.currentItem.duration;
    double target = CMTimeGetSeconds(current) + seconds;
    if (target < 0) target = 0;
    if (CMTIME_IS_VALID(duration) && CMTIME_IS_NUMERIC(duration)) {
        double total = CMTimeGetSeconds(duration);
        if (target > total) target = total;
    }
    [player seekToTime:CMTimeMakeWithSeconds(target, NSEC_PER_SEC)
       toleranceBefore:kCMTimeZero
        toleranceAfter:kCMTimeZero];
    GHLLog(@"快进：%+.0f 秒 -> %.1f", seconds, target);
}

void GHLPauseCurrentPlayer(void) {
    AVPlayer *player = GHLFindPlayingAVPlayer();
    if (!player) {
        GHLLog(@"暂停：没找到正在播放的播放器");
        return;
    }
    [player pause];
    GHLLog(@"已暂停当前视频");
}

#pragma mark - (1) 睡眠定时

static NSTimer *ghlSleepTimer = nil;

void GHLRestartSleepTimer(void) {
    GHLRunOnMain(^{
      [ghlSleepTimer invalidate];
      ghlSleepTimer = nil;
      NSString *choice = GHLGetString(GHL_KEY_SLEEP_TIMER) ?: @"关闭";
      NSTimeInterval minutes = 0;
      if ([choice isEqualToString:@"15分钟"]) minutes = 15;
      else if ([choice isEqualToString:@"30分钟"]) minutes = 30;
      else if ([choice isEqualToString:@"60分钟"]) minutes = 60;
      if (minutes <= 0) {
          GHLLog(@"睡眠定时：关闭");
          return;
      }
      ghlSleepTimer = [NSTimer scheduledTimerWithTimeInterval:minutes * 60
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
                                                          GHLPauseCurrentPlayer();
                                                          [DYYYUtils showToast:@"睡眠定时到，已暂停播放"];
                                                          GHLLog(@"睡眠定时到（%@），已暂停", choice);
                                                        }];
      [DYYYUtils showToast:[NSString stringWithFormat:@"睡眠定时已设：%@后暂停", choice]];
      GHLLog(@"睡眠定时：已设 %@", choice);
    });
}

#pragma mark - (9) 夜间护眼

void GHLApplyNightMode(BOOL on) {
    GHLRunOnMain(^{
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
      if (on) {
          if (![defaults objectForKey:@"GHLNightSavedBrightness"]) {
              [defaults setFloat:[UIScreen mainScreen].brightness forKey:@"GHLNightSavedBrightness"];
          }
          NSString *value = GHLGetString(GHL_KEY_NIGHT_BRIGHTNESS);
          CGFloat target = value.length > 0 ? [value floatValue] : 0.3f;
          if (target <= 0 || target > 1) target = 0.3f;
          [UIScreen mainScreen].brightness = target;
          if (window) window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
          GHLLog(@"夜间护眼：开，亮度 %.2f", target);
      } else {
          NSNumber *saved = [defaults objectForKey:@"GHLNightSavedBrightness"];
          if (saved) [UIScreen mainScreen].brightness = [saved floatValue];
          [defaults removeObjectForKey:@"GHLNightSavedBrightness"];
          if (window) window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
          GHLLog(@"夜间护眼：关，已恢复亮度");
      }
    });
}

#pragma mark - (2) 画中画

static AVPictureInPictureController *ghlPiPController = nil;
// （1.0.21：ghlPiPSyntheticLayer 的声明挪到 finder 前面了，A 路排除自己图层要用。）

// ===== 画中画兜底 D 路（1.0.16）=====
// 抖音自有播放器（Metal 渲染）没有 AVPlayerLayer，A/B/C 全空时只能自起播放器。
// 老实边界：从头播（接不上进度）、链接可能是带签名的短效链接（过期播不了）、
// 后台/锁屏/与原视频声音冲突都要真机验证。player/item 都强引用留住（画中画停了
// 也不放，下次同视频复用）；item 就绪（KVO status）后再 startPictureInPicture。
static AVPlayer *ghlPiPFallbackPlayer = nil;
static AVPlayerItem *ghlPiPFallbackItem = nil;
static BOOL ghlPiPFallbackObserving = NO;
static BOOL ghlPiPFallbackStarted = NO;
static char kGHLPiPFallbackKVOContext;

// 画中画 start 回调标记：didStart/失败任一到就置 YES；每次调 startPictureInPicture 前清掉。
// 3 秒都没回调＝系统根本没接上（1.0.18 日志：8 次调用 0 成功、7 次没任何回调；
// 8.log：没窗口的兜底一直响到会话结束），看门狗就把兜底播放器停掉，别让它在后台一直出声。
static BOOL ghlPiPStartCallbackReceived = NO;
static CFAbsoluteTime ghlPiPLastStartTime = 0;
// （1.0.21：ghlPiPLayerHostView 的声明挪到 finder 前面了，A 路排除自己图层要用。）
// 1.0.21：第 7 项去重——上次切后台触发的时间（不管有没有调 start）；10 秒内重复触发直接丢弃。
// （8.log：D 里 4 秒内重复触发 5 次，每次都重建兜底播放器，旧看门狗全被新播放器顶掉。
//  旧的冷却只看上次 start，没调 start 时挡不住——通知中心下拉也会触发 WillResignActive，
//  回来又 DidBecomeActive 清掉 guard，一拉一回就是一次新触发。）
static CFAbsoluteTime ghlPiPLastTriggerTime = 0;
// 1.0.21：兜底播放器建的时候 App 是不是已在后台（WillResignActive 时 state 已是 Inactive）。
// 建的时候在后台、就绪时已回前台＝用户回来了，别再启动画中画，直接停掉兜底（免得两个声音叠着响）。
static BOOL ghlPiPFallbackCreatedWhileBackground = NO;

// 前向声明（定义在下面 GHLStartPiP 前；GHLPiPDelegate 的 KVO 回调里先用到）。
static void GHLCleanupFallbackPiPObserver(void);
static void GHLCleanupFallbackPiPPlayer(void);
static void GHLNotePiPStartAttempted(void);
static void GHLStopFallbackPlayerIfPiPNotStarted(NSString *reason); // 1.0.21：3 秒看门狗／后台任务结束时的共用停播

// 1.0.15：%ctor 里三个 addObserverForName:usingBlock: 的返回值以前全丢了——
// ARC 下 token 立刻释放，NSNotificationCenter 只弱引用它，监听随即注销，
// GHLStartPiP() 一次都没跑过（皇上 19:53「滑出抖音没有小窗」的根因）。
// 现在把 token 存进 file-static 变量（照 DYYY.xm 的 dyyy*Token 写法），
// applicationWillTerminate 时移除（见 %ctor 后面的 %hook AppDelegate）。
static id ghlScreenshotObserverToken = nil;
static id ghlVolumeObserverToken = nil;
static id ghlPiPWillResignActiveToken = nil;
static id ghlPiPDidEnterBackgroundToken = nil;
static id ghlPiPDidBecomeActiveToken = nil;
// 一次后台只触发一次画中画：WillResignActive 先触发，DidEnterBackground 兜底时
// 靠它跳过；回到前台（DidBecomeActive）再清掉，下次切后台重新触发。
static BOOL ghlPiPTriggeredForCurrentBackground = NO;
// 兜底路径的后台任务：DidEnterBackground 里起画中画时 App 随时被挂起，
// 开一个后台任务撑到系统回调（didStart/失败）或 10 秒超时。
static UIBackgroundTaskIdentifier ghlPiPBackgroundTask = UIBackgroundTaskInvalid;

static void GHLEndPiPBackgroundTask(void) {
    if (ghlPiPBackgroundTask == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = ghlPiPBackgroundTask;
    ghlPiPBackgroundTask = UIBackgroundTaskInvalid;
    [[UIApplication sharedApplication] endBackgroundTask:task];
}

// 1.0.20：兜底画中画的后台任务——WillResignActive 和 DidEnterBackground 两条路都开
// （以前只在 DidEnterBackground 的兜底分支开；正常流程 WillResignActive 先触发，
// D 路等 item 就绪要几秒，App 已在后台，没任务撑着随时被挂起）。
static void GHLBeginPiPBackgroundTaskIfNeeded(void) {
    if (ghlPiPTriggeredForCurrentBackground) return;
    if (!GHLGetBool(GHL_KEY_BACKGROUND_AUDIO)) return;
    if (ghlPiPBackgroundTask != UIBackgroundTaskInvalid) return;
    ghlPiPBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
      // 1.0.21：系统要收回后台时间了——画中画还没出来就先停兜底，别让它没窗口一直响。
      GHLStopFallbackPlayerIfPiPNotStarted(@"后台任务到期");
      GHLEndPiPBackgroundTask();
    }];
    UIBackgroundTaskIdentifier task = ghlPiPBackgroundTask;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      // 1.0.21：10 秒到了——没出来就停兜底，再结束这个任务（只结束自己这一份，
      // 别动后来新开的任务；以前直接调 GHLEndPiPBackgroundTask，会误结束新任务）。
      GHLStopFallbackPlayerIfPiPNotStarted(@"后台任务 10 秒到");
      if (ghlPiPBackgroundTask == task) GHLEndPiPBackgroundTask();
    });
}

static void GHLRemovePiPObservers(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (ghlScreenshotObserverToken) {
        [center removeObserver:ghlScreenshotObserverToken];
        ghlScreenshotObserverToken = nil;
    }
    if (ghlVolumeObserverToken) {
        [center removeObserver:ghlVolumeObserverToken];
        ghlVolumeObserverToken = nil;
    }
    if (ghlPiPWillResignActiveToken) {
        [center removeObserver:ghlPiPWillResignActiveToken];
        ghlPiPWillResignActiveToken = nil;
    }
    if (ghlPiPDidEnterBackgroundToken) {
        [center removeObserver:ghlPiPDidEnterBackgroundToken];
        ghlPiPDidEnterBackgroundToken = nil;
    }
    if (ghlPiPDidBecomeActiveToken) {
        [center removeObserver:ghlPiPDidBecomeActiveToken];
        ghlPiPDidBecomeActiveToken = nil;
    }
}

// 1.0.21：第 7 项——音频状态一行（切后台触发／已进后台／将终止三处共用，格式统一才好对照）。
// 两路会叠加：兜底播放器在播＋抖音自己的后台音频（status 2）同时响，日志里要分得清。
// （status 是 setListenVideoStatus 钩子记下的改写后值；-1 表示还没见过。）
static void GHLLogAudioState(NSString *when) {
    GHLLog(@"%@：音频状态：兜底播放器%@（%@），抖音后台听视频 status=%ld（开关 %@／%@），PiP 回调%@／小窗%@",
           when,
           ghlPiPFallbackPlayer ? @"在" : @"不在",
           (ghlPiPFallbackPlayer && ghlPiPFallbackPlayer.rate > 0) ? @"在播" : @"没播",
           (long)GHLCurrentListenVideoStatus(),
           GHLGetBool(GHL_KEY_BACKGROUND_LISTEN) ? @"开" : @"关",
           [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableBackgroundListen"] ? @"开" : @"关",
           ghlPiPStartCallbackReceived ? @"有" : @"无",
           (ghlPiPController && ghlPiPController.pictureInPictureActive) ? @"已出" : @"没出");
}

// 切后台时触发一次画中画（开关关着就不触发；已触发过就跳过，等回到前台再重置）。
static void GHLTriggerPiPForBackground(void) {
    if (ghlPiPTriggeredForCurrentBackground) return;
    // 1.0.21：第 7 项去重——距上次触发不足 10 秒直接丢弃，不要重复建兜底播放器
    // （8.log：D 里 4 秒内重复触发 5 次；旧冷却只看上次 start，没调 start 时挡不住——
    //  通知中心下拉也会触发 WillResignActive，回来又 DidBecomeActive 清掉 guard，
    //  一拉一回就是一次新触发，每次都重建兜底，旧看门狗全被新播放器顶掉）。
    if (ghlPiPLastTriggerTime > 0 && CFAbsoluteTimeGetCurrent() - ghlPiPLastTriggerTime < 10) {
        GHLLog(@"画中画：距上次触发不足 10 秒，丢弃重复触发");
        return;
    }
    // 1.0.20：距上次 start 未满 10 秒直接忽略（6.log 17:18 七秒连触三次，
    // 第三次 start 才 1 秒就被切后台 3 秒重查误杀；冷却后同一次后台只会触发一次）。
    if (ghlPiPLastStartTime > 0 && CFAbsoluteTimeGetCurrent() - ghlPiPLastStartTime < 10) {
        GHLLog(@"画中画：距上次启动不足 10 秒，跳过这次切后台触发");
        return;
    }
    if (!GHLGetBool(GHL_KEY_BACKGROUND_AUDIO)) return;
    ghlPiPTriggeredForCurrentBackground = YES;
    ghlPiPLastTriggerTime = CFAbsoluteTimeGetCurrent();
    // 1.0.21：第 7 项——每次切后台触发记一行音频状态。
    GHLLogAudioState(@"画中画：切后台触发");
    // 1.0.16：切后台触发也记调用方（判别是网格点按还是切后台）。
    GHLStartPiPWithCaller(@"切后台");
}

// 画中画 delegate：系统回调如实记日志（startPictureInPicture 只表示已调用，
// 小窗真出来要等 didStart；失败也只在这里才知道）。
@interface GHLPiPDelegate : NSObject <AVPictureInPictureControllerDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation GHLPiPDelegate

+ (instancetype)sharedDelegate {
    static GHLPiPDelegate *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      shared = [[self alloc] init];
    });
    return shared;
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    GHLLog(@"画中画：系统已开始画中画");
    ghlPiPStartCallbackReceived = YES;
    GHLEndPiPBackgroundTask();
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    GHLLog(@"画中画：系统启动失败：%@", error.localizedDescription ?: @"未知错误");
    ghlPiPStartCallbackReceived = YES;
    GHLEndPiPBackgroundTask();
    // 兜底播放器：画中画没接上就不能让它继续放，否则切后台后声音一直讲
    // （皇上 1.0.18 反馈「退出抖音还有声音在讲」）；只清兜底播放器，C 路用的原播放器不动。
    if (pictureInPictureController == ghlPiPController && ghlPiPFallbackPlayer) {
        GHLCleanupFallbackPiPPlayer();
    }
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    GHLLog(@"画中画：已退出画中画");
    // 兜底播放器是自己起的：小窗关了就停播，别让它在后台继续出声。
    if (ghlPiPFallbackPlayer) [ghlPiPFallbackPlayer pause];
    GHLEndPiPBackgroundTask();
}

// 兜底 item 的 KVO：就绪后再 startPictureInPicture（没就绪就直接调大概率失败）。
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kGHLPiPFallbackKVOContext) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item != ghlPiPFallbackItem) return; // 已换视频，旧 item 的回调不管
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            if (!ghlPiPFallbackStarted) {
                ghlPiPFallbackStarted = YES;
                // 1.0.21：KVO 回调不在主线程跑（AVFoundation 内部线程），startPictureInPicture
                // 必须回主线程调——后台线程调很可能系统根本不接（0 回调的嫌疑之一）。
                // 兜底是切后台建的、就绪时已回前台＝用户回来了：别启动，直接停掉兜底
                // （免得兜底和抖音自己的声音叠着响）。
                GHLRunOnMain(^{
                  if (!ghlPiPFallbackPlayer || !ghlPiPController) return; // 已经被停了（看门狗／3 秒检查）
                  if (ghlPiPFallbackCreatedWhileBackground &&
                      [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                      GHLLog(@"画中画：兜底就绪时已回前台，不启动画中画，停掉兜底播放器");
                      GHLCleanupFallbackPiPPlayer();
                      return;
                  }
                  [ghlPiPFallbackPlayer play];
                  [ghlPiPController startPictureInPicture];
                  GHLNotePiPStartAttempted();
                  GHLLog(@"画中画：已调用 startPictureInPicture（等系统回调）");
                });
            }
            GHLCleanupFallbackPiPObserver(); // 就绪了就不用再监听
        } else if (item.status == AVPlayerItemStatusFailed) {
            GHLLog(@"画中画兜底：播放地址打不开：%@", item.error.localizedDescription ?: @"未知错误");
            [DYYYUtils showToast:@"画中画启动失败"];
            GHLCleanupFallbackPiPPlayer();
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end

// 画中画前先把音频会话切到 playback 并激活（抖音原播放器没走这条路时 PiP 容易没声音）。
// 正常路和兜底路共用。只在类别不是 playback 时才改（只改类别、不动别的设置；失败如实记日志，不硬来）。
static void GHLPreparePiPAudioSession(void) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session.category isEqualToString:AVAudioSessionCategoryPlayback]) {
        NSString *oldCategory = session.category ?: @"未知";
        NSError *categoryError = nil;
        [session setCategory:AVAudioSessionCategoryPlayback error:&categoryError];
        if (categoryError) {
            GHLLog(@"画中画：音频会话改 playback 失败：%@", categoryError.localizedDescription);
        } else {
            GHLLog(@"画中画：音频会话已改成 playback（原来 %@）", oldCategory);
        }
    }
    NSError *activeError = nil;
    [session setActive:YES error:&activeError];
    if (activeError) {
        GHLLog(@"画中画：音频会话激活失败：%@", activeError.localizedDescription);
    }
}

// 兜底 D 路（1.0.16）：A/B/C 全空时用当前视频链接自起一个 AVPlayer 做画中画。
// 老实边界：会从头播（接不上当前进度）；播放地址可能是带签名的短效链接（过期播不了）；
// 后台行为、锁屏控制、与抖音原播放器的声音冲突都要真机验证。
// 直播分支（1.0.17）：直播间没有 video.playURL，改从 room model 取 HLS 拉流地址
// （见 GHLProbeLiveStreamURL）；只有 FLV/RTMP 时记一行，不转封装。

// 当前视频的播放地址（复用保存视频那套取法：video.playURL.originURLList 首个；
// 图集视频走当前图的 clipVideo.playURL）。
static NSURL *GHLCurrentVideoPlayURL(void) {
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    if (!model) return nil;
    @try {
        AWEVideoModel *videoModel = model.video;
        if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
            NSString *urlString = videoModel.playURL.originURLList.firstObject;
            if (urlString.length > 0) return [NSURL URLWithString:urlString];
        }
        if (model.awemeType == 68 && model.albumImages.count > 0 && model.currentImageIndex > 0 && model.currentImageIndex <= (NSInteger)model.albumImages.count) {
            AWEImageAlbumImageModel *imageModel = model.albumImages[model.currentImageIndex - 1];
            if (imageModel.clipVideo && imageModel.clipVideo.playURL) {
                return [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

// ===== 1.0.17：直播画中画探针（D 路直播分支用）=====
// 背景（2026-11-14 21:45 定死，GuHaiLongDouyin-3.log）：照片里卡住的小窗是抖音自己的
// 原生小窗，咱们一次都没启动过，修不了；普通视频走 1.0.16 的 D 路兜底能绕过去，
// 但直播间没有 video.playURL，D 路覆盖不了直播。
// 探针只在两处跑：画中画查找发生在直播间时、进直播间时各一次——绝不进 2 秒巡检，
// 免得刷屏。日志只记栏位名＋URL 长度＋前 60 字符，不记完整签名 URL。
// AVPlayer 只能播 HLS（.m3u8），不能播 FLV/RTMP：只有 FLV/RTMP 时如实记一行，不转封装。

// 递归收全部 VC（对象，不是类名）：子 VC + presented VC 都走。
static void GHLCollectAllViewControllersInVC(UIViewController *vc, NSMutableArray<UIViewController *> *out) {
    if (!vc || !out) return;
    [out addObject:vc];
    for (UIViewController *child in vc.childViewControllers) {
        GHLCollectAllViewControllersInVC(child, out);
    }
    if (vc.presentedViewController) GHLCollectAllViewControllersInVC(vc.presentedViewController, out);
}

// 对象属性名清单（往上走 3 层父类，去重，60 个封顶）。
static NSArray<NSString *> *GHLPropertyNamesOfObject(id obj) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    Class cls = [obj class];
    for (NSInteger level = 0; level < 3 && cls && cls != [NSObject class]; level++) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count && names.count < 60; i++) {
            NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
            if (name.length > 0 && ![seen containsObject:name]) {
                [seen addObject:name];
                [names addObject:name];
            }
        }
        free(props);
        cls = class_getSuperclass(cls);
    }
    return names;
}

// URL 分类：看内容，不看栏位名（栏位名可能骗人，内容不会）。
static NSString *GHLClassifyStreamURLString(NSString *urlString) {
    if (!urlString || urlString.length == 0) return nil;
    NSString *lower = urlString.lowercaseString;
    if ([lower containsString:@"m3u8"] || [lower containsString:@"hls"]) return @"HLS";
    if ([lower containsString:@"flv"]) return @"FLV";
    if ([lower containsString:@"rtmp"]) return @"RTMP";
    return @"其他";
}

// 前 60 字符（不记完整签名 URL）。
static NSString *GHLTruncatedURLString(NSString *urlString) {
    if (!urlString) return @"";
    if (urlString.length <= 60) return urlString;
    return [urlString substringToIndex:60];
}

// 一个候选值里找拉流地址：字符串直接分类；数组取首个字符串；字典在里面按
// hls/flv/rtmp 键找一层；其他对象枚举它的字符串属性（只找一层嵌套，HLS 优先）。
// 命中记进 hits（@{key,type,where,url}），HLS 地址另记进 hlsURLs。
static void GHLCollectStreamURLHitFromValue(id value, NSString *key, NSString *where, NSMutableArray<NSDictionary *> *hits, NSMutableArray<NSString *> *hlsURLs) {
    if (!value) return;
    NSString *urlString = nil;
    NSString *hitKey = key;
    if ([value isKindOfClass:[NSString class]]) {
        urlString = (NSString *)value;
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id element in (NSArray *)value) {
            if ([element isKindOfClass:[NSString class]] && ((NSString *)element).length > 0) {
                urlString = (NSString *)element;
                break;
            }
        }
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        for (NSString *subKey in @[@"hls_pull_url", @"flv_pull_url", @"rtmp_pull_url", @"pull_url", @"url"]) {
            id sub = ((NSDictionary *)value)[subKey];
            if ([sub isKindOfClass:[NSString class]] && ((NSString *)sub).length > 0) {
                urlString = (NSString *)sub;
                hitKey = [NSString stringWithFormat:@"%@.%@", key, subKey];
                break;
            }
        }
    } else if ([value isKindOfClass:[NSObject class]]) {
        // 嵌套对象（比如 stream_url 对象）：先找名字带 hls 的属性，再找任意 url/pull/stream/play 属性。
        NSArray<NSString *> *props = GHLPropertyNamesOfObject(value);
        for (NSInteger pass = 0; pass < 2 && !urlString; pass++) {
            for (NSString *prop in props) {
                NSString *lower = prop.lowercaseString;
                BOOL isURLish = [lower containsString:@"url"] || [lower containsString:@"pull"] || [lower containsString:@"stream"] || [lower containsString:@"play"];
                if (!isURLish) continue;
                if (pass == 0 && ![lower containsString:@"hls"]) continue;
                @try {
                    id sub = [value valueForKey:prop];
                    if ([sub isKindOfClass:[NSString class]] && ((NSString *)sub).length > 0) {
                        urlString = (NSString *)sub;
                        hitKey = [NSString stringWithFormat:@"%@.%@", key, prop];
                        break;
                    }
                } @catch (__unused NSException *exception) {
                }
            }
        }
    }
    if (!urlString || urlString.length == 0) return;
    NSString *type = GHLClassifyStreamURLString(urlString);
    if (!type) return;
    [hits addObject:@{@"key": hitKey, @"type": type, @"where": where, @"url": urlString}];
    if ([type isEqualToString:@"HLS"] && ![hlsURLs containsObject:urlString]) [hlsURLs addObject:urlString];
}

// 探一个模型对象：先按候选键逐个试，再把对象全部字符串属性里名字带 url/pull/stream/play 的都扫一遍
// （候选键没覆盖到的也抓出来）。
// 1.0.18：再往下探一层——1.0.17 定死：IESLiveRoomService 上用键 roomModel 拿到的是服务外壳，
// 真正的房间数据在它里面的 roomModel 属性里，之前从不往下探。容器键只认这几个，深度只多一层，
// 同一个对象不重复探（probed 按指针去重），避免循环引用兜圈子。
static void GHLProbeStreamURLOnModelDeep(id model, NSString *where, NSMutableArray<NSDictionary *> *hits, NSMutableArray<NSString *> *hlsURLs, NSMutableSet<NSNumber *> *probed, NSInteger depth) {
    if (!model || ![model isKindOfClass:[NSObject class]]) return;
    NSNumber *ptr = @((uintptr_t)(__bridge void *)model);
    if ([probed containsObject:ptr]) return;
    [probed addObject:ptr];
    static NSArray<NSString *> *urlKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      urlKeys = @[@"hls_pull_url", @"hlsPullUrl", @"pullUrl", @"pull_url", @"streamUrl", @"stream_url", @"playUrl", @"play_url", @"flv_pull_url", @"flvPullUrl", @"rtmp_pull_url", @"rtmpPullUrl", @"hls_url", @"hlsUrl", @"liveUrl", @"url", @"playbackUrl", @"streamURL", @"pullStreamUrl", @"pullURL", @"originPullUrl"];
    });
    for (NSString *key in urlKeys) {
        @try {
            id value = [model valueForKey:key];
            GHLCollectStreamURLHitFromValue(value, key, where, hits, hlsURLs);
        } @catch (__unused NSException *exception) {
        }
    }
    NSArray<NSString *> *propNames = GHLPropertyNamesOfObject(model);
    for (NSString *prop in propNames) {
        NSString *lower = prop.lowercaseString;
        if (![lower containsString:@"url"] && ![lower containsString:@"pull"] && ![lower containsString:@"stream"] && ![lower containsString:@"play"]) continue;
        if ([urlKeys containsObject:prop]) continue; // 第 1 步试过了
        @try {
            id value = [model valueForKey:prop];
            GHLCollectStreamURLHitFromValue(value, prop, where, hits, hlsURLs);
        } @catch (__unused NSException *exception) {
        }
    }
    if (depth >= 1) return; // 只多探一层，不无限下探
    static NSArray<NSString *> *containerKeys = nil;
    static dispatch_once_t onceToken2;
    dispatch_once(&onceToken2, ^{
      containerKeys = @[@"roomModel", @"room", @"roomInfo", @"liveRoom", @"api"];
    });
    for (NSString *key in containerKeys) {
        @try {
            id nested = [model valueForKey:key];
            if (!nested || ![nested isKindOfClass:[NSObject class]]) continue;
            if ([nested isKindOfClass:[NSString class]] || [nested isKindOfClass:[NSArray class]] || [nested isKindOfClass:[NSDictionary class]]) continue;
            NSString *nestedClass = NSStringFromClass([nested class]);
            if ([nestedClass hasPrefix:@"UI"] || [nestedClass hasPrefix:@"NS"] || [nestedClass hasPrefix:@"__NS"]) continue;
            NSNumber *nestedPtr = @((uintptr_t)(__bridge void *)nested);
            if ([probed containsObject:nestedPtr]) continue;
            GHLLog(@"直播画中画探针：下探一层 %@（%@，键 %@）", nestedClass, where, key);
            GHLProbeStreamURLOnModelDeep(nested, [NSString stringWithFormat:@"%@.%@", where, key], hits, hlsURLs, probed, depth + 1);
        } @catch (__unused NSException *exception) {
        }
    }
}

// 保持旧调用形式：新探一层从深度 0 开始，共用同一套去重集合。
static void GHLProbeStreamURLOnModel(id model, NSString *where, NSMutableArray<NSDictionary *> *hits, NSMutableArray<NSString *> *hlsURLs, NSMutableSet<NSNumber *> *probed) {
    GHLProbeStreamURLOnModelDeep(model, where, hits, hlsURLs, probed ?: [NSMutableSet set], 0);
}

// 1.0.17：直播间拉流地址探针。返回 HLS 拉流地址（NSURL），没有 HLS 时返回 nil。
// 跑两处：画中画查找发生在直播间时、进直播间时各一次（不在 2 秒巡检里跑）。
static NSURL *GHLProbeLiveStreamURL(void) {
    NSMutableArray<NSDictionary *> *hits = [NSMutableArray array];
    NSMutableArray<NSString *> *hlsURLs = [NSMutableArray array];
    // 1) 直播间 VC（类名含 Live，全树走，不只顶层）
    NSMutableArray<UIViewController *> *liveVCs = [NSMutableArray array];
    for (UIWindow *window in GHLAllAppWindows()) {
        UIViewController *root = window.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        NSMutableArray<UIViewController *> *all = [NSMutableArray array];
        GHLCollectAllViewControllersInVC(root, all);
        for (UIViewController *vc in all) {
            if ([NSStringFromClass([vc class]) rangeOfString:@"Live"].location != NSNotFound) {
                if (![liveVCs containsObject:vc] && liveVCs.count < 5) [liveVCs addObject:vc];
            }
        }
    }
    NSMutableArray<NSString *> *liveVCNames = [NSMutableArray array];
    for (UIViewController *vc in liveVCs) [liveVCNames addObject:NSStringFromClass([vc class])];
    GHLLog(@"直播画中画探针：直播间 VC %lu 个（前 5）：%@", (unsigned long)liveVCs.count, liveVCNames.count > 0 ? [liveVCNames componentsJoinedByString:@"、"] : @"无");
    static NSArray<NSString *> *modelKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      modelKeys = @[@"roomModel", @"liveRoomModel", @"room", @"model", @"liveModel", @"roomInfo", @"liveRoom", @"currentRoomModel", @"roomData", @"liveRoomInfo", @"roomViewModel", @"liveRoomViewModel", @"awemeModel", @"aweme"];
    });
    NSMutableSet<NSNumber *> *probedModels = [NSMutableSet set];
    for (UIViewController *vc in liveVCs) {
        NSString *vcName = NSStringFromClass([vc class]);
        for (NSString *key in modelKeys) {
            @try {
                id model = [vc valueForKey:key];
                if (!model || ![model isKindOfClass:[NSObject class]]) continue;
                NSNumber *ptr = @((uintptr_t)(__bridge void *)model);
                if ([probedModels containsObject:ptr]) continue;
                // 去重集合由 GHLProbeStreamURLOnModelDeep 统一加（下探一层也共用同一套）。
                NSString *modelClass = NSStringFromClass([model class]);
                if ([modelClass hasPrefix:@"UI"] || [modelClass hasPrefix:@"NS"] || [modelClass hasPrefix:@"__NS"]) continue;
                NSArray<NSString *> *props = GHLPropertyNamesOfObject(model);
                GHLLog(@"直播画中画探针：在 %@ 上找到模型 %@（键 %@），属性 %lu 个：%@", vcName, modelClass, key, (unsigned long)props.count, props.count > 0 ? [props componentsJoinedByString:@"、"] : @"无");
                GHLProbeStreamURLOnModel(model, [NSString stringWithFormat:@"%@.%@", vcName, key], hits, hlsURLs, probedModels);
            } @catch (__unused NSException *exception) {
            }
        }
    }
    // 2) 当前视频模型也探一下（直播间里 feed 的 model 可能是直播 aweme）
    AWEAwemeModel *aweme = GHLCurrentAwemeModel();
    if (aweme) {
        GHLProbeStreamURLOnModel(aweme, @"当前视频模型", hits, hlsURLs, probedModels);
    }
    // 3) 命中汇总（按 URL 去重，只记栏位名＋长度＋前 60 字）
    NSMutableSet<NSString *> *seenURLs = [NSMutableSet set];
    for (NSDictionary *hit in hits) {
        NSString *url = hit[@"url"];
        if ([seenURLs containsObject:url]) continue;
        [seenURLs addObject:url];
        GHLLog(@"直播画中画探针：栏位 %@ 命中 %@（%@，长 %lu，前 60 字：%@）", hit[@"key"], hit[@"type"], hit[@"where"], (unsigned long)((NSString *)url).length, GHLTruncatedURLString(url));
    }
    if (hlsURLs.count > 0) {
        NSURL *hlsURL = [NSURL URLWithString:hlsURLs.firstObject];
        if (hlsURL) {
            GHLLog(@"直播画中画探针：HLS 地址已确认（%lu 条），画中画用第一条", (unsigned long)hlsURLs.count);
            return hlsURL;
        }
        GHLLog(@"直播画中画探针：找到疑似 HLS 地址但拼不成 NSURL（见上面栏位行）");
    }
    BOOL hasFLVOrRTMP = NO;
    for (NSDictionary *hit in hits) {
        if ([hit[@"type"] isEqualToString:@"FLV"] || [hit[@"type"] isEqualToString:@"RTMP"]) { hasFLVOrRTMP = YES; break; }
    }
    if (hasFLVOrRTMP) {
        GHLLog(@"直播画中画探针：只有 FLV/RTMP，没有 HLS，系统画中画做不了（AVPlayer 播不了 FLV/RTMP，不转封装）");
    } else {
        GHLLog(@"直播画中画探针：没找到任何拉流地址（模型/栏位见上面）");
    }
    return nil;
}

// 1.0.18：探针改后台线程跑——之前是主线程同步，KVC getter 万一耗时会堵 UI
// （皇上 22:44–22:45：画面冻住、声音继续、慢慢变卡）。
// 探针本体只读窗口/VC 树＋KVC，全部 try/catch；日志写盘本身就是异步队列，
// 所以后台线程记日志安全；完成回调回主线程。
static dispatch_queue_t GHLProbeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      queue = dispatch_queue_create("com.guhailong.douyin.liveprobe", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void GHLProbeLiveStreamURLAsync(void (^completion)(NSURL * _Nullable hlsURL)) {
    dispatch_async(GHLProbeQueue(), ^{
      NSURL *url = nil;
      @try {
          url = GHLProbeLiveStreamURL();
      } @catch (__unused NSException *exception) {
          GHLLog(@"直播画中画探针：后台跑探针时异常，按拿不到地址处理");
      }
      NSURL *foundURL = url;
      GHLRunOnMain(^{
        if (completion) completion(foundURL);
      });
    });
}

static void GHLCleanupFallbackPiPObserver(void) {
    if (ghlPiPFallbackObserving && ghlPiPFallbackItem) {
        @try {
            [ghlPiPFallbackItem removeObserver:[GHLPiPDelegate sharedDelegate] forKeyPath:@"status" context:&kGHLPiPFallbackKVOContext];
        } @catch (__unused NSException *exception) {
        }
        ghlPiPFallbackObserving = NO;
    }
}

static void GHLCleanupFallbackPiPPlayer(void) {
    GHLCleanupFallbackPiPObserver();
    if (ghlPiPFallbackPlayer) {
        [ghlPiPFallbackPlayer pause];
        GHLLog(@"兜底播放器：已停止");
    }
    ghlPiPFallbackPlayer = nil;
    ghlPiPFallbackItem = nil;
    ghlPiPFallbackStarted = NO;
    // 控制器和合成图层也一起清掉，别留一个死的控制器给复用路
    // （复用路只在 player/item 还在时才走，清掉后不会误用）。
    if (ghlPiPSyntheticLayer) [ghlPiPSyntheticLayer removeFromSuperlayer];
    ghlPiPSyntheticLayer = nil;
    ghlPiPController = nil;
}

// 合成图层挂到窗口里：1.0.20 改成正常可见尺寸（320×180，放在 feed 底部、底栏上方，
// 不挡操作）再启动——1.0.19 的 2×2 小宿主 11 次调用 0 回调，系统很可能要求图层真正可见
// （每次 start 系统都建了 hosted window，就是不显示、不回调）。这只是最可能的方向，
// 真机测了才算；宿主尺寸记进日志。
static void GHLAttachPiPLayerToHostView(AVPlayerLayer *layer) {
    if (!layer) return;
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (!ghlPiPLayerHostView) {
        ghlPiPLayerHostView = [[UIView alloc] init];
        ghlPiPLayerHostView.backgroundColor = [UIColor clearColor];
        ghlPiPLayerHostView.userInteractionEnabled = NO;
        GHLLog(@"画中画：宿主改成可见尺寸 320x180（放在 feed 底部、底栏上方）");
    }
    CGFloat hostW = 320;
    CGFloat hostH = 180;
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = window.safeAreaInsets.bottom;
    CGFloat tabBarH = 83; // 底栏大约 83pt（含 Home Indicator 区）；宿主贴在底栏上方
    CGFloat hostX = (window.bounds.size.width - hostW) / 2;
    CGFloat hostY = window.bounds.size.height - safeBottom - tabBarH - hostH - 8;
    if (hostY < 0) hostY = 0;
    ghlPiPLayerHostView.frame = CGRectMake(hostX, hostY, hostW, hostH);
    if (ghlPiPLayerHostView.window != window) [window addSubview:ghlPiPLayerHostView];
    [window bringSubviewToFront:ghlPiPLayerHostView];
    [layer removeFromSuperlayer];
    layer.frame = ghlPiPLayerHostView.bounds;
    [ghlPiPLayerHostView.layer addSublayer:layer];
}

// 1.0.21：画中画没出来时的兜底停播（共用）：兜底在、没回调、小窗没起来，就停掉并记原因。
// 调用点：3 秒看门狗、后台任务结束时、后台任务过期时——三处兜底，不只靠主线程定时器。
// （8.log 实锤：8 秒看门狗有时根本没跑——start 调得晚，看门狗排到后台任务结束后，
//  App 已挂起，主线程定时器不跑，兜底就一直响到会话结束。去重（第 7 项）修了重复建播放器
//  顶掉看门狗的那一半；任务结束时停修了看门狗排到任务结束后的那一半。）
static void GHLStopFallbackPlayerIfPiPNotStarted(NSString *reason) {
    if (!ghlPiPFallbackPlayer) return;
    if (ghlPiPStartCallbackReceived) return;
    if (ghlPiPController && ghlPiPController.pictureInPictureActive) return;
    GHLLog(@"画中画没出来，已停兜底播放器（%@）", reason);
    GHLCleanupFallbackPiPPlayer();
}

// 每次调 startPictureInPicture 后都记一下：3 秒后还没回调（didStart/失败都没来），
// 当系统没接上，停掉兜底播放器（复用路/KVO 路/超时路都走这里）。
// 1.0.21：8 秒改 3 秒——硬上限是「调 start 后 3 秒内没回调就必停」，别让没窗口的兜底多响 5 秒。
static void GHLWatchPiPStartTimeout(void) {
    __block AVPictureInPictureController *controller = ghlPiPController;
    __block AVPlayer *player = ghlPiPFallbackPlayer;
    __block CFAbsoluteTime startTime = ghlPiPLastStartTime;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (ghlPiPStartCallbackReceived) return;
      if (controller != ghlPiPController || player != ghlPiPFallbackPlayer) return; // 已换过一轮，不管
      if (startTime != ghlPiPLastStartTime) return;                                 // 又调了一次 start，后面的看门狗会处理
      GHLStopFallbackPlayerIfPiPNotStarted(@"调 start 后 3 秒没系统回调");
    });
}

// 调 startPictureInPicture 前统一记一笔（清回调标记＋记时间＋挂看门狗）。
static void GHLNotePiPStartAttempted(void) {
    ghlPiPStartCallbackReceived = NO;
    ghlPiPLastStartTime = CFAbsoluteTimeGetCurrent();
    GHLWatchPiPStartTimeout();
}

// 兜底启动：就绪后再 startPictureInPicture（KVO 监听 item.status）。
// 返回 YES 表示兜底已接手（正在等就绪或已启动），调用方不用再报“没找到播放的视频”。
// videoURL 由调用方取好（普通视频同步取，直播间后台探针取——见 GHLStartFallbackPiP）。
static BOOL GHLStartFallbackPiPWithURL(NSURL *videoURL, BOOL isLive) {
    if (!videoURL) {
        if (isLive) {
            GHLLog(@"画中画兜底：直播间拿不到 HLS 拉流地址，画中画开不了（原因见上面探针行）");
        } else {
            GHLLog(@"画中画兜底：当前视频拿不到播放地址，画中画开不了");
        }
        return NO;
    }
    // 同一个视频重复点：复用已建好的兜底播放器，直接播＋开画中画。
    if (ghlPiPFallbackPlayer && ghlPiPFallbackItem && ghlPiPFallbackItem.asset) {
        NSURL *existingURL = ((AVURLAsset *)ghlPiPFallbackItem.asset).URL;
        if (existingURL && [existingURL.absoluteString isEqualToString:videoURL.absoluteString]) {
            GHLLog(@"画中画兜底：复用已建好的自起播放器（从头播）");
            [ghlPiPFallbackPlayer play];
            if (ghlPiPController && !ghlPiPController.pictureInPictureActive) {
                [ghlPiPController startPictureInPicture];
                GHLNotePiPStartAttempted();
                GHLLog(@"画中画：已调用 startPictureInPicture（等系统回调）");
            }
            return YES;
        }
    }
    // 换视频：先清掉旧兜底（KVO 一定要先摘掉再放 item，否则野指针崩）。
    GHLCleanupFallbackPiPPlayer();
    if (isLive) {
        GHLLog(@"画中画兜底：直播画中画用 HLS 拉流地址自起播放器（从头播，接不上直播进度；拉流地址可能是短效签名，过期播不了；后台/锁屏/与原直播声音冲突待真机验证）");
    } else {
        GHLLog(@"画中画兜底：没找到系统播放器，用当前视频链接自起播放器（从头播，接不上进度；原视频声音可能同时响）");
    }
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    ghlPiPFallbackItem = item;
    ghlPiPFallbackPlayer = player;
    ghlPiPFallbackStarted = NO;
    // 1.0.21：记下建兜底时 App 是不是已在后台（WillResignActive 时 state 已是 Inactive）——
    // 就绪时若已回前台就不启动（见上面 KVO 分支）。
    ghlPiPFallbackCreatedWhileBackground = ([UIApplication sharedApplication].applicationState != UIApplicationStateActive);
    GHLPreparePiPAudioSession();
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    ghlPiPSyntheticLayer = layer;
    GHLAttachPiPLayerToHostView(layer); // 图层必须挂进窗口，系统才肯启动画中画（1.0.18 没挂，7 次没回调）
    @try {
        ghlPiPController = [[AVPictureInPictureController alloc] initWithPlayerLayer:layer];
        ghlPiPController.delegate = [GHLPiPDelegate sharedDelegate];
    } @catch (NSException *exception) {
        [DYYYUtils showToast:@"画中画启动失败"];
        GHLLog(@"画中画兜底启动失败：%@", exception.reason);
        GHLCleanupFallbackPiPPlayer();
        return NO;
    }
    // item 就绪后再 start：没就绪就直接调大概率失败（delegate 会记失败原因）。
    if (item.status == AVPlayerItemStatusReadyToPlay) {
        [player play];
        [ghlPiPController startPictureInPicture];
        GHLNotePiPStartAttempted();
        ghlPiPFallbackStarted = YES;
        GHLLog(@"画中画：已调用 startPictureInPicture（等系统回调）");
    } else if (item.status == AVPlayerItemStatusFailed) {
        GHLLog(@"画中画兜底：播放地址打不开：%@", item.error.localizedDescription ?: @"未知错误");
        [DYYYUtils showToast:@"画中画启动失败"];
        GHLCleanupFallbackPiPPlayer();
        return NO;
    } else {
        [item addObserver:[GHLPiPDelegate sharedDelegate] forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:&kGHLPiPFallbackKVOContext];
        ghlPiPFallbackObserving = YES;
        [player play];
        // 8 秒还没就绪也试一次（弱网时 item 可能一直卡在 Unknown；试了不行 delegate 会记失败）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          if (ghlPiPFallbackPlayer == player && !ghlPiPFallbackStarted && ghlPiPFallbackItem == item) {
              if (item.status == AVPlayerItemStatusReadyToPlay) return; // KVO 那边会处理
              // 1.0.21：同 KVO 分支——兜底是切后台建的、8 秒后已回前台就别启动，直接停掉。
              if (ghlPiPFallbackCreatedWhileBackground &&
                  [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                  GHLLog(@"画中画：兜底 8 秒未就绪且已回前台，不启动画中画，停掉兜底播放器");
                  GHLCleanupFallbackPiPPlayer();
                  return;
              }
              if (!ghlPiPController) return;
              GHLLog(@"画中画兜底：等播放器就绪超时，直接试一次 startPictureInPicture");
              [ghlPiPController startPictureInPicture];
              GHLNotePiPStartAttempted();
              ghlPiPFallbackStarted = YES;
              GHLLog(@"画中画：已调用 startPictureInPicture（等系统回调）");
          }
        });
    }
    return YES;
}

// 兜底入口：普通视频同步取 playURL；直播间走后台探针（1.0.18，5 秒超时）。
// 直播间返回 YES 表示已接手（正在等探针结果），调用方不用再报“没找到播放的视频”；
// 超时或拿不到地址时，回调里记一行＋弹一次提示，不无限制等。
static BOOL GHLStartFallbackPiP(void) {
    BOOL isLive = GHLIsInLiveRoom();
    if (!isLive) {
        return GHLStartFallbackPiPWithURL(GHLCurrentVideoPlayURL(), NO);
    }
    // 1.0.17：直播间先走直播分支（room model 的 HLS 拉流地址），不走普通视频的 playURL——
    // 直播间没有 video.playURL，普通路拿不到地址。
    __block BOOL probeFinished = NO;
    GHLProbeLiveStreamURLAsync(^(NSURL *hlsURL) {
      if (probeFinished) return; // 已超时处理过，迟来的结果不再动
      probeFinished = YES;
      if (!GHLStartFallbackPiPWithURL(hlsURL, YES)) {
          [DYYYUtils showToast:@"没找到播放的视频"];
      }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (probeFinished) return;
      probeFinished = YES;
      GHLLog(@"画中画兜底：直播探针超时（5 秒没回），按拿不到地址处理");
      [DYYYUtils showToast:@"没找到播放的视频"];
    });
    return YES;
}

void GHLStartPiP(void) {
    GHLStartPiPWithCaller(nil);
}

void GHLStartPiPWithCaller(NSString *caller) {
    GHLRunOnMain(^{
      GHLLog(@"画中画：触发（%@）", caller.length > 0 ? caller : @"未知");
      // 1.0.21：记下触发时 App 的状态——窗口还可见时调 start 才有意义，
      // 切后台后才调（窗口已不可见）是 0 回调的嫌疑之一；WillResignActive 时是“不活跃”。
      UIApplicationState appState = [UIApplication sharedApplication].applicationState;
      GHLLog(@"画中画：触发时 App 状态：%@", appState == UIApplicationStateActive ? @"前台" : (appState == UIApplicationStateInactive ? @"不活跃（正在切后台）" : @"后台"));
      // 1.0.17：查找日志加一行是否在直播间（直播的查找现场跟普通视频不一样）。
      GHLLog(@"画中画查找：是否在直播间：%@", GHLIsInLiveRoom() ? @"是" : @"否");
      if (![AVPictureInPictureController isPictureInPictureSupported]) {
          [DYYYUtils showToast:@"当前设备不支持画中画"];
          GHLLog(@"画中画：设备不支持");
          return;
      }
      if (ghlPiPController.pictureInPictureActive) {
          GHLLog(@"画中画：已经在画中画里了");
          return;
      }
      // 1.0.15：找播放器（A 路图层 → B 路控制器探针，详细日志见“画中画查找”）；
      // 有播放器没图层时，用播放器新建一个图层再建 PiP 控制器。
      AVPlayerLayer *realLayer = nil;
      AVPlayer *player = GHLFindPlayingAVPlayerForPiP(&realLayer);
      if (!player) {
          // 1.0.16：A/B/C 全空时走 D 路兜底（自起 AVPlayer），兜底也开不了才报没找到。
          if (GHLStartFallbackPiP()) return;
          [DYYYUtils showToast:@"没找到播放的视频"];
          GHLLog(@"画中画：没找到播放器（查找经过见上面“画中画查找”的日志）");
          return;
      }
      AVPlayerLayer *layer = realLayer;
      if (!layer) {
          layer = [AVPlayerLayer playerLayerWithPlayer:player];
          ghlPiPSyntheticLayer = layer;
          GHLAttachPiPLayerToHostView(layer); // 新建的图层也要挂进窗口，不然 start 调了也没回调
          GHLLog(@"画中画：没找到现成图层，用播放器新建了一个图层再建 PiP 控制器");
      }
      @try {
          GHLPreparePiPAudioSession();
          ghlPiPController = [[AVPictureInPictureController alloc] initWithPlayerLayer:layer];
          ghlPiPController.delegate = [GHLPiPDelegate sharedDelegate];
          [ghlPiPController startPictureInPicture];
          // 1.0.20：A／C 路以前调完 start 没记时间戳——切后台 3 秒重查拿旧时间一算，
          // 新 start 才 1 秒就被误杀（6.log 17:18:30 实锤）。三路统一记一笔。
          GHLNotePiPStartAttempted();
          // 只表示已调用，不是小窗真的出来了——真出来/失败看 delegate 回调。
          GHLLog(@"画中画：已调用 startPictureInPicture（等系统回调）");
      } @catch (NSException *exception) {
          [DYYYUtils showToast:@"画中画启动失败"];
          GHLLog(@"画中画启动失败：%@", exception.reason);
      }
    });
}

// 播放器控制器查找（画中画 B 路探针用）。
static void GHLFindPlayerViewControllersInVC(UIViewController *vc, NSMutableArray *out) {
    if (!vc) return;
    if ([vc isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] ||
        [vc isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] ||
        [vc isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
        [out addObject:vc];
    }
    for (UIViewController *child in vc.childViewControllers) {
        GHLFindPlayerViewControllersInVC(child, out);
    }
    if (vc.presentedViewController) GHLFindPlayerViewControllersInVC(vc.presentedViewController, out);
}

#pragma mark - (6) 一键清爽模式 / (12) 直播间净化（开关联动）

// 直播间净化涉及的上游隐藏键
static NSArray<NSString *> *GHLLiveHideKeys(void) {
    return @[
        @"DYYYHideLiveView", @"DYYYHideLiveRoomShareCompanion", @"DYYYHideLiveRoomMirroring",
        @"DYYYHideLiveRoomFullscreen", @"DYYYHideLiveRoomClose", @"DYYYHideLiveRoomClear",
        @"DYYYHideLivePopup", @"DYYYHideLivePlayground", @"DYYYHideLiveLikeAnimation",
        @"DYYYHideLiveHotMessage", @"DYYYHideLiveGoodsMsg", @"DYYYHideLiveGIF",
        @"DYYYHideLiveDiscovery", @"DYYYHideLiveDetail", @"DYYYHideLiveDanmaku",
        @"DYYYHideLiveCapsuleView", @"DYYYHideEnterLive", @"DYYYHideAvatarLive",
        @"DYYYHideTabLive", @"DYYYHideLiveDuration"
    ];
}

void GHLApplyLivePurification(BOOL on) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (on) {
        NSMutableDictionary *saved = [NSMutableDictionary dictionary];
        for (NSString *key in GHLLiveHideKeys()) {
            saved[key] = @([defaults boolForKey:key]);
            [defaults setBool:YES forKey:key];
        }
        [defaults setObject:saved forKey:@"GHLLivePurifySaved"];
        GHLLog(@"直播间净化：开，已全开 %lu 个直播间隐藏项", (unsigned long)GHLLiveHideKeys().count);
    } else {
        NSDictionary *saved = [defaults objectForKey:@"GHLLivePurifySaved"];
        if ([saved isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in GHLLiveHideKeys()) {
                NSNumber *value = saved[key];
                if (value) [defaults setBool:[value boolValue] forKey:key];
            }
            [defaults removeObjectForKey:@"GHLLivePurifySaved"];
        }
        GHLLog(@"直播间净化：关，已恢复之前的值");
    }
}

void GHLApplyCleanMode(BOOL on) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:on forKey:@"DYYYEnablePure"];
    if (on) {
        [defaults setBool:YES forKey:@"DYYYEnableFloatClearButton"];
        reloadClearButtonConfiguration();
        GHLLog(@"一键清爽：开（首页净化+清屏按钮）");
    } else {
        GHLLog(@"一键清爽：关（首页净化已关）");
    }
}

#pragma mark - 解析接口（复用 DYYY 的接口格式：apiKey + 分享链接）

static void GHLFetchParseJSONForShareLink(NSString *shareLink, void (^completion)(NSDictionary *dataDict)) {
    NSString *apiKey = GHLGetString(@"DYYYInterfaceDownload");
    if (shareLink.length == 0 || apiKey.length == 0) {
        GHLRunOnMain(^{
          [DYYYUtils showToast:@"请先在设置里填解析接口 Key"];
        });
        GHLLog(@"解析接口：分享链接或 API Key 为空");
        if (completion) completion(nil);
        return;
    }
    NSString *apiUrl = [NSString stringWithFormat:@"%@%@", apiKey, [shareLink stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSURL *url = [NSURL URLWithString:apiUrl];
    if (!url) {
        if (completion) completion(nil);
        return;
    }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                               if (error || !data) {
                                                                   GHLLog(@"解析接口请求失败：%@", error.localizedDescription);
                                                                   if (completion) completion(nil);
                                                                   return;
                                                               }
                                                               NSError *jsonError = nil;
                                                               NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                                                               if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
                                                                   GHLLog(@"解析接口返回数据解析失败");
                                                                   if (completion) completion(nil);
                                                                   return;
                                                               }
                                                               NSInteger code = [json[@"code"] integerValue];
                                                               if (code != 0 && code != 200) {
                                                                   GHLLog(@"解析接口返回错误：%@", json[@"msg"] ?: @"未知错误");
                                                                   if (completion) completion(nil);
                                                                   return;
                                                               }
                                                               if (completion) completion(json[@"data"]);
                                                             }];
    [task resume];
}

// 从解析结果里取最清晰的一条视频直链
static NSString *GHLBestVideoURLFromParseData(NSDictionary *dataDict) {
    if (![dataDict isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *videoList = dataDict[@"video_list"];
    if ([videoList isKindOfClass:[NSArray class]] && videoList.count > 0) {
        id first = videoList[0];
        if ([first isKindOfClass:[NSDictionary class]] && [first[@"url"] length] > 0) return first[@"url"];
    }
    NSArray *videos = dataDict[@"videos"];
    if ([videos isKindOfClass:[NSArray class]] && videos.count > 0 && [videos[0] length] > 0) return videos[0];
    if ([dataDict[@"video_url"] length] > 0) return dataDict[@"video_url"];
    if ([dataDict[@"url"] length] > 0) return dataDict[@"url"];
    return nil;
}

#pragma mark - (18) 去水印分享直链

void GHLCopyNoWatermarkLinkForAwemeModel(AWEAwemeModel *model) {
    if (!model) return;
    NSString *shareLink = model.shareURL;
    if (shareLink.length == 0) {
        [DYYYUtils showToast:@"无法获取分享链接"];
        return;
    }
    [DYYYUtils showToast:@"正在解析无水印链接…"];
    GHLFetchParseJSONForShareLink(shareLink, ^(NSDictionary *dataDict) {
      GHLRunOnMain(^{
        NSString *bestURL = GHLBestVideoURLFromParseData(dataDict);
        if (!bestURL) {
            [DYYYUtils showToast:@"解析失败，换个接口 Key 试试"];
            return;
        }
        [[UIPasteboard generalPasteboard] setString:bestURL];
        [DYYYUtils showToast:@"无水印链接已复制"];
        GHLLog(@"去水印直链：已复制 %@", bestURL);
      });
    });
}

#pragma mark - (25) 视频截图去水印

void GHLSaveCleanScreenshotForAwemeModel(AWEAwemeModel *model, double seconds) {
    if (!model) return;
    NSString *shareLink = model.shareURL;
    if (shareLink.length == 0) {
        [DYYYUtils showToast:@"无法获取分享链接，干净截图失败"];
        return;
    }
    [DYYYUtils showToast:@"正在取无水印画面…"];
    GHLFetchParseJSONForShareLink(shareLink, ^(NSDictionary *dataDict) {
      NSString *bestURL = GHLBestVideoURLFromParseData(dataDict);
      if (!bestURL) {
          GHLRunOnMain(^{
            [DYYYUtils showToast:@"解析失败，干净截图没存成"];
          });
          return;
      }
      NSURL *videoURL = [NSURL URLWithString:bestURL];
      NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:videoURL
                                                                       completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                                                                         if (error || !location) {
                                                                             GHLLog(@"干净截图：视频下载失败 %@", error.localizedDescription);
                                                                             return;
                                                                         }
                                                                         AVURLAsset *asset = [AVURLAsset URLAssetWithURL:location options:nil];
                                                                         AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                                                                         generator.appliesPreferredTrackTransform = YES;
                                                                         generator.requestedTimeToleranceBefore = kCMTimeZero;
                                                                         generator.requestedTimeToleranceAfter = kCMTimeZero;
                                                                         NSError *imageError = nil;
                                                                         CMTime time = CMTimeMakeWithSeconds(seconds > 0 ? seconds : 0, NSEC_PER_SEC);
                                                                         CGImageRef imageRef = [generator copyCGImageAtTime:time actualTime:NULL error:&imageError];
                                                                         if (!imageRef) {
                                                                             GHLLog(@"干净截图：取帧失败 %@", imageError.localizedDescription);
                                                                             return;
                                                                         }
                                                                         UIImage *image = [UIImage imageWithCGImage:imageRef];
                                                                         CGImageRelease(imageRef);
                                                                         GHLRunOnMain(^{
                                                                           UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
                                                                           [DYYYUtils showToast:@"干净截图已存到相册"];
                                                                           GHLLog(@"干净截图：已存相册（%.1fs 处）", seconds);
                                                                         });
                                                                       }];
      [task resume];
    });
}

#pragma mark - 1.0.23：长按面板新增（清单 9 号，按抖音图层的做法）

// statistics 上只有 diggCount 有声明，其余计数（评论/分享/播放/收藏）运行时对象上
// 一般都有，用 KVC 探一下，拿不到就显示“—”，不崩、不瞎编。
static NSString *GHLNumberStringFromProbe(id object, NSString *key) {
    if (!object || key.length == 0) return @"—";
    @try {
        id value = [object valueForKey:key];
        if ([value isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%@", value];
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) return value;
    } @catch (__unused NSException *exception) {
    }
    return @"—";
}

// 获取作品数据：弹窗显示作者/文案/各数，并复制一份到剪贴板。
void GHLShowAwemeDataForAwemeModel(AWEAwemeModel *model) {
    if (!model) {
        [DYYYUtils showToast:@"拿不到作品信息"];
        return;
    }
    NSString *desc = model.descriptionString ?: @"";
    if (desc.length > 100) desc = [[desc substringToIndex:100] stringByAppendingString:@"…"];
    NSString *createTimeText = @"—";
    if (model.createTime) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[model.createTime doubleValue]];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
        createTimeText = [formatter stringFromDate:date];
    }
    id stats = model.statistics;
    NSString *text = [NSString stringWithFormat:
        @"作者：%@（%@）\n视频 ID：%@\n发布时间：%@\n时长：%.1f 秒\n点赞：%@　评论：%@\n分享：%@　播放：%@\n收藏：%@　是否广告：%@\n图集：%@ 张\n文案：%@",
        model.author.nickname ?: @"—", model.author.shortID ?: @"—",
        model.itemID ?: @"—", createTimeText, model.videoDuration,
        GHLNumberStringFromProbe(stats, @"diggCount"),
        GHLNumberStringFromProbe(stats, @"commentCount"),
        GHLNumberStringFromProbe(stats, @"shareCount"),
        GHLNumberStringFromProbe(stats, @"playCount"),
        GHLNumberStringFromProbe(stats, @"collectCount"),
        model.isAds ? @"是" : @"否",
        @(model.albumImages.count),
        desc.length > 0 ? desc : @"（无文案）"];
    [[UIPasteboard generalPasteboard] setString:text];
    [DYYYUtils showToast:@"作品数据已复制"];
    [DYYYBottomAlertView showAlertWithTitle:@"作品数据"
                                    message:text
                                  avatarURL:nil
                           cancelButtonText:@"关闭"
                          confirmButtonText:@"知道了"
                               cancelAction:nil
                                closeAction:nil
                              confirmAction:nil];
    GHLLog(@"获取作品数据：已显示（%@）", model.itemID ?: @"?");
}

// 图片预览：图集才有；把每张图的原图地址翻出来，全屏左右翻页看，点一下关闭。
void GHLPreviewAwemeImagesForAwemeModel(AWEAwemeModel *model) {
    if (!model || model.albumImages.count == 0) {
        [DYYYUtils showToast:@"这条不是图集，没有图片可预览"];
        GHLLog(@"图片预览：不是图集（albumImages 为空）");
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (AWEImageAlbumImageModel *imageModel in model.albumImages) {
        NSArray *urlList = imageModel.urlList;
        if ([urlList isKindOfClass:[NSArray class]] && urlList.count > 0 &&
            [urlList.firstObject isKindOfClass:[NSString class]]) {
            NSURL *url = [NSURL URLWithString:urlList.firstObject];
            if (url) [urls addObject:url];
        }
    }
    if (urls.count == 0) {
        [DYYYUtils showToast:@"拿不到图片地址"];
        GHLLog(@"图片预览：图集有 %lu 项但一张地址都拿不到", (unsigned long)model.albumImages.count);
        return;
    }
    GHLImagePreviewViewController *previewVC = [[GHLImagePreviewViewController alloc] initWithImageURLs:urls];
    previewVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [GHLTopViewController() presentViewController:previewVC animated:YES completion:nil];
    GHLLog(@"图片预览：已打开（%lu 张）", (unsigned long)urls.count);
}

#pragma mark - (30) 视频原声提取

void GHLExtractOriginalAudioForAwemeModel(AWEAwemeModel *model) {
    if (!model || !model.video) return;
    NSURL *videoURL = nil;
    if (model.video.h264URL && model.video.h264URL.originURLList.count > 0) {
        videoURL = [NSURL URLWithString:model.video.h264URL.originURLList.firstObject];
    } else if (model.video.playURL && model.video.playURL.originURLList.count > 0) {
        videoURL = [NSURL URLWithString:model.video.playURL.originURLList.firstObject];
    }
    if (!videoURL) {
        [DYYYUtils showToast:@"拿不到视频地址，提不出来"];
        return;
    }
    [DYYYUtils showToast:@"正在下载视频并提取原声…"];
    [DYYYManager downloadMediaWithProgress:videoURL
                                 mediaType:MediaTypeVideo
                                     audio:nil
                                  progress:nil
                                completion:^(BOOL success, NSURL *fileURL) {
                                  if (!success || !fileURL) {
                                      GHLRunOnMain(^{
                                        [DYYYUtils showToast:@"视频下载失败，原声没提出来"];
                                      });
                                      GHLLog(@"原声提取：视频下载失败");
                                      return;
                                  }
                                  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
                                  if (![[asset tracksWithMediaType:AVMediaTypeAudio] count]) {
                                      GHLRunOnMain(^{
                                        [DYYYUtils showToast:@"这个视频没有音轨"];
                                      });
                                      GHLLog(@"原声提取：视频没有音轨");
                                      return;
                                  }
                                  AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
                                  if (!exportSession) {
                                      GHLLog(@"原声提取：建导出会话失败");
                                      return;
                                  }
                                  NSString *outputName = [NSString stringWithFormat:@"ghl_audio_%@.m4a", [[NSUUID UUID] UUIDString]];
                                  NSURL *outputURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:outputName];
                                  exportSession.outputURL = outputURL;
                                  exportSession.outputFileType = AVFileTypeAppleM4A;
                                  [exportSession exportAsynchronouslyWithCompletionHandler:^{
                                    if (exportSession.status != AVAssetExportSessionStatusCompleted) {
                                        GHLLog(@"原声提取：导出失败 %@", exportSession.error.localizedDescription);
                                        GHLRunOnMain(^{
                                          [DYYYUtils showToast:@"原声导出失败"];
                                        });
                                        return;
                                    }
                                    GHLRunOnMain(^{
                                      UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ outputURL ] applicationActivities:nil];
                                      UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                                      [rootVC presentViewController:activityVC animated:YES completion:nil];
                                      [DYYYUtils showToast:@"原声已提出来，选个地方存"];
                                      GHLLog(@"原声提取：完成 %@", outputURL.lastPathComponent);
                                    });
                                  }];
                                }];
}

#pragma mark - (24) 私信防撤回（探针）

void GHLProbeAntiRecall(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name containsString:@"Recall"] || [name containsString:@"Revoke"] || [name containsString:@"Withdraw"]) {
            [hits addObject:name];
            if (hits.count >= 50) break;
        }
    }
    free(classes);
    GHLLog(@"私信防撤回探针：疑似撤回相关类 %lu 个：%@", (unsigned long)hits.count, hits);
    if (hits.count == 0) {
        GHLLog(@"私信防撤回探针：没找到撤回相关的类，功能待真机进一步验证，开关目前只做记录");
    }
}

#pragma mark - 手势：双击快进 / 三指双击清屏 / 边缘滑动切视频

// 1.0.8 双击爱心探针：双击后 0.35 秒扫一遍互动层，记下可能是爱心动画的视图。
// 背景：双击爱心是抖音 %orig 里弹出来的，AwemeHeaders 里没有爱心动画类，
// 代码无法断定它是 Lottie 还是 UIImageView——先靠真机日志认类，再决定能不能换。
static void GHLCollectHeartProbeCandidatesInView(UIView *view, NSMutableArray<NSString *> *out, NSInteger depth) {
    if (!view || depth > 5 || out.count >= 10) return;
    NSString *className = NSStringFromClass(view.class);
    BOOL isLottie = [className isEqualToString:@"LOTAnimationView"];
    BOOL isBigImage = [view isKindOfClass:[UIImageView class]] && CGRectGetWidth(view.bounds) >= 60 && CGRectGetHeight(view.bounds) >= 60;
    if (isLottie || isBigImage) {
        NSString *extra = @"";
        if (isLottie) {
            @try {
                id animation = [view valueForKey:@"animation"];
                if (animation) {
                    NSString *name = nil;
                    @try { name = [animation valueForKey:@"name"]; } @catch (__unused NSException *e) { }
                    if (!name) { @try { name = [animation valueForKey:@"animationName"]; } @catch (__unused NSException *e2) { } }
                    if (name.length > 0) extra = [NSString stringWithFormat:@" 动画=%@", name];
                }
            } @catch (__unused NSException *e) { }
        }
        [out addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f 中心(%.0f,%.0f)%@", className, CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds), view.center.x, view.center.y, extra]];
    }
    for (UIView *subview in view.subviews) GHLCollectHeartProbeCandidatesInView(subview, out, depth + 1);
}

void GHLProbeDoubleTapHeartInView(UIView *view) {
    if (!view || !GHLGetBool(GHL_KEY_DOUBLE_TAP_HEART_PROBE)) return;
    __weak UIView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIView *strongView = weakView;
      if (!strongView || !strongView.window) return;
      NSMutableArray<NSString *> *found = [NSMutableArray array];
      GHLCollectHeartProbeCandidatesInView(strongView, found, 0);
      if (found.count > 0) {
          GHLLog(@"双击爱心探针：双击后 0.35 秒看到 %lu 个候选：%@", (unsigned long)found.count, [found componentsJoinedByString:@" | "]);
      } else {
          GHLLog(@"双击爱心探针：双击后 0.35 秒没看到 LOTAnimationView 或大图——爱心可能是更小的图或已播完消失");
      }
    });
}

static char kGHLGesturesInstalledKey;
static char kGHLSidebarOrderAppliedKey;

static void GHLHandleDoubleTapSeek(UITapGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    // (37) 双击下载开了就优先下载，不快进
    if (GHLGetBool(GHL_KEY_DOUBLE_TAP_DOWNLOAD)) {
        GHLDownloadCurrentVideoWithProgress();
        return;
    }
    if (!GHLGetBool(GHL_KEY_SEEK_GESTURES)) return;
    // 双击点赞没关时不抢手势，避免一点赞就快进
    if (!GHLGetBool(@"DYYYDisableDoubleTapLike")) return;
    CGPoint point = [gesture locationInView:gesture.view];
    CGFloat width = gesture.view.bounds.size.width;
    if (point.x < width / 3.0) {
        GHLSeekCurrentPlayerBySeconds(-10);
    } else if (point.x > width * 2.0 / 3.0) {
        GHLSeekCurrentPlayerBySeconds(10);
    }
}

static void GHLHandleTripleTapClear(UITapGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    if (!GHLGetBool(GHL_KEY_TRIPLE_TAP_CLEAR)) return;
    __block HideUIButton *clearButton = nil;
    GHLRunOnMain(^{
      UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
      NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
      while (stack.count > 0 && !clearButton) {
          UIView *view = stack.lastObject;
          [stack removeLastObject];
          if ([view isKindOfClass:NSClassFromString(@"HideUIButton")]) {
              clearButton = (HideUIButton *)view;
              break;
          }
          [stack addObjectsFromArray:view.subviews];
      }
    });
    if (clearButton) {
        [clearButton handleTap];
        GHLLog(@"三指双击清屏：已触发");
    } else {
        [DYYYUtils showToast:@"请先开启一键清屏悬浮按钮"];
    }
}

// 1.0.5 手势自定义：三击 / 双指双击 / 左滑 / 右滑，处理时读 live 设置（没配动作就是“默认”，直接返回）。
static void GHLHandleCustomTripleTap(UITapGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GHLPerformGestureAction(GHLGetString(GHL_KEY_GESTURE_TRIPLE_TAP));
}

static void GHLHandleTwoFingerDoubleTap(UITapGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GHLPerformGestureAction(GHLGetString(GHL_KEY_GESTURE_TWO_FINGER_DOUBLE_TAP));
}

static void GHLHandleSwipeLeft(UISwipeGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GHLPerformGestureAction(GHLGetString(GHL_KEY_GESTURE_SWIPE_LEFT));
}

static void GHLHandleSwipeRight(UISwipeGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GHLPerformGestureAction(GHLGetString(GHL_KEY_GESTURE_SWIPE_RIGHT));
}

// 切到下一个视频（找 Feed 列表，滚到下一行；边缘滑动和手势自定义共用）。
static void GHLScrollFeedToNextVideo(void) {
    GHLRunOnMain(^{
      @try {
          UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
          if (!window) return;
          NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
          UITableView *feedTable = nil;
          while (stack.count > 0 && !feedTable) {
              UIView *view = stack.lastObject;
              [stack removeLastObject];
              if ([view isKindOfClass:[UITableView class]] && [NSStringFromClass([view class]) containsString:@"Feed"]) {
                  feedTable = (UITableView *)view;
                  break;
              }
              [stack addObjectsFromArray:view.subviews];
          }
          if (!feedTable) {
              for (UIView *subview in window.subviews) {
                  if ([subview isKindOfClass:[UITableView class]]) {
                      feedTable = (UITableView *)subview;
                      break;
                  }
              }
          }
          if (!feedTable) {
              GHLLog(@"切下一个视频：没找到 Feed 列表");
              return;
          }
          NSArray<NSIndexPath *> *visible = [feedTable indexPathsForVisibleRows];
          if (!visible || visible.count == 0) return;
          NSIndexPath *last = visible.lastObject;
          NSInteger rows = [feedTable numberOfRowsInSection:last.section];
          if (last.row + 1 < rows) {
              NSIndexPath *next = [NSIndexPath indexPathForRow:last.row + 1 inSection:last.section];
              [feedTable scrollToRowAtIndexPath:next atScrollPosition:UITableViewScrollPositionTop animated:YES];
              GHLLog(@"切下一个视频：已切到下一个");
          }
      } @catch (__unused NSException *exception) {
      }
    });
}

static void GHLHandleEdgeSwipeNext(UIScreenEdgePanGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    if (!GHLGetBool(GHL_KEY_EDGE_SWIPE_NEXT)) return;
    GHLScrollFeedToNextVideo();
}

static void GHLInstallFeedGesturesOnView(UIView *view) {
    if (!view) return;
    if (objc_getAssociatedObject(view, &kGHLGesturesInstalledKey)) return;
    objc_setAssociatedObject(view, &kGHLGesturesInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleDoubleTapSeek:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleTripleTapClear:)];
    tripleTap.numberOfTapsRequired = 2;
    tripleTap.numberOfTouchesRequired = 3;
    tripleTap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:tripleTap];

    UIScreenEdgePanGestureRecognizer *edgeSwipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleEdgeSwipeNext:)];
    edgeSwipe.edges = UIRectEdgeRight;
    [view addGestureRecognizer:edgeSwipe];

    UIScreenEdgePanGestureRecognizer *leftSwipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleLeftSwipeBack:)];
    leftSwipe.edges = UIRectEdgeLeft;
    [view addGestureRecognizer:leftSwipe];

    // 1.0.5 手势自定义：三击、双指双击、左滑、右滑。
    // 三击：只在配了动作时装（不配就不装，双击点赞一点都不拖慢）；装了以后，让这个视频页里
    // 已有的双击识别器（自己的 + 抖音原生的）等三击失败再认，否则三击会先触发点赞/快进。
    // 三击改完切个视频生效（每个视频的视图装一次）；另外三个处理时读 live 设置，改完立即生效。
    NSString *tripleTapAction = GHLGetString(GHL_KEY_GESTURE_TRIPLE_TAP);
    if (tripleTapAction.length > 0 && ![tripleTapAction isEqualToString:GHL_FLOAT_ACTION_DEFAULT]) {
        UITapGestureRecognizer *customTripleTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleCustomTripleTap:)];
        customTripleTap.numberOfTapsRequired = 3;
        customTripleTap.numberOfTouchesRequired = 1;
        customTripleTap.cancelsTouchesInView = NO;
        [view addGestureRecognizer:customTripleTap];
        // 这个视频页（view + 父视图，即当前视频 cell）里的双击识别器等三击失败。
        NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
        if (view.superview) [stack addObject:view.superview];
        while (stack.count > 0) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIGestureRecognizer *gr in v.gestureRecognizers ?: @[]) {
                if (gr == customTripleTap) continue;
                if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
                    UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
                    if (tap.numberOfTapsRequired == 2 && tap.numberOfTouchesRequired == 1) {
                        [tap requireGestureRecognizerToFail:customTripleTap];
                    }
                }
            }
            [stack addObjectsFromArray:v.subviews];
        }
    }

    // 双指双击：抖音没有双指点按，不跟任何手势打架；常驻，处理时读 live 设置。
    UITapGestureRecognizer *twoFingerDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleTwoFingerDoubleTap:)];
    twoFingerDoubleTap.numberOfTapsRequired = 2;
    twoFingerDoubleTap.numberOfTouchesRequired = 2;
    twoFingerDoubleTap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:twoFingerDoubleTap];

    // 左滑 / 右滑：Feed 是竖滑列表，视频区没有横滑手势；cancelsTouchesInView=NO，竖滑照常。
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleSwipeLeft:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.cancelsTouchesInView = NO;
    [view addGestureRecognizer:swipeLeft];
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleSwipeRight:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.cancelsTouchesInView = NO;
    [view addGestureRecognizer:swipeRight];
}

static void GHLHandleLeftSwipeBack(UIScreenEdgePanGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    if (!GHLGetBool(GHL_KEY_LEFT_SWIPE_BACK)) return;
    GHLRunOnMain(^{
      UIViewController *topVC = GHLTopViewController();
      if (topVC.navigationController && topVC.navigationController.viewControllers.count > 1) {
          [topVC.navigationController popViewControllerAnimated:YES];
          GHLLog(@"左滑返回：已返回上一页");
      } else if (topVC.presentedViewController) {
          [topVC dismissViewControllerAnimated:YES completion:nil];
          GHLLog(@"左滑返回：已关闭当前页");
      }
    });
}

#pragma mark - (22) 侧边栏自定义排序

static void GHLApplySidebarOrderInView(UIView *view) {
    if (!GHLGetBool(GHL_KEY_SIDEBAR_REORDER)) return;
    NSString *orderString = GHLGetString(GHL_KEY_SIDEBAR_ORDER);
    if (orderString.length == 0) return;
    NSArray<NSString *> *desiredOrder = [orderString componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *cleanOrder = [NSMutableArray array];
    for (NSString *item in desiredOrder) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [cleanOrder addObject:trimmed];
    }
    if (cleanOrder.count < 2) return;

    // 找到装着点赞/评论/分享/收藏按钮的容器
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count > 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        NSMutableArray *buttons = [NSMutableArray array];
        for (UIView *subview in candidate.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")]) [buttons addObject:subview];
        }
        if (buttons.count >= 2) {
            // 当前从上到下的标签顺序
            NSArray *sortedNow = [buttons sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
              if (a.center.y < b.center.y) return NSOrderedAscending;
              if (a.center.y > b.center.y) return NSOrderedDescending;
              return NSOrderedSame;
            }];
            NSMutableArray<NSString *> *currentLabels = [NSMutableArray array];
            for (AWEFeedVideoButton *button in sortedNow) {
                [currentLabels addObject:button.accessibilityLabel ?: @""];
            }
            // 期望顺序：列表里的按给定排，没列出的保持原相对顺序缀在后面
            NSMutableArray<NSString *> *targetLabels = [NSMutableArray array];
            for (NSString *label in cleanOrder) {
                if ([currentLabels containsObject:label]) [targetLabels addObject:label];
            }
            for (NSString *label in currentLabels) {
                if (![targetLabels containsObject:label]) [targetLabels addObject:label];
            }
            if ([targetLabels isEqualToArray:currentLabels]) return;
            // 按目标顺序分配现在的 y 位置
            NSMutableArray<NSNumber *> *slots = [NSMutableArray array];
            for (UIView *button in sortedNow) [slots addObject:@(button.center.y)];
            NSMutableDictionary<NSString *, AWEFeedVideoButton *> *byLabel = [NSMutableDictionary dictionary];
            for (AWEFeedVideoButton *button in buttons) {
                if (button.accessibilityLabel.length > 0) byLabel[button.accessibilityLabel] = button;
            }
            for (NSUInteger i = 0; i < targetLabels.count && i < slots.count; i++) {
                AWEFeedVideoButton *button = byLabel[targetLabels[i]];
                if (!button) continue;
                CGPoint center = button.center;
                center.y = [slots[i] floatValue];
                button.center = center;
            }
            GHLLog(@"侧边栏排序：已按 %@ 排列", [targetLabels componentsJoinedByString:@","]);
            return;
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
}

#pragma mark - (44) 1.0.8 美化：主题预设

// 主题预设一次写好现有颜色类 key（只写真实存在的 key，不编造；选完仍可在各行单独微调）。
void GHLApplyThemePreset(NSString *preset) {
    if (!preset || [preset isEqualToString:@"无"]) return;
    NSDictionary<NSString *, NSString *> *values = nil;
    if ([preset isEqualToString:@"金龙"]) {
        values = @{@"DYYYVideoBGColor" : @"000000", @"DYYYDanmuColor" : @"FFD700", @"DYYYProgressLabelColor" : @"D4AF37", @"DYYYLabelColor" : @"D4AF37", GHL_KEY_PROGRESS_BAR_COLOR : @"D4AF37"};
    } else if ([preset isEqualToString:@"冰蓝"]) {
        values = @{@"DYYYVideoBGColor" : @"0A1628", @"DYYYDanmuColor" : @"7DD3FC", @"DYYYProgressLabelColor" : @"7DD3FC", @"DYYYLabelColor" : @"BAE6FD", GHL_KEY_PROGRESS_BAR_COLOR : @"38BDF8"};
    } else if ([preset isEqualToString:@"樱粉"]) {
        values = @{@"DYYYVideoBGColor" : @"1F0A14", @"DYYYDanmuColor" : @"FDA4AF", @"DYYYProgressLabelColor" : @"FDA4AF", @"DYYYLabelColor" : @"FBCFE8", GHL_KEY_PROGRESS_BAR_COLOR : @"F472B6"};
    } else if ([preset isEqualToString:@"暗夜"]) {
        values = @{@"DYYYVideoBGColor" : @"000000", @"DYYYDanmuColor" : @"E5E7EB", @"DYYYProgressLabelColor" : @"9CA3AF", @"DYYYLabelColor" : @"9CA3AF", GHL_KEY_PROGRESS_BAR_COLOR : @"6B7280"};
    }
    if (!values) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in values) [defaults setObject:values[key] forKey:key];
    [defaults synchronize];
    GHLLog(@"主题预设：已应用 %@ 主题", preset);
}

#pragma mark - (44) 1.0.8 美化：右侧边栏（图标缩放 / 间距 / 圆角底）

static char kGHLSidebarPillViewKey;
static char kGHLSidebarBaselinePitchKey;
static char kGHLSidebarBaselineCountKey;

// 在 interaction 层里找装着 AWEFeedVideoButton 的容器（跟排序函数同一套找法）。
static UIView *GHLFindSidebarButtonContainer(UIView *view, NSMutableArray<AWEFeedVideoButton *> *outButtons) {
    if (!view) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count > 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        NSMutableArray *buttons = [NSMutableArray array];
        for (UIView *subview in candidate.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")]) [buttons addObject:subview];
        }
        if (buttons.count >= 2) {
            if (outButtons) [outButtons addObjectsFromArray:buttons];
            return candidate;
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

void GHLApplySidebarBeautifyInView(UIView *view) {
    if (!view || !GHLGetBool(GHL_KEY_SIDEBAR_BEAUTIFY)) return;
    if (![NSThread isMainThread]) return;
    NSMutableArray<AWEFeedVideoButton *> *buttons = [NSMutableArray array];
    UIView *container = GHLFindSidebarButtonContainer(view, buttons);
    if (!container || buttons.count < 2) return;

    // 图标缩放：只动 imageView 的 transform，不动按钮 frame，点按区域不变。
    NSString *scaleString = GHLGetString(GHL_KEY_SIDEBAR_ICON_SCALE);
    CGFloat scale = scaleString.length > 0 ? [scaleString floatValue] : 1.0;
    if (scale < 0.5) scale = 0.5;
    if (scale > 1.5) scale = 1.5;
    BOOL pillOn = GHLGetBool(GHL_KEY_SIDEBAR_PILL_BG);
    for (AWEFeedVideoButton *button in buttons) {
        UIImageView *iconView = button.imageView;
        if (iconView) {
            iconView.transform = (fabs(scale - 1.0) > 0.01) ? CGAffineTransformMakeScale(scale, scale) : CGAffineTransformIdentity;
        }
        // 圆角底：每颗图标下面垫一块半透明圆角底，只包图标不包数字标签，不拦截触摸。
        UIView *pill = objc_getAssociatedObject(button, &kGHLSidebarPillViewKey);
        if (pillOn && iconView) {
            if (!pill) {
                pill = [[UIView alloc] init];
                pill.userInteractionEnabled = NO;
                pill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
                objc_setAssociatedObject(button, &kGHLSidebarPillViewKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [button insertSubview:pill atIndex:0];
            }
            CGRect iconFrame = iconView.frame;
            CGFloat pad = 8.0;
            CGFloat pillHeight = CGRectGetHeight(iconFrame) + pad * 2;
            pill.frame = CGRectMake(CGRectGetMidX(iconFrame) - pillHeight / 2, CGRectGetMidY(iconFrame) - pillHeight / 2, pillHeight, pillHeight);
            pill.layer.cornerRadius = pillHeight / 2;
            pill.hidden = NO;
        } else if (pill) {
            pill.hidden = YES;
        }
    }

    // 间距：用首次看到的自然 pitch 作基准（只在美化第一次跑时记录，之后一直沿用），
    // 每次按 基准 + 设定间距 重排，不会在多次 layout 里越加越大。
    NSString *spacingString = GHLGetString(GHL_KEY_SIDEBAR_SPACING);
    CGFloat spacing = spacingString.length > 0 ? [spacingString floatValue] : 0.0;
    if (spacing < -30) spacing = -30;
    if (spacing > 60) spacing = 60;
    if (fabs(spacing) < 0.01) return;
    NSArray *sorted = [buttons sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
      if (a.center.y < b.center.y) return NSOrderedAscending;
      if (a.center.y > b.center.y) return NSOrderedDescending;
      return NSOrderedSame;
    }];
    NSNumber *baselinePitch = objc_getAssociatedObject(container, &kGHLSidebarBaselinePitchKey);
    NSNumber *baselineCount = objc_getAssociatedObject(container, &kGHLSidebarBaselineCountKey);
    if (!baselinePitch || !baselineCount || [baselineCount integerValue] != (NSInteger)buttons.count) {
        // 只在当前这组按钮还没基准时记录；此时位置是抖音原生排布（美化之前没动过它们）。
        CGFloat totalGap = 0;
        for (NSUInteger i = 1; i < sorted.count; i++) totalGap += ([sorted[i] center].y - [sorted[i - 1] center].y);
        CGFloat pitch = (sorted.count > 1) ? totalGap / (sorted.count - 1) : 0;
        if (pitch <= 0) return;
        objc_setAssociatedObject(container, &kGHLSidebarBaselinePitchKey, @(pitch), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(container, &kGHLSidebarBaselineCountKey, @(buttons.count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        baselinePitch = @(pitch);
    }
    CGFloat pitch = [baselinePitch floatValue] + spacing;
    if (pitch < 20) pitch = 20;
    CGFloat y = [sorted[0] center].y;
    for (NSUInteger i = 0; i < sorted.count; i++) {
        UIView *button = sorted[i];
        CGPoint center = button.center;
        center.y = y;
        button.center = center;
        y += pitch;
    }
}

#pragma mark - (7)(29) 评论区：关键词屏蔽 + 自动展开

static BOOL GHLCommentFilterActive(void) {
    if (!GHLGetBool(GHL_KEY_COMMENT_AUTO_EXPAND) && ![GHLGetString(GHL_KEY_COMMENT_BLOCK_KEYWORDS) length]) return NO;
    return YES;
}

static NSArray<NSString *> *GHLCommentBlockKeywords(void) {
    NSString *raw = GHLGetString(GHL_KEY_COMMENT_BLOCK_KEYWORDS);
    if (raw.length == 0) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *item in [raw componentsSeparatedByString:@","]) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [out addObject:trimmed];
    }
    return out;
}

static void GHLCollectLabelsInView(UIView *view, NSMutableArray<UILabel *> *out) {
    if ([view isKindOfClass:[UILabel class]]) [out addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) GHLCollectLabelsInView(subview, out);
}

static void GHLCollectButtonsInView(UIView *view, NSMutableArray<UIButton *> *out) {
    if ([view isKindOfClass:[UIButton class]]) [out addObject:(UIButton *)view];
    for (UIView *subview in view.subviews) GHLCollectButtonsInView(subview, out);
}

static char kGHLExpandTappedKey;

// 在评论面板里：屏蔽含关键词的评论格、点一遍展开按钮
static void GHLProcessVisibleCommentCells(UITableView *tableView) {
    if (!tableView) return;
    NSArray<NSString *> *blockKeywords = GHLCommentBlockKeywords();
    BOOL autoExpand = GHLGetBool(GHL_KEY_COMMENT_AUTO_EXPAND);
    BOOL expandReplies = GHLGetBool(GHL_KEY_EXPAND_REPLIES);
    for (UITableViewCell *cell in tableView.visibleCells) {
        @try {
            if (blockKeywords.count > 0) {
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                GHLCollectLabelsInView(cell.contentView, labels);
                BOOL blocked = NO;
                for (UILabel *label in labels) {
                    for (NSString *keyword in blockKeywords) {
                        if (label.text.length > 0 && [label.text containsString:keyword]) {
                            blocked = YES;
                            break;
                        }
                    }
                    if (blocked) break;
                }
                cell.hidden = blocked;
                if (blocked) GHLLog(@"评论屏蔽：已藏一条含关键词的评论");
            }
            if (autoExpand || expandReplies) {
                NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
                GHLCollectButtonsInView(cell.contentView, buttons);
                for (UIButton *button in buttons) {
                    if (objc_getAssociatedObject(button, &kGHLExpandTappedKey)) continue;
                    NSString *title = button.titleLabel.text ?: @"";
                    BOOL isFullText = autoExpand && ([title containsString:@"全文"] || [title containsString:@"展开"]);
                    BOOL isReplyExpand = expandReplies && ([title containsString:@"条回复"] || [title containsString:@"展开"]);
                    if (isFullText || isReplyExpand) {
                        objc_setAssociatedObject(button, &kGHLExpandTappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                        GHLLog(@"评论展开：已点“%@”", title);
                    }
                }
            }
        } @catch (__unused NSException *exception) {
        }
    }
}

static NSTimer *ghlCommentTimer = nil;

static void GHLStartCommentProcessing(UIViewController *containerVC) {
    [ghlCommentTimer invalidate];
    ghlCommentTimer = nil;
    if (!GHLCommentFilterActive() && !GHLGetBool(GHL_KEY_EXPAND_REPLIES)) return;
    __weak UIViewController *weakVC = containerVC;
    ghlCommentTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                      repeats:YES
                                                        block:^(NSTimer *timer) {
                                                          UIViewController *vc = weakVC;
                                                          if (!vc || !vc.view.window) {
                                                              [timer invalidate];
                                                              ghlCommentTimer = nil;
                                                              return;
                                                          }
                                                          NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
                                                          while (stack.count > 0) {
                                                              UIView *view = stack.lastObject;
                                                              [stack removeLastObject];
                                                              if ([view isKindOfClass:[UITableView class]]) {
                                                                  GHLProcessVisibleCommentCells((UITableView *)view);
                                                                  return;
                                                              }
                                                              [stack addObjectsFromArray:view.subviews];
                                                          }
                                                        }];
}

static void GHLStopCommentProcessing(void) {
    [ghlCommentTimer invalidate];
    ghlCommentTimer = nil;
}

#pragma mark - (10) 音量键调进度

static double ghlLastVolume = -1;
static BOOL ghlRestoringVolume = NO;
static NSTimeInterval ghlLastVolumeEventTime = 0;

static void GHLHandleVolumeChange(NSNotification *note) {
    if (!GHLGetBool(GHL_KEY_VOLUME_SEEK)) return;
    if (ghlRestoringVolume) return;
    NSDictionary *info = note.userInfo;
    NSString *reason = info[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"];
    if (![reason isEqualToString:@"ExplicitVolumeChange"]) return; // 只响应实体按键
    NSNumber *volumeNumber = info[@"AVSystemController_AudioVolumeNotificationParameter"];
    if (!volumeNumber) return;
    double volume = [volumeNumber doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - ghlLastVolumeEventTime < 0.25) return; // 防抖
    ghlLastVolumeEventTime = now;
    if (ghlLastVolume < 0) {
        ghlLastVolume = volume;
        return;
    }
    double direction = 0;
    if (volume > ghlLastVolume + 0.01) direction = 10;
    else if (volume < ghlLastVolume - 0.01) direction = -10;
    double previousVolume = ghlLastVolume;
    ghlLastVolume = volume;
    if (direction == 0) return;
    GHLSeekCurrentPlayerBySeconds(direction);
    // 把系统音量拨回去，避免按一下音量变一下
    ghlRestoringVolume = YES;
    @try {
        [[objc_getClass("AVSystemController") sharedAVSystemController] setVolumeTo:(float)previousVolume forCategory:@"Audio/Video"];
    } @catch (__unused NSException *exception) {
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      ghlRestoringVolume = NO;
    });
}

#pragma mark - (25) 截图监听

static void GHLHandleScreenshotTaken(NSNotification *note) {
    if (!GHLGetBool(GHL_KEY_SCREENSHOT_CLEAN)) return;
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    if (!model) {
        GHLLog(@"截图去水印：没找到当前视频");
        return;
    }
    double seconds = GHLCurrentPlayerTime();
    GHLSaveCleanScreenshotForAwemeModel(model, seconds);
}

#pragma mark - GHLFeatures（手势回调的 target）


@implementation GHLFeatures

+ (void)ghl_handleDoubleTapSeek:(UITapGestureRecognizer *)gesture {
    GHLHandleDoubleTapSeek(gesture);
}

+ (void)ghl_handleTripleTapClear:(UITapGestureRecognizer *)gesture {
    GHLHandleTripleTapClear(gesture);
}

+ (void)ghl_handleEdgeSwipeNext:(UIScreenEdgePanGestureRecognizer *)gesture {
    GHLHandleEdgeSwipeNext(gesture);
}

+ (void)ghl_handleLeftSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    GHLHandleLeftSwipeBack(gesture);
}

// 1.0.23 第二批：70 双击消息快捷回复、73 长按头像续火花、75 AI 解析页签／开始解析。
// 实现在下面“1.0.23 第二批”一节，这里只做转发。
+ (void)ghl_handleIMDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GHLHandleIMDoubleTapReply();
}

+ (void)ghl_handleIMAvatarLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UITableView *table = (UITableView *)gesture.view;
    if (![table isKindOfClass:[UITableView class]]) return;
    CGPoint point = [gesture locationInView:table];
    GHLHandleIMAvatarLongPress(table, point);
}

+ (void)ghl_handleAISegmentChanged:(UISegmentedControl *)segment {
    GHLHandleAISegmentChanged(segment);
}

+ (void)ghl_handleAIParseStart:(UIButton *)button {
    GHLHandleAIParseStart(button);
}

// 1.0.5 手势自定义
+ (void)ghl_handleCustomTripleTap:(UITapGestureRecognizer *)gesture {
    GHLHandleCustomTripleTap(gesture);
}

+ (void)ghl_handleTwoFingerDoubleTap:(UITapGestureRecognizer *)gesture {
    GHLHandleTwoFingerDoubleTap(gesture);
}

+ (void)ghl_handleSwipeLeft:(UISwipeGestureRecognizer *)gesture {
    GHLHandleSwipeLeft(gesture);
}

+ (void)ghl_handleSwipeRight:(UISwipeGestureRecognizer *)gesture {
    GHLHandleSwipeRight(gesture);
}

// 1.0.19 浮动按钮＋卡片面板（target-action 只能挂对象方法，挂 GHLFeatures 的类方法）
+ (void)ghl_floatPanelButtonTapped {
    GHLLog(@"快捷面板：已点浮动钮");
    GHLToggleFloatPanel();
}

+ (void)ghl_floatPanelDimTapped:(UITapGestureRecognizer *)gesture {
    GHLFloatPanelHandleDimTap(gesture);
}

// 卡片里设置页根的「关闭」按钮（点一下关掉整张卡片）。
+ (void)ghl_floatPanelCloseTapped {
    GHLHideFloatPanel();
}

@end

#pragma mark - Hooks

%hook AWEFeedContainerViewController
- (void)aweme:(id)arg1 currentIndexDidChange:(NSInteger)arg2 {
    %orig;
    GHLMaybeAutoLike();
}
%end

// (8) 点赞自动保存 + (10) 手势安装 + (22) 侧边栏排序
%hook AWEPlayInteractionViewController
- (void)performLikeAction {
    %orig;
    if (!GHLGetBool(GHL_KEY_AUTO_SAVE_LIKED)) return;
    __weak AWEPlayInteractionViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      @try {
          AWEPlayInteractionViewController *strongSelf = weakSelf;
          if (!strongSelf) return;
          AWEAwemeModel *model = strongSelf.model;
          if (!model || !model.video) return;
          // 确认现在是已点赞状态（避免点取消时也下载）
          __block BOOL liked = NO;
          NSMutableArray *stack = [NSMutableArray arrayWithObject:strongSelf.view];
          while (stack.count > 0 && !liked) {
              UIView *view = stack.lastObject;
              [stack removeLastObject];
              if ([view isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")] &&
                  [((AWEFeedVideoButton *)view).accessibilityLabel isEqualToString:@"点赞"]) {
                  liked = ((UIButton *)view).selected;
                  break;
              }
              [stack addObjectsFromArray:view.subviews];
          }
          if (!liked) return;
          NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
          NSMutableArray *saved = [[defaults objectForKey:@"GHLAutoSavedLikedIDs"] mutableCopy] ?: [NSMutableArray array];
          if ([saved containsObject:model.itemID]) return;
          [saved addObject:model.itemID];
          [defaults setObject:saved forKey:@"GHLAutoSavedLikedIDs"];
          NSURL *videoURL = nil;
          NSURL *audioURL = nil;
          if (model.video.h264URL && model.video.h264URL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:model.video.h264URL.originURLList.firstObject];
          } else if (model.video.playURL && model.video.playURL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:model.video.playURL.originURLList.firstObject];
          }
          if (model.music && model.music.playURL && model.music.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:model.music.playURL.originURLList.firstObject];
          }
          if (!videoURL) return;
          [DYYYManager downloadMedia:videoURL
                           mediaType:MediaTypeVideo
                               audio:audioURL
                          completion:^(BOOL success) {
                            GHLLog(@"点赞自动保存：%@ %@", model.itemID, success ? @"成功" : @"失败");
                          }];
          [DYYYUtils showToast:@"已点赞，视频自动保存中…"];
      } @catch (__unused NSException *exception) {
      }
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    GHLInstallFeedGesturesOnView(self.view);
}

- (void)viewDidLayoutSubviews {
    // 1.0.18 计时日志（只加日志，不改行为）：统计本钩子每秒调用次数＋耗时——
    // 本钩子每跳跑四组全树遍历（侧边栏排序/美化、界面缩放、数字改写），若每秒几十次、
    // 单次几十毫秒，就是主线程渐进饱和的另一半证据；单次 >50ms 另记一行。
    static CFAbsoluteTime ghlLayoutWindowStart = 0;
    static NSInteger ghlLayoutCallCount = 0;
    static double ghlLayoutTotalMs = 0;
    static double ghlLayoutMaxMs = 0;
    CFAbsoluteTime layoutStart = CFAbsoluteTimeGetCurrent();
    %orig;
    GHLApplySidebarOrderInView(self.view);
    // 1.0.8：右侧边栏美化在排序之后跑（缩放/间距/圆角底）。
    GHLApplySidebarBeautifyInView(self.view);
    GHLApplyInterfaceScaleInView(self.view);
    GHLApplyFakeStatsInView(self.view);
    double layoutMs = (CFAbsoluteTimeGetCurrent() - layoutStart) * 1000.0;
    if (ghlLayoutWindowStart == 0) ghlLayoutWindowStart = layoutStart;
    ghlLayoutCallCount++;
    ghlLayoutTotalMs += layoutMs;
    if (layoutMs > ghlLayoutMaxMs) ghlLayoutMaxMs = layoutMs;
    if (layoutMs > 50) {
        GHLLog(@"布局计时：单次 viewDidLayoutSubviews 耗时 %.1fms（超过 50ms）", layoutMs);
    }
    if ((layoutStart - ghlLayoutWindowStart) >= 1.0) {
        GHLLog(@"布局计时：过去 %.1f 秒 viewDidLayoutSubviews %ld 次，总耗时 %.1fms，最长 %.1fms",
               (layoutStart - ghlLayoutWindowStart), (long)ghlLayoutCallCount, ghlLayoutTotalMs, ghlLayoutMaxMs);
        ghlLayoutWindowStart = layoutStart;
        ghlLayoutCallCount = 0;
        ghlLayoutTotalMs = 0;
        ghlLayoutMaxMs = 0;
    }
}
%end

// (38) 深色键盘：评论输入框出现时把键盘改成深色
%hook AWECommentInputViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    GHLApplyDarkKeyboardInView(self.view);
}
%end

// (7)(29) 评论面板：关键词屏蔽 + 自动展开
%hook AWECommentContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    GHLStartCommentProcessing(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    GHLStopCommentProcessing();
}
%end

// (7) 评论关键词屏蔽：在 cell 布局时藏掉含关键词的格子（只在评论面板内生效）
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    @try {
        NSArray<NSString *> *blockKeywords = GHLCommentBlockKeywords();
        if (blockKeywords.count == 0) return;
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        if (!vc) return;
        NSString *vcName = NSStringFromClass([vc class]);
        if ([vcName rangeOfString:@"Comment"].location == NSNotFound) return;
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        GHLCollectLabelsInView(self.contentView, labels);
        BOOL blocked = NO;
        for (UILabel *label in labels) {
            for (NSString *keyword in blockKeywords) {
                if (label.text.length > 0 && [label.text containsString:keyword]) {
                    blocked = YES;
                    break;
                }
            }
            if (blocked) break;
        }
        self.hidden = blocked;
    } @catch (__unused NSException *exception) {
    }
}
%end

#pragma mark - 启动

%ctor {
    @autoreleasepool {
        GHLLog(@"顾海龙抖音 1.0.26 已加载（基于 DYYY MIT，免费使用，仅限学习交流）");
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        // 1.0.15：三个监听的 token 必须存下来（以前返回值丢了，监听立刻失效，
        // 画中画/截屏/音量监听全是死的）。
        ghlScreenshotObserverToken = [center addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          GHLHandleScreenshotTaken(note);
                        }];
        ghlVolumeObserverToken = [center addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          GHLHandleVolumeChange(note);
                        }];
        // 画中画：主触发改到 WillResignActive（还在前台时启动；DidEnterBackground
        // 再调 startPictureInPicture 就太晚了）；DidEnterBackground 留作兜底，
        // 一次后台只触发一次（GHLTriggerPiPForBackground 里的 guard）；回到前台重置。
        ghlPiPWillResignActiveToken = [center addObserverForName:UIApplicationWillResignActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          // 1.0.20：先开后台任务再触发（D 路等 item 就绪要几秒，App 已在后台）。
                          GHLBeginPiPBackgroundTaskIfNeeded();
                          GHLTriggerPiPForBackground();
                        }];
        ghlPiPDidEnterBackgroundToken = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          // 1.0.21：第 7 项——进后台时先记一行音频状态（和切后台触发那行对照）。
                          GHLLogAudioState(@"应用已进后台");
                          // 兜底：开关开着、还没触发过时，先开个后台任务撑到系统回调
                          // （或 10 秒超时），再触发。
                          GHLBeginPiPBackgroundTaskIfNeeded();
                          GHLTriggerPiPForBackground();
                          // 1.0.19：切后台时画中画没接上，兜底播放器不能留着继续放
                          // （皇上 1.0.18 反馈「退出抖音还有声音在讲」）。
                          // 3 秒后再查一次（给系统回调留时间；只清已经调过 start、回调又没来的那次，
                          // item 还没就绪的别动——KVO 就绪后还会调 start，看门狗会接手）。
                          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            if (!ghlPiPFallbackPlayer || !ghlPiPFallbackStarted) return;
                            if (ghlPiPStartCallbackReceived) return;
                            if (ghlPiPController && ghlPiPController.pictureInPictureActive) return;
                            if (CFAbsoluteTimeGetCurrent() - ghlPiPLastStartTime < 3) return;
                            GHLLog(@"画中画：切后台时没接上（3 秒没回调），停掉兜底播放器");
                            GHLCleanupFallbackPiPPlayer();
                          });
                        }];
        ghlPiPDidBecomeActiveToken = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          ghlPiPTriggeredForCurrentBackground = NO;
                        }];
        GHLStartHousekeepingTimer();
        GHLStartMainThreadWatchdog(); // 1.0.21：第 6 项——冻住看门狗（诊断用，只抓证据）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          if (GHLGetBool(GHL_KEY_NIGHT_MODE)) GHLApplyNightMode(YES);
          if (GHLGetBool(GHL_KEY_ANTI_RECALL)) GHLProbeAntiRecall();
          if (GHLGetBool(GHL_KEY_HIDE_TYPING) || GHLGetBool(GHL_KEY_HIDE_READ_RECEIPT) || GHLGetBool(GHL_KEY_ANTI_BURN)) GHLProbePrivacyFeatures();
          if (GHLGetBool(GHL_KEY_COMMENT_VOICE)) GHLProbeCommentVoice();
          if (GHLGetBool(GHL_KEY_VOICE_FORWARD) || GHLGetBool(GHL_KEY_VOICE_DURATION) || GHLGetBool(GHL_KEY_VOICE_REPLACE_COMMENT) || GHLGetBool(GHL_KEY_COMMENT_VOICE_SAVE)) GHLProbeVoiceFeatures();
          if (GHLGetBool(GHL_KEY_LIVE_DURATION) || GHLGetBool(GHL_KEY_LIVE_RECORD) || GHLGetBool(GHL_KEY_FAKE_LIVE_USER_COUNT)) GHLProbeLiveRoom();
          GHLRestartSleepTimer();
        });
    }
}

// 1.0.15：进程退出时移除 %ctor 里注册的监听（照 DYYY.xm 的 DYYYRemoveAppLifecycleObservers 写法）。
%hook AppDelegate
- (void)applicationWillTerminate:(UIApplication *)application {
    // 1.0.21：第 7 项——进程要没了，尽力停兜底＋停画中画。先记一行音频状态（和切后台触发／
    // 已进后台那两行对照），再停。诚实边界：彻底划掉是 SIGKILL，WillTerminate 未必跑得到；
    // 跑到了就停，跑不到时声音若还在响，就是系统画中画会话在终止后存活，那是 iOS 行为，
    // 不是咱们能停的——日志里要分得清（所以先记状态再停）。
    GHLLogAudioState(@"应用将终止");
    if (ghlPiPController && ghlPiPController.pictureInPictureActive) {
        [ghlPiPController stopPictureInPicture];
        GHLLog(@"应用将终止：画中画已停");
    }
    if (ghlPiPFallbackPlayer) {
        GHLCleanupFallbackPiPPlayer(); // 里面会记「兜底播放器：已停止」
        GHLLog(@"应用将终止：兜底播放器已停");
    }
    GHLRemovePiPObservers();
    %orig;
}
%end

#pragma mark - (31) 语音包（xuu 式管理器，代码全部自己写）
// 行为参考（只学流程，不碰对方代码）：语音包列表（按文件夹/分类、按名字搜）→ 选一个
// 音色 → 试听 → 输入文字合成语音 → 发到私信/直播。
// 音色分两档：
//   a. 内置档：iOS 自带的 AVSpeechSynthesisVoice（本机就有，多个中文音色），不联网、不用 key；
//   b. 在线档：Fish Audio（api.fish.audio/v1/tts），皇上自己在设置页填 key 才能用；
//      没有 key 就只用内置档。绝不用 xuu 的 token、不调它那个要验证的远程服务。
// 诚实说明：这不是真人声音克隆——在线音色是 Fish Audio 的 TTS 模型音色，
// 不是“语音包里对方那个人”的克隆；直播里发语音目前只做运行期探针，不 hook、不发包。

@implementation GHLVoicePackageInfo

+ (instancetype)packageWithVoiceId:(NSString *)voiceId
                       displayName:(NSString *)displayName
                          category:(NSString *)category
                            source:(GHLVoicePackageSource)source
             systemVoiceIdentifier:(NSString *)systemVoiceIdentifier
                       fishModelId:(NSString *)fishModelId {
    GHLVoicePackageInfo *info = [[self alloc] init];
    info.voiceId = voiceId ?: @"";
    info.displayName = displayName ?: voiceId ?: @"";
    info.category = category ?: @"内置";
    info.source = source;
    info.systemVoiceIdentifier = systemVoiceIdentifier;
    info.fishModelId = fishModelId;
    return info;
}

@end

// 内置档：枚举本机中文 TTS 语音（只列 zh，够用；没有就留一个默认中文入口）
static NSArray<GHLVoicePackageInfo *> *GHLBuiltInVoicePackages(void) {
    static NSArray<GHLVoicePackageInfo *> *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSMutableArray<GHLVoicePackageInfo *> *list = [NSMutableArray array];
      for (AVSpeechSynthesisVoice *voice in [AVSpeechSynthesisVoice speechVoices]) {
          if (![voice.language hasPrefix:@"zh"]) continue;
          NSString *voiceId = [@"sys:" stringByAppendingString:voice.identifier];
          NSString *name = [NSString stringWithFormat:@"%@（%@）", voice.name, voice.language];
          [list addObject:[GHLVoicePackageInfo packageWithVoiceId:voiceId
                                                       displayName:name
                                                          category:@"内置"
                                                            source:GHLVoicePackageSourceBuiltIn
                                             systemVoiceIdentifier:voice.identifier
                                                       fishModelId:nil]];
      }
      if (list.count == 0) {
          [list addObject:[GHLVoicePackageInfo packageWithVoiceId:@"sys:default-zh-CN"
                                                       displayName:@"系统默认中文（内置）"
                                                          category:@"内置"
                                                            source:GHLVoicePackageSourceBuiltIn
                                             systemVoiceIdentifier:nil
                                                       fishModelId:nil]];
      }
      cached = [list copy];
    });
    return cached;
}

// 在线档：读缓存的 Fish Audio 语音包列表（id/title）
static NSArray<GHLVoicePackageInfo *> *GHLFishAudioVoicePackages(void) {
    NSArray *cached = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_FISH_AUDIO_VOICES_CACHE];
    if (![cached isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<GHLVoicePackageInfo *> *list = [NSMutableArray array];
    for (id item in cached) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *modelId = item[@"id"];
        NSString *title = item[@"title"];
        if (![modelId isKindOfClass:[NSString class]] || modelId.length == 0) continue;
        if (![title isKindOfClass:[NSString class]] || title.length == 0) title = modelId;
        NSString *voiceId = [@"fish:" stringByAppendingString:modelId];
        [list addObject:[GHLVoicePackageInfo packageWithVoiceId:voiceId
                                                     displayName:title
                                                        category:@"在线"
                                                          source:GHLVoicePackageSourceFishAudio
                                           systemVoiceIdentifier:nil
                                                     fishModelId:modelId]];
    }
    // 1.0.4：Fish Audio 返回的模型没有分类/热度字段，不编造热度数字，按名字排。
    [list sortUsingComparator:^NSComparisonResult(GHLVoicePackageInfo *a, GHLVoicePackageInfo *b) {
      return [a.displayName localizedStandardCompare:b.displayName];
    }];
    return list;
}

#pragma mark - 1.0.24：导入的语音（自定义档）+ 文件夹

// 导入的语音存在 App 沙盒 Documents/DYYY/VoicePackages/，记录在 NSUserDefaults
//（GHL_KEY_CUSTOM_VOICES：字典数组 @{@"name", @"file", @"folder"}）。
// 导入的是一段录好的音频，点一下就播放，不能像内置/在线那样合成任意文字——
// 所以它不进设置页的 TTS 选取器（GHLVoicePackageIDs 只给能合成的），只在管理器里播。
NSString *GHLCustomVoicePackagesDirectory(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [documents stringByAppendingPathComponent:@"DYYY/VoicePackages"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSArray<NSDictionary *> *GHLCustomVoiceRecords(void) {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_CUSTOM_VOICES];
    if (![stored isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    for (id item in stored) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = item[@"name"];
        NSString *file = item[@"file"];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) continue;
        if (![file isKindOfClass:[NSString class]] || file.length == 0) continue;
        NSString *folder = item[@"folder"];
        if (![folder isKindOfClass:[NSString class]] || folder.length == 0) folder = @"我的导入";
        [records addObject:@{@"name": name, @"file": file, @"folder": folder}];
    }
    return records;
}

static void GHLSaveCustomVoiceRecords(NSArray<NSDictionary *> *records) {
    [[NSUserDefaults standardUserDefaults] setObject:records forKey:GHL_KEY_CUSTOM_VOICES];
}

// 文件夹列表：我的导入在前，自建文件夹按建的顺序排。
NSArray<NSString *> *GHLCustomVoiceFolders(void) {
    NSMutableArray<NSString *> *folders = [NSMutableArray arrayWithObject:@"我的导入"];
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_VOICE_CUSTOM_FOLDERS];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id item in stored) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0 && ![folders containsObject:item]) {
                [folders addObject:item];
            }
        }
    }
    return folders;
}

static NSArray<GHLVoicePackageInfo *> *GHLCustomVoicePackages(void) {
    NSMutableArray<GHLVoicePackageInfo *> *list = [NSMutableArray array];
    NSString *dir = GHLCustomVoicePackagesDirectory();
    NSArray<NSString *> *folderOrder = GHLCustomVoiceFolders();
    for (NSDictionary *record in GHLCustomVoiceRecords()) {
        NSString *path = [dir stringByAppendingPathComponent:record[@"file"]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue; // 文件没了就跳过（记录留着，文件回来还能用）
        [list addObject:[GHLVoicePackageInfo customPackageWithName:record[@"name"] filePath:path folder:record[@"folder"]]];
    }
    [list sortUsingComparator:^NSComparisonResult(GHLVoicePackageInfo *a, GHLVoicePackageInfo *b) {
        NSUInteger ia = [folderOrder indexOfObject:a.category];
        NSUInteger ib = [folderOrder indexOfObject:b.category];
        if (ia == NSNotFound) ia = folderOrder.count;
        if (ib == NSNotFound) ib = folderOrder.count;
        if (ia != ib) return ia < ib ? NSOrderedAscending : NSOrderedDescending;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
    return list;
}

void GHLCreateVoiceFolder(NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [DYYYUtils showToast:@"文件夹名字是空的"];
        return;
    }
    if ([trimmed isEqualToString:@"内置"] || [trimmed isEqualToString:@"在线"] || [trimmed isEqualToString:@"我的导入"] || [trimmed isEqualToString:@"★ 收藏"]) {
        [DYYYUtils showToast:@"这个名字是系统留用的，换一个"];
        return;
    }
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_VOICE_CUSTOM_FOLDERS];
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id item in stored) {
            if ([item isKindOfClass:[NSString class]]) [folders addObject:item];
        }
    }
    if ([folders containsObject:trimmed]) {
        [DYYYUtils showToast:@"已经有这个文件夹了"];
        return;
    }
    [folders addObject:trimmed];
    [[NSUserDefaults standardUserDefaults] setObject:folders forKey:GHL_KEY_VOICE_CUSTOM_FOLDERS];
    // 1.0.26：建成功弹一句提示（以前成功了什么都不说，空文件夹又不显示，看着像建失败）。
    [DYYYUtils showToast:[NSString stringWithFormat:@"已新建文件夹「%@」", trimmed]];
    GHLLog(@"语音包文件夹：新建「%@」", trimmed);
}

void GHLDeleteVoiceFolder(NSString *name) {
    if (!name || name.length == 0) return;
    // 里面的导入语音回“我的导入”。
    NSMutableArray<NSDictionary *> *records = [NSMutableArray arrayWithArray:GHLCustomVoiceRecords()];
    for (NSUInteger i = 0; i < records.count; i++) {
        NSMutableDictionary *record = [records[i] mutableCopy];
        if ([record[@"folder"] isEqualToString:name]) {
            record[@"folder"] = @"我的导入";
            records[i] = record;
        }
    }
    GHLSaveCustomVoiceRecords(records);
    // 内置/在线音色指派到这个文件夹的也清掉（回默认分类）。
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:GHL_KEY_VOICE_FOLDER_MAP] ?: @{}];
    for (NSString *key in [map allKeys]) {
        if ([map[key] isEqualToString:name]) [map removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:map forKey:GHL_KEY_VOICE_FOLDER_MAP];
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_VOICE_CUSTOM_FOLDERS];
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id item in stored) {
            if ([item isKindOfClass:[NSString class]] && ![item isEqualToString:name]) [folders addObject:item];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:folders forKey:GHL_KEY_VOICE_CUSTOM_FOLDERS];
    GHLLog(@"语音包文件夹：已删「%@」（里面的语音回“我的导入”）", name);
}

void GHLMoveVoiceToFolder(NSString *voiceId, NSString *folder) {
    if (!voiceId || voiceId.length == 0) return;
    NSString *target = [folder stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([voiceId hasPrefix:@"custom:"]) {
        // 导入的语音：改记录里的 folder（空 = 回“我的导入”）。
        NSMutableArray<NSDictionary *> *records = [NSMutableArray arrayWithArray:GHLCustomVoiceRecords()];
        for (NSUInteger i = 0; i < records.count; i++) {
            NSString *candidateId = [@"custom:" stringByAppendingString:records[i][@"file"]];
            if (![candidateId isEqualToString:voiceId]) continue;
            NSMutableDictionary *record = [records[i] mutableCopy];
            record[@"folder"] = (target.length > 0 ? target : @"我的导入");
            records[i] = record;
            break;
        }
        GHLSaveCustomVoiceRecords(records);
        GHLLog(@"语音包：%@ 已移到「%@」", voiceId, target.length > 0 ? target : @"我的导入");
        return;
    }
    // 内置/在线音色：记指派表（空 = 移出，回默认分类）。
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:GHL_KEY_VOICE_FOLDER_MAP] ?: @{}];
    if (target.length == 0) {
        [map removeObjectForKey:voiceId];
    } else {
        map[voiceId] = target;
    }
    [[NSUserDefaults standardUserDefaults] setObject:map forKey:GHL_KEY_VOICE_FOLDER_MAP];
    GHLLog(@"语音包：%@ 已移到「%@」", voiceId, target.length > 0 ? target : @"默认分类");
}

NSString *GHLFolderForVoiceId(NSString *voiceId) {
    if (!voiceId) return nil;
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) {
        if ([info.voiceId isEqualToString:voiceId]) return info.category;
    }
    return nil;
}

void GHLDeleteCustomVoice(NSString *voiceId) {
    if (!voiceId || ![voiceId hasPrefix:@"custom:"]) return;
    NSString *file = [voiceId substringFromIndex:[@"custom:" length]];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray arrayWithArray:GHLCustomVoiceRecords()];
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *record in records) {
        if (![record[@"file"] isEqualToString:file]) [kept addObject:record];
    }
    GHLSaveCustomVoiceRecords(kept);
    [[NSFileManager defaultManager] removeItemAtPath:[GHLCustomVoicePackagesDirectory() stringByAppendingPathComponent:file] error:nil];
    // 收藏/选中里清掉（选中了它就回默认中文音色）。
    NSMutableSet<NSString *> *favorites = [NSMutableSet setWithSet:GHLVoiceFavorites()];
    if ([favorites containsObject:voiceId]) {
        [favorites removeObject:voiceId];
        [[NSUserDefaults standardUserDefaults] setObject:[favorites allObjects] forKey:GHL_KEY_VOICE_FAVORITES];
    }
    if ([[[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_VOICE_PACKAGE_ID] isEqualToString:voiceId]) {
        [[NSUserDefaults standardUserDefaults] setObject:@"sys:default-zh-CN" forKey:GHL_KEY_VOICE_PACKAGE_ID];
    }
    GHLLog(@"语音包：已删导入的「%@」", file);
}

NSString *GHLFileSizeText(NSString *path) {
    if (!path || path.length == 0) return @"";
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    unsigned long long bytes = [attrs[NSFileSize] unsignedLongLongValue];
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
}

// 导入一个文件进语音包：已经是音频（m4a/mp3/wav/aac/caf/aiff）就直接复制；
// 视频（mp4/mov 等）只抽音频轨转成 .m4a（AVAssetExportSession，AppleM4A 预设，
// 复用 DYYYManager 里 AVAssetReader/Writer 转码的同一思路：音频轨 AAC 44.1k）。
// 完成回调在主线程跑（成功时 name 是显示名）。
void GHLImportVoiceAudioFileAtURL(NSURL *url, void (^done)(BOOL success, NSString * _Nullable name)) {
    if (!url) {
        if (done) done(NO, nil);
        return;
    }
    NSString *ext = url.pathExtension.lowercaseString;
    NSString *baseName = [[url.lastPathComponent stringByDeletingPathExtension] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (baseName.length == 0) baseName = @"导入的语音";
    NSString *dir = GHLCustomVoicePackagesDirectory();
    NSString *(^uniqueFileName)(NSString *, NSString *) = ^NSString *(NSString *base, NSString *targetExt) {
        NSString *candidate = [NSString stringWithFormat:@"%@.%@", base, targetExt];
        NSInteger n = 2;
        while ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:candidate]]) {
            candidate = [NSString stringWithFormat:@"%@ %ld.%@", base, (long)n, targetExt];
            n++;
        }
        return candidate;
    };
    void (^registerVoice)(NSString *, NSString *) = ^(NSString *fileName, NSString *displayName) {
        NSMutableArray *records = [NSMutableArray arrayWithArray:GHLCustomVoiceRecords()];
        [records addObject:@{@"name": displayName, @"file": fileName, @"folder": @"我的导入"}];
        GHLSaveCustomVoiceRecords(records);
        GHLLog(@"语音包导入：已导入「%@」（%@）", displayName, fileName);
        [DYYYUtils showToast:[NSString stringWithFormat:@"已导入「%@」", displayName]];
        if (done) done(YES, displayName);
    };
    NSSet<NSString *> *audioExts = [NSSet setWithObjects:@"m4a", @"mp3", @"wav", @"aac", @"caf", @"aiff", @"aif", nil];
    if ([audioExts containsObject:ext]) {
        NSString *fileName = uniqueFileName(baseName, ext);
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:fileName]] error:&error]) {
            GHLLog(@"语音包导入：复制失败 %@", error.localizedDescription);
            [DYYYUtils showToast:@"导入失败，文件复制不出来"];
            if (done) done(NO, nil);
            return;
        }
        registerVoice(fileName, baseName);
        return;
    }
    AVURLAsset *asset = [AVURLAsset assetWithURL:url];
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!session) {
        GHLLog(@"语音包导入：这个文件转不了音频（%@）", url.lastPathComponent);
        [DYYYUtils showToast:@"这个文件里没有能转的音频"];
        if (done) done(NO, nil);
        return;
    }
    NSString *fileName = uniqueFileName(baseName, @"m4a");
    NSURL *outputURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:fileName]];
    session.outputURL = outputURL;
    session.outputFileType = AVFileTypeAppleM4A;
    [DYYYUtils showToast:@"正在转音频…"];
    [session exportAsynchronouslyWithCompletionHandler:^{
        if (session.status != AVAssetExportSessionStatusCompleted) {
            GHLLog(@"语音包导入：转音频失败 %@", session.error.localizedDescription);
            [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
            GHLRunOnMain(^{
              [DYYYUtils showToast:@"导入失败，转音频没成功"];
              if (done) done(NO, nil);
            });
            return;
        }
        GHLRunOnMain(^{
          registerVoice(fileName, baseName);
        });
    }];
}

// 导出：把导入的语音文件分享出去（voiceIds 为空 = 全部；只导导入档，不导内置/在线）。
void GHLExportCustomVoices(UIViewController *presenter, NSArray<NSString *> *voiceIds) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (GHLVoicePackageInfo *info in GHLCustomVoicePackages()) {
        if (voiceIds.count > 0 && ![voiceIds containsObject:info.voiceId]) continue;
        if (info.audioFilePath.length > 0) [urls addObject:[NSURL fileURLWithPath:info.audioFilePath]];
    }
    if (urls.count == 0) {
        [DYYYUtils showToast:@"没有能导出的导入语音"];
        return;
    }
    GHLRunOnMain(^{
      UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
      if (activity.popoverPresentationController) {
          activity.popoverPresentationController.sourceView = presenter.view;
          activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
      }
      [presenter presentViewController:activity animated:YES completion:nil];
      GHLLog(@"语音包导出：已分享 %lu 个文件", (unsigned long)urls.count);
    });
}

NSArray<GHLVoicePackageInfo *> *GHLVoicePackageList(void) {
    // 1.0.24：内置/在线音色被移进文件夹时，category 就是文件夹名（指派表 GHL_KEY_VOICE_FOLDER_MAP）；
    // 没指派就回默认分类（内置/在线）；导入档自带文件夹（默认“我的导入”）。
    NSDictionary *folderMap = [[NSUserDefaults standardUserDefaults] dictionaryForKey:GHL_KEY_VOICE_FOLDER_MAP];
    NSMutableArray<GHLVoicePackageInfo *> *all = [NSMutableArray array];
    for (GHLVoicePackageInfo *info in GHLBuiltInVoicePackages()) {
        NSString *folder = folderMap[info.voiceId];
        info.category = ([folder isKindOfClass:[NSString class]] && folder.length > 0) ? folder : @"内置";
        [all addObject:info];
    }
    for (GHLVoicePackageInfo *info in GHLFishAudioVoicePackages()) {
        NSString *folder = folderMap[info.voiceId];
        info.category = ([folder isKindOfClass:[NSString class]] && folder.length > 0) ? folder : @"在线";
        [all addObject:info];
    }
    [all addObjectsFromArray:GHLCustomVoicePackages()];
    return all;
}

NSArray<GHLVoicePackageInfo *> *GHLVoicePackagesInCategory(NSString *category) {
    NSMutableArray<GHLVoicePackageInfo *> *result = [NSMutableArray array];
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) {
        if ([info.category isEqualToString:category]) [result addObject:info];
    }
    return result;
}

NSArray<GHLVoicePackageInfo *> *GHLSearchVoicePackages(NSString *query) {
    if (!query || query.length == 0) return GHLVoicePackageList();
    NSString *lowerQuery = query.lowercaseString;
    NSMutableArray<GHLVoicePackageInfo *> *result = [NSMutableArray array];
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) {
        if ([info.displayName.lowercaseString containsString:lowerQuery] ||
            [info.voiceId.lowercaseString containsString:lowerQuery]) {
            [result addObject:info];
        }
    }
    return result;
}

NSArray<NSString *> *GHLVoicePackageIDs(void) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) {
        // 1.0.24：导入的录音不能合成文字，不进设置页的 TTS 选取器。
        if (info.source == GHLVoicePackageSourceCustom) continue;
        [ids addObject:info.voiceId];
    }
    return ids;
}

GHLVoicePackageInfo *GHLVoicePackageForID(NSString *voiceId) {
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) {
        if (voiceId && [info.voiceId isEqualToString:voiceId]) return info;
    }
    return GHLVoicePackageList().firstObject;
}

NSString *GHLVoicePackageDisplayNameForID(NSString *voiceId) {
    GHLVoicePackageInfo *info = GHLVoicePackageForID(voiceId);
    return info ? info.displayName : @"未选择";
}

// 1.0.4 语音包收藏：收藏的 voiceId 存在 NSUserDefaults（GHL_KEY_VOICE_FAVORITES）。
NSSet<NSString *> *GHLVoiceFavorites(void) {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_VOICE_FAVORITES];
    if (![stored isKindOfClass:[NSArray class]]) return [NSSet set];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]]) [set addObject:item];
    }
    return [set copy];
}

BOOL GHLIsVoiceFavorite(NSString *voiceId) {
    return voiceId.length > 0 && [GHLVoiceFavorites() containsObject:voiceId];
}

void GHLSetVoiceFavorite(NSString *voiceId, BOOL favorite) {
    if (voiceId.length == 0) return;
    NSMutableSet<NSString *> *set = [NSMutableSet setWithSet:GHLVoiceFavorites()];
    if (favorite) {
        [set addObject:voiceId];
    } else {
        [set removeObject:voiceId];
    }
    [[NSUserDefaults standardUserDefaults] setObject:set.allObjects forKey:GHL_KEY_VOICE_FAVORITES];
}

static AVSpeechSynthesizer *ghlSpeechSynthesizer = nil;

static AVSpeechUtterance *GHLUtteranceForText(NSString *text, GHLVoicePackageInfo *info) {
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    AVSpeechSynthesisVoice *voice = nil;
    if (info.systemVoiceIdentifier.length > 0) {
        voice = [AVSpeechSynthesisVoice voiceWithIdentifier:info.systemVoiceIdentifier];
    }
    if (!voice) voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    utterance.voice = voice;
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
    utterance.volume = 1.0f;
    return utterance;
}

static AVAudioPlayer *ghlFishPreviewPlayer = nil;
static AVAudioPlayer *ghlCustomVoicePlayer = nil; // 1.0.24：导入语音试听的播放器（留着不释放，不然播一半就停）

// Fish Audio API Key：优先读设置页填的值，没填就用皇上自己的默认 key（已填好）
static NSString *GHLFishAudioAPIKey(void) {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_FISH_AUDIO_API_KEY];
    if (stored.length > 0) return stored;
    return GHL_DEFAULT_FISH_AUDIO_API_KEY;
}

// 在线档：用 Fish Audio 合成一段文字，返回音频文件 URL（.mp3）；失败回调 nil
static void GHLSynthesizeWithFishAudio(NSString *text, NSString *modelId, void (^completion)(NSURL *fileURL)) {
    NSString *apiKey = GHLFishAudioAPIKey();
    if (apiKey.length == 0) {
        GHLLog(@"语音包合成（在线）：没有填 Fish Audio API Key，先去设置页填写");
        GHLRunOnMain(^{
          [DYYYUtils showToast:@"在线音色要先在设置页填 Fish Audio API Key"];
        });
        if (completion) completion(nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:@"https://api.fish.audio/v1/tts"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // 免费账号用 s2.1-pro-free（$0）；不带 model 头会默认走付费 s2.1-pro，$0 余额会失败
    [request setValue:@"s2.1-pro-free" forHTTPHeaderField:@"model"];
    NSDictionary *body = @{
        @"text" : text,
        @"reference_id" : modelId,
        @"format" : @"mp3",
        @"mp3_bitrate" : @128,
        @"normalize" : @YES,
        @"latency" : @"normal"
    };
    NSError *jsonError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) {
        GHLLog(@"语音包合成（在线）：组请求失败 %@", jsonError.localizedDescription);
        if (completion) completion(nil);
        return;
    }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                   NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                                                   if (error || !data || data.length == 0 || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                                                                       GHLLog(@"语音包合成（在线）：请求失败 HTTP %ld %@", (long)httpResponse.statusCode, error.localizedDescription);
                                                                       GHLRunOnMain(^{
                                                                         [DYYYUtils showToast:@"在线合成失败，检查 key 和网络"];
                                                                       });
                                                                       if (completion) completion(nil);
                                                                       return;
                                                                   }
                                                                   NSString *fileName = [NSString stringWithFormat:@"ghl_voice_%@.mp3", [[NSUUID UUID] UUIDString]];
                                                                   NSURL *fileURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:fileName];
                                                                   if ([data writeToURL:fileURL atomically:YES]) {
                                                                       GHLLog(@"语音包合成（在线）：完成 %@", fileURL.lastPathComponent);
                                                                       if (completion) completion(fileURL);
                                                                   } else {
                                                                       GHLLog(@"语音包合成（在线）：写文件失败");
                                                                       if (completion) completion(nil);
                                                                   }
                                                                 }];
    [task resume];
}

void GHLPreviewVoicePackage(NSString *voiceId) {
    if (!GHLGetBool(GHL_KEY_VOICE_PACKAGE)) {
        [DYYYUtils showToast:@"请先打开语音包开关"];
        return;
    }
    GHLVoicePackageInfo *info = GHLVoicePackageForID(voiceId);
    if (!info) return;
    NSString *sample = [NSString stringWithFormat:@"顾海龙抖音语音包试听，现在是%@音色。", info.displayName];
    if (info.source == GHLVoicePackageSourceCustom) {
        // 1.0.24：导入的录音直接播文件（不能合成文字，所以不念试听句）。
        GHLRunOnMain(^{
          if (ghlCustomVoicePlayer.playing) [ghlCustomVoicePlayer stop];
          NSError *playerError = nil;
          ghlCustomVoicePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:info.audioFilePath] error:&playerError];
          if (!ghlCustomVoicePlayer) {
              GHLLog(@"语音包试听（导入）：播放器建失败 %@", playerError.localizedDescription);
              return;
          }
          [ghlCustomVoicePlayer play];
          GHLLog(@"语音包试听（导入）：%@", info.displayName);
        });
        return;
    }
    if (info.source == GHLVoicePackageSourceFishAudio) {
        [DYYYUtils showToast:@"正在联网合成试听…"];
        GHLSynthesizeWithFishAudio(sample, info.fishModelId, ^(NSURL *fileURL) {
          if (!fileURL) return;
          GHLRunOnMain(^{
            NSError *playerError = nil;
            ghlFishPreviewPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&playerError];
            if (!ghlFishPreviewPlayer) {
                GHLLog(@"语音包试听（在线）：播放器建失败 %@", playerError.localizedDescription);
                return;
            }
            [ghlFishPreviewPlayer play];
            GHLLog(@"语音包试听（在线）：%@", info.displayName);
          });
        });
        return;
    }
    GHLRunOnMain(^{
      if (!ghlSpeechSynthesizer) ghlSpeechSynthesizer = [[AVSpeechSynthesizer alloc] init];
      if (ghlSpeechSynthesizer.speaking) [ghlSpeechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
      [ghlSpeechSynthesizer speakUtterance:GHLUtteranceForText(sample, info)];
      GHLLog(@"语音包试听（内置）：%@", info.displayName);
    });
}

void GHLSynthesizeVoicePackageText(NSString *text, NSString *voiceId, void (^completion)(NSURL *fileURL)) {
    if (text.length == 0) {
        if (completion) completion(nil);
        return;
    }
    GHLVoicePackageInfo *info = GHLVoicePackageForID(voiceId);
    if (!info) {
        if (completion) completion(nil);
        return;
    }
    if (info.source == GHLVoicePackageSourceCustom) {
        // 1.0.24：导入的录音是固定音频，合成不了文字。
        GHLLog(@"语音包合成：导入的录音不能合成文字");
        if (completion) completion(nil);
        return;
    }
    if (info.source == GHLVoicePackageSourceFishAudio) {
        GHLSynthesizeWithFishAudio(text, info.fishModelId, completion);
        return;
    }
    AVSpeechUtterance *utterance = GHLUtteranceForText(text, info);
    AVSpeechSynthesizer *synthesizer = [[AVSpeechSynthesizer alloc] init];
    NSString *fileName = [NSString stringWithFormat:@"ghl_voice_%@.caf", [[NSUUID UUID] UUIDString]];
    NSURL *outputURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:fileName];
    NSDictionary *settings = @{
        AVFormatIDKey : @(kAudioFormatLinearPCM),
        AVSampleRateKey : @(22050),
        AVNumberOfChannelsKey : @(1),
        AVLinearPCMBitDepthKey : @(16),
        AVLinearPCMIsNonInterleaved : @(NO),
        AVLinearPCMIsFloatKey : @(NO),
        AVLinearPCMIsBigEndianKey : @(NO)
    };
    NSError *fileError = nil;
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForWriting:outputURL settings:settings error:&fileError];
    if (!audioFile) {
        GHLLog(@"语音包合成：建文件失败 %@", fileError.localizedDescription);
        if (completion) completion(nil);
        return;
    }
    __block AVAudioFile *file = audioFile;
    __block BOOL finished = NO;
    [synthesizer writeUtterance:utterance
               toBufferCallback:^(AVAudioBuffer *buffer) {
                 if (!buffer) return;
                 NSError *writeError = nil;
                 if ([buffer isKindOfClass:[AVAudioPCMBuffer class]]) {
                     AVAudioPCMBuffer *pcmBuffer = (AVAudioPCMBuffer *)buffer;
                     if (pcmBuffer.frameLength == 0) return;
                     if (![file writeFromBuffer:pcmBuffer error:&writeError]) {
                         GHLLog(@"语音包合成：写 buffer 失败 %@", writeError.localizedDescription);
                     }
                 }
               }];
    // 轮询等合成完成（writeUtterance 是异步的，合成器 speaking 结束即完成）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
      for (int i = 0; i < 600 && !finished; i++) {
          if (!synthesizer.speaking) {
              finished = YES;
              break;
          }
          [NSThread sleepForTimeInterval:0.1];
      }
      GHLRunOnMain(^{
        if (finished) {
            GHLLog(@"语音包合成：完成 %@", outputURL.lastPathComponent);
        } else {
            GHLLog(@"语音包合成：超时（60s）");
        }
        if (completion) completion(finished ? outputURL : nil);
      });
    });
}

// 在线档：从 Fish Audio 拉语音包列表（需 key；成功后缓存并回调）
void GHLFetchFishAudioVoiceListWithCompletion(void (^completion)(NSArray<GHLVoicePackageInfo *> *voices, NSError *error)) {
    NSString *apiKey = GHLFishAudioAPIKey();
    if (apiKey.length == 0) {
        NSError *error = [NSError errorWithDomain:@"GHLVoicePackage"
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey : @"没有填写 Fish Audio API Key"}];
        GHLLog(@"语音包拉取（在线）：没有填 Fish Audio API Key");
        if (completion) completion(@[], error);
        return;
    }
    // 官方列表接口是 GET /model（/v1/models 和 /v1/voices 都 404）；先拉公开库，再试自己的库
    NSArray<NSString *> *endpoints = @[ @"https://api.fish.audio/model?page_size=100", @"https://api.fish.audio/model?self=true&page_size=100" ];
    __block void (^tryFetch)(NSUInteger) = nil;
    tryFetch = ^(NSUInteger index) {
      if (index >= endpoints.count) {
          NSError *error = [NSError errorWithDomain:@"GHLVoicePackage"
                                               code:404
                                           userInfo:@{NSLocalizedDescriptionKey : @"拉取在线语音包列表失败"}];
          GHLLog(@"语音包拉取（在线）：两个列表接口都失败");
          if (completion) completion(@[], error);
          return;
      }
      NSURL *url = [NSURL URLWithString:endpoints[index]];
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
      [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
      NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                     NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                                                     NSArray *items = nil;
                                                                     if (!error && data && httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                                                                         NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                                                         if ([json isKindOfClass:[NSDictionary class]]) {
                                                                             items = json[@"items"];
                                                                             if (![items isKindOfClass:[NSArray class]]) items = json[@"voices"];
                                                                         }
                                                                     }
                                                                     if (![items isKindOfClass:[NSArray class]]) {
                                                                         tryFetch(index + 1);
                                                                         return;
                                                                     }
                                                                     NSMutableArray<NSDictionary *> *cached = [NSMutableArray array];
                                                                     for (id item in items) {
                                                                         if (![item isKindOfClass:[NSDictionary class]]) continue;
                                                                         NSString *modelId = item[@"_id"];
                                                                         if (![modelId isKindOfClass:[NSString class]]) modelId = item[@"id"];
                                                                         NSString *title = item[@"title"];
                                                                         if (![modelId isKindOfClass:[NSString class]] || modelId.length == 0) continue;
                                                                         if (![title isKindOfClass:[NSString class]] || title.length == 0) title = modelId;
                                                                         [cached addObject:@{@"id" : modelId, @"title" : title}];
                                                                     }
                                                                     [[NSUserDefaults standardUserDefaults] setObject:cached forKey:GHL_KEY_FISH_AUDIO_VOICES_CACHE];
                                                                     GHLLog(@"语音包拉取（在线）：拉到 %lu 个音色", (unsigned long)cached.count);
                                                                     if (completion) completion(GHLFishAudioVoicePackages(), nil);
                                                                   }];
      [task resume];
    };
    tryFetch(0);
}

#pragma mark 语音包管理器（列表/分类/搜索/试听/选中）

// 1.0.26：上次拉取在线列表失败过没（刷新成功后清掉；在线分区脚注靠它留一行失败提示，不再静默失败）。
static BOOL ghlOnlineFetchFailed = NO;

@interface GHLVoicePackageManagerViewController : UITableViewController <UISearchBarDelegate>
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
@property(nonatomic, strong, nullable) DYYYBackupPickerDelegate *voicePickerDelegate; // 1.0.24：导入语音的文件选择器代理（要留着，不然选完没人接）
@end

@implementation GHLVoicePackageManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"语音包管理";
    self.searchText = @"";
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"搜名字或 voiceId";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(ghlDismiss)];
    // 1.0.24：右上角 +（导入语音 / 新建文件夹 / 导出全部 / 删除文件夹）+ 刷新在线。
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(ghlAddButtonTapped)],
        [[UIBarButtonItem alloc] initWithTitle:@"刷新在线" style:UIBarButtonItemStylePlain target:self action:@selector(ghlRefreshOnline)]
    ];
    // 1.0.24：长按一行出菜单（收藏/移文件夹/分享/删除）。
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ghlRowLongPressed:)];
    [self.tableView addGestureRecognizer:longPress];
    [self ghlApplyAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ghlApplyAppearance];
    [self.tableView reloadData];
}

// 统一视觉：跟设置主页同一套（金色点缀、深色跟随、自定义背景铺底）。
- (BOOL)ghlDarkModeActive {
    return GHLFollowSystemDarkEnabled() && [DYYYUtils isDarkMode];
}

- (void)ghlApplyAppearance {
    BOOL dark = [self ghlDarkModeActive];
    self.overrideUserInterfaceStyle = GHLFollowSystemDarkEnabled() ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleLight;
    self.backgroundImage = GHLCustomBackgroundImage();
    self.tableView.backgroundView = [DYYYUtils dYYYSettingsBackgroundViewForImage:self.backgroundImage darkMode:dark];
    self.tableView.backgroundColor = self.backgroundImage ? [UIColor clearColor] : [UIColor systemGroupedBackgroundColor];
}

- (void)ghlDismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ghlRefreshOnline {
    NSString *apiKey = GHLFishAudioAPIKey();
    if (apiKey.length == 0) {
        [DYYYUtils showToast:@"在线音色要先在设置页填 Fish Audio API Key"];
        return;
    }
    [DYYYUtils showToast:@"正在拉取在线语音包…"];
    GHLFetchFishAudioVoiceListWithCompletion(^(NSArray<GHLVoicePackageInfo *> *voices, NSError *error) {
      GHLRunOnMain(^{
        // 1.0.26：记一次拉取成败，在线分区脚注不再静默失败。
        ghlOnlineFetchFailed = (error != nil);
        if (error) {
            [DYYYUtils showToast:@"拉取失败，检查 key 和网络"];
        } else {
            [DYYYUtils showToast:[NSString stringWithFormat:@"拉到 %lu 个在线音色", (unsigned long)voices.count]];
        }
        [self.tableView reloadData];
      });
    });
}

// 1.0.24：右上角 + 菜单（导入语音 / 新建文件夹 / 导出全部 / 删除文件夹）。
- (void)ghlAddButtonTapped {
    __weak __typeof(self) weakSelf = self;
    [DYYYOptionsSelectionView showWithPreferenceKey:GHL_KEY_VOICE_ADD_MENU_LAST
                                       optionsArray:@[@"导入语音文件", @"新建文件夹", @"导出全部导入的语音", @"删除文件夹…"]
                                         headerText:@"语音包"
                                     onPresentingVC:self
                                   selectionChanged:^(NSString *selectedValue) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([selectedValue isEqualToString:@"导入语音文件"]) {
            [strongSelf ghlImportVoiceFile];
        } else if ([selectedValue isEqualToString:@"新建文件夹"]) {
            [strongSelf ghlCreateFolder];
        } else if ([selectedValue isEqualToString:@"导出全部导入的语音"]) {
            GHLExportCustomVoices(strongSelf, nil);
        } else if ([selectedValue isEqualToString:@"删除文件夹…"]) {
            [strongSelf ghlDeleteFolder];
        }
    }];
}

// 1.0.24：导入语音文件（mp4/mov 转音频，其他音频直接复制；见 GHLImportVoiceAudioFileAtURL）。
- (void)ghlImportVoiceFile {
    self.voicePickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
    __weak __typeof(self) weakSelf = self;
    self.voicePickerDelegate.completionBlock = ^(NSURL *url) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      GHLImportVoiceAudioFileAtURL(url, ^(BOOL success, NSString *name) {
        (void)success;
        (void)name;
        [strongSelf.tableView reloadData];
      });
    };
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.movie", @"public.audio"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self.voicePickerDelegate;
    [self presentViewController:picker animated:YES completion:nil];
}

// 1.0.24：新建文件夹（名字查重、留用名都由 GHLCreateVoiceFolder 把关）。
- (void)ghlCreateFolder {
    __weak __typeof(self) weakSelf = self;
    DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"新建文件夹" defaultText:@"" placeholder:@"文件夹名字"];
    inputView.onConfirm = ^(NSString *text) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      GHLCreateVoiceFolder(text);
      [strongSelf.tableView reloadData];
    };
    inputView.onCancel = ^{};
    [inputView show];
}

// 1.0.24：删除文件夹（只能删自建的；里面的语音回“我的导入”）。
- (void)ghlDeleteFolder {
    NSArray<NSString *> *folders = GHLCustomVoiceFolders();
    NSMutableArray<NSString *> *deletable = [NSMutableArray array];
    for (NSString *folder in folders) {
        if (![folder isEqualToString:@"我的导入"]) [deletable addObject:folder];
    }
    if (deletable.count == 0) {
        [DYYYUtils showToast:@"还没有自建文件夹"];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [DYYYOptionsSelectionView showWithPreferenceKey:GHL_KEY_VOICE_ADD_MENU_LAST
                                       optionsArray:deletable
                                         headerText:@"删哪个文件夹？"
                                     onPresentingVC:self
                                   selectionChanged:^(NSString *selectedValue) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [DYYYBottomAlertView showAlertWithTitle:@"删掉这个文件夹？"
                                        message:[NSString stringWithFormat:@"「%@」会删掉，里面的语音回“我的导入”，文件本身不删。", selectedValue]
                                      avatarURL:nil
                               cancelButtonText:@"取消"
                              confirmButtonText:@"删除"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
            __strong __typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return;
            GHLDeleteVoiceFolder(selectedValue);
            [strongSelf2.tableView reloadData];
        }];
    }];
}

// 1.0.24：长按一行出菜单（收藏/移文件夹/分享/删除）。
- (void)ghlRowLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return;
    NSArray *categories = [self ghlVisibleCategories];
    if (indexPath.section < 0 || indexPath.section >= (NSInteger)categories.count) return;
    NSArray *packages = [self ghlPackagesInCategory:categories[indexPath.section]];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)packages.count) return;
    GHLVoicePackageInfo *info = packages[indexPath.row];
    __weak __typeof(self) weakSelf = self;
    NSMutableArray<NSString *> *options = [NSMutableArray array];
    [options addObject:GHLIsVoiceFavorite(info.voiceId) ? @"取消收藏" : @"收藏"];
    [options addObject:@"移入文件夹…"];
    // 1.0.26：在线音色长按加「下载试听音频」——存下来的只是一句固定试听句的录音，
    // 不是那个音色本身，离线不能拿它合成任意文字（诚实边界写在选项名和成功提示里）。
    if (info.source == GHLVoicePackageSourceFishAudio) {
        [options addObject:@"下载试听音频（仅一句录音）"];
    }
    if (info.source == GHLVoicePackageSourceCustom) {
        [options addObject:@"分享/导出"];
        [options addObject:@"删除"];
    }
    [DYYYOptionsSelectionView showWithPreferenceKey:GHL_KEY_VOICE_ROW_MENU_LAST
                                       optionsArray:options
                                         headerText:info.displayName
                                     onPresentingVC:self
                                   selectionChanged:^(NSString *selectedValue) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([selectedValue isEqualToString:@"收藏"] || [selectedValue isEqualToString:@"取消收藏"]) {
            GHLSetVoiceFavorite(info.voiceId, !GHLIsVoiceFavorite(info.voiceId));
            [strongSelf.tableView reloadData];
        } else if ([selectedValue isEqualToString:@"移入文件夹…"]) {
            [strongSelf ghlMoveVoiceToFolderSheet:info];
        } else if ([selectedValue isEqualToString:@"下载试听音频（仅一句录音）"]) {
            [strongSelf ghlDownloadTrialAudioForVoice:info];
        } else if ([selectedValue isEqualToString:@"分享/导出"]) {
            GHLExportCustomVoices(strongSelf, @[info.voiceId]);
        } else if ([selectedValue isEqualToString:@"删除"]) {
            [strongSelf ghlDeleteCustomVoiceConfirm:info];
        }
    }];
}

// 1.0.26：下载试听音频——把试听句合成出来，存进「我的导入」。
// 存下来的只是一句固定试听句的录音，不是那个音色本身，离线不能拿它合成任意文字。
- (void)ghlDownloadTrialAudioForVoice:(GHLVoicePackageInfo *)info {
    if (info.source != GHLVoicePackageSourceFishAudio || info.fishModelId.length == 0) return;
    __weak __typeof(self) weakSelf = self;
    // 试听句和点行试听同一句（GHLPreviewVoicePackage）。
    NSString *sample = [NSString stringWithFormat:@"顾海龙抖音语音包试听，现在是%@音色。", info.displayName];
    [DYYYUtils showToast:@"正在合成试听音频…"];
    GHLSynthesizeWithFishAudio(sample, info.fishModelId, ^(NSURL *fileURL) {
      if (!fileURL) return; // 合成失败时合成函数自己弹 toast＋记日志
      // 导入函数按文件名取名：先拷一份带音色名的临时文件，导入后名字才好看。
      NSString *friendlyName = [NSString stringWithFormat:@"%@ 试听.mp3", info.displayName];
      NSURL *namedURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:friendlyName];
      [[NSFileManager defaultManager] removeItemAtURL:namedURL error:nil];
      NSError *copyError = nil;
      if (![[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:namedURL error:&copyError]) {
          GHLLog(@"语音包下载试听：改名复制失败 %@，直接导原文件", copyError.localizedDescription);
          namedURL = fileURL; // 复制失败就直接导原文件，名字难看一点而已
      }
      GHLRunOnMain(^{
        GHLImportVoiceAudioFileAtURL(namedURL, ^(BOOL success, NSString *name) {
          if (!success) return;
          GHLLog(@"语音包下载试听：「%@」已存进「我的导入」（只是一句试听录音，不是音色本身，离线不能合成任意文字）", name ?: info.displayName);
          [DYYYUtils showToast:@"已存进「我的导入」：只是一句试听录音，不是音色本身，离线不能合成任意文字"];
          __strong __typeof(weakSelf) strongSelf = weakSelf;
          if (strongSelf) [strongSelf.tableView reloadData];
        });
      });
    });
}

// 1.0.24：移入文件夹（选“移出文件夹”就回默认分类/我的导入）。
- (void)ghlMoveVoiceToFolderSheet:(GHLVoicePackageInfo *)info {
    __weak __typeof(self) weakSelf = self;
    NSMutableArray<NSString *> *options = [NSMutableArray arrayWithObject:@"移出文件夹"];
    [options addObjectsFromArray:GHLCustomVoiceFolders()];
    [DYYYOptionsSelectionView showWithPreferenceKey:GHL_KEY_VOICE_ROW_MENU_LAST
                                       optionsArray:options
                                         headerText:[NSString stringWithFormat:@"把「%@」移到…", info.displayName]
                                     onPresentingVC:self
                                   selectionChanged:^(NSString *selectedValue) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([selectedValue isEqualToString:@"移出文件夹"]) {
            GHLMoveVoiceToFolder(info.voiceId, nil);
        } else {
            GHLMoveVoiceToFolder(info.voiceId, selectedValue);
        }
        [strongSelf.tableView reloadData];
    }];
}

// 1.0.24：删导入的语音（记录 + 文件一起删，确认后才动手）。
- (void)ghlDeleteCustomVoiceConfirm:(GHLVoicePackageInfo *)info {
    __weak __typeof(self) weakSelf = self;
    [DYYYBottomAlertView showAlertWithTitle:@"删掉这个语音？"
                                    message:[NSString stringWithFormat:@"「%@」会从语音包和文件里一起删掉。", info.displayName]
                                  avatarURL:nil
                           cancelButtonText:@"取消"
                          confirmButtonText:@"删除"
                               cancelAction:nil
                                closeAction:nil
                              confirmAction:^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        GHLDeleteCustomVoice(info.voiceId);
        [strongSelf.tableView reloadData];
    }];
}

// 当前要显示的列表（有搜索词就按搜索结果，否则全量）
- (NSArray<GHLVoicePackageInfo *> *)ghlVisiblePackages {
    return GHLSearchVoicePackages(self.searchText);
}

- (NSArray<NSString *> *)ghlVisibleCategories {
    NSMutableArray<NSString *> *categories = [NSMutableArray array];
    // 1.0.4：收藏置顶一个分区（只有收藏了、且收藏的音色还在当前列表里才出现）。
    NSSet<NSString *> *favorites = GHLVoiceFavorites();
    if (favorites.count > 0) {
        for (GHLVoicePackageInfo *info in [self ghlVisiblePackages]) {
            if ([favorites containsObject:info.voiceId]) {
                [categories addObject:@"★ 收藏"];
                break;
            }
        }
    }
    for (GHLVoicePackageInfo *info in [self ghlVisiblePackages]) {
        if (![categories containsObject:info.category]) [categories addObject:info.category];
    }
    // 1.0.26：自建文件夹空着也显示分区（以前只从实际语音里收分区，空文件夹永不现身，
    // 建完看着像没建成）；搜索时不并入，免得搜的时候冒出一堆空分区。
    if (self.searchText.length == 0) {
        for (NSString *folder in GHLCustomVoiceFolders()) {
            if (![categories containsObject:folder]) [categories addObject:folder];
        }
    }
    return categories;
}

- (NSArray<GHLVoicePackageInfo *> *)ghlPackagesInCategory:(NSString *)category {
    NSMutableArray<GHLVoicePackageInfo *> *result = [NSMutableArray array];
    NSSet<NSString *> *favorites = GHLVoiceFavorites();
    for (GHLVoicePackageInfo *info in [self ghlVisiblePackages]) {
        if ([category isEqualToString:@"★ 收藏"]) {
            if ([favorites containsObject:info.voiceId]) [result addObject:info];
        } else if ([info.category isEqualToString:category]) {
            [result addObject:info];
        }
    }
    return result;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAX(1, [self ghlVisibleCategories].count);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *categories = [self ghlVisibleCategories];
    if (categories.count == 0) return 0;
    return [self ghlPackagesInCategory:categories[section]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *categories = [self ghlVisibleCategories];
    if (categories.count == 0) return nil;
    NSString *category = categories[section];
    if ([category isEqualToString:@"★ 收藏"]) return @"★ 收藏";
    if ([category isEqualToString:@"在线"]) return @"在线（Fish Audio，需 key）";
    return category;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSArray *categories = [self ghlVisibleCategories];
    if (categories.count == 0) return nil;
    if ([categories[section] isEqualToString:@"★ 收藏"]) return @"点 ★ 取消收藏；点行选中并试听。";
    if ([categories[section] isEqualToString:@"在线"]) {
        NSString *apiKey = GHLFishAudioAPIKey();
        if (apiKey.length == 0) return @"在线音色要先在设置页填写 Fish Audio API Key，填完点右上角“刷新在线”拉取。";
        // 1.0.26：上次拉取失败时脚注留一行，不再静默失败。
        if (ghlOnlineFetchFailed) return @"上次拉取在线列表失败了，请检查网络和 Key，点右上角“刷新在线”再试一次。";
        return nil;
    }
    if ([categories[section] isEqualToString:@"内置"]) return nil;
    // 1.0.24：我的导入 / 自建文件夹——导入的语音点一下就播放（不能合成文字）。
    return @"导入的语音点一下就播放（不能用来合成文字）；长按可移文件夹、分享或删除。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GHLVoicePackageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    NSArray *categories = [self ghlVisibleCategories];
    GHLVoicePackageInfo *info = [self ghlPackagesInCategory:categories[indexPath.section]][indexPath.row];
    cell.textLabel.text = info.displayName;
    cell.detailTextLabel.text = info.voiceId;
    // 1.0.24：导入的语音副标题显示文件名 + 大小（跟图层抖音一样显示大小）。
    if (info.source == GHLVoicePackageSourceCustom) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [info.audioFilePath lastPathComponent], GHLFileSizeText(info.audioFilePath)];
    }
    NSString *selectedId = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_VOICE_PACKAGE_ID];
    BOOL selected = [info.voiceId isEqualToString:selectedId];
    // 统一视觉：选中行名字用金色；行底色跟随深色/自定义背景。
    BOOL dark = [self ghlDarkModeActive];
    cell.backgroundColor = [DYYYUtils dYYYSettingsCellBackgroundColorForBackgroundImage:self.backgroundImage darkMode:dark];
    cell.textLabel.textColor = selected ? [DYYYUtils dYYYGoldAccentColor] : [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
    cell.detailTextLabel.textColor = [DYYYUtils dYYYSettingsSecondaryTextColorDarkMode:dark];
    // 1.0.4 收藏：右侧 ✓（已选）+ ★/☆ 按钮（点一下收藏/取消收藏，不影响点行选中）。
    UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 76, 44)];
    UILabel *checkLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 24, 44)];
    checkLabel.text = @"✓";
    checkLabel.font = [UIFont systemFontOfSize:17];
    checkLabel.textColor = [DYYYUtils dYYYGoldAccentColor];
    checkLabel.textAlignment = NSTextAlignmentCenter;
    // 1.0.24：导入的录音不能设为合成用的音色，不打 ✓。
    checkLabel.hidden = !selected || info.source == GHLVoicePackageSourceCustom;
    [accessory addSubview:checkLabel];
    UIButton *starButton = [UIButton buttonWithType:UIButtonTypeSystem];
    starButton.frame = CGRectMake(28, 0, 44, 44);
    BOOL favorited = GHLIsVoiceFavorite(info.voiceId);
    [starButton setTitle:favorited ? @"★" : @"☆" forState:UIControlStateNormal];
    starButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [starButton setTitleColor:favorited ? [DYYYUtils dYYYGoldAccentColor] : [UIColor grayColor] forState:UIControlStateNormal];
    starButton.tag = indexPath.section * 10000 + indexPath.row;
    [starButton addTarget:self action:@selector(ghlFavoriteButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [accessory addSubview:starButton];
    cell.accessoryView = accessory;
    return cell;
}

// 1.0.4：点 ★ 收藏/取消收藏（收藏的固定排在最前面）。
- (void)ghlFavoriteButtonTapped:(UIButton *)sender {
    NSInteger section = sender.tag / 10000;
    NSInteger row = sender.tag % 10000;
    NSArray *categories = [self ghlVisibleCategories];
    if (section < 0 || section >= (NSInteger)categories.count) return;
    NSArray *packages = [self ghlPackagesInCategory:categories[section]];
    if (row < 0 || row >= (NSInteger)packages.count) return;
    GHLVoicePackageInfo *info = packages[row];
    GHLSetVoiceFavorite(info.voiceId, !GHLIsVoiceFavorite(info.voiceId));
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *categories = [self ghlVisibleCategories];
    GHLVoicePackageInfo *info = [self ghlPackagesInCategory:categories[indexPath.section]][indexPath.row];
    if (info.source == GHLVoicePackageSourceCustom) {
        // 1.0.24：导入的录音点一下就播放，不设为合成用的音色（录音合成不了文字）。
        GHLPreviewVoicePackage(info.voiceId);
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:info.voiceId forKey:GHL_KEY_VOICE_PACKAGE_ID];
    [tableView reloadData];
    GHLPreviewVoicePackage(info.voiceId);
}

#pragma mark UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end

void GHLPresentVoicePackageManagerFromViewController(UIViewController *viewController) {
    if (!viewController) return;
    GHLRunOnMain(^{
      GHLVoicePackageManagerViewController *managerVC = [[GHLVoicePackageManagerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
      UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:managerVC];
      nav.navigationBar.prefersLargeTitles = YES; // 统一视觉：跟设置主页一样用大标题
      [viewController presentViewController:nav animated:YES completion:nil];
      GHLLog(@"语音包管理：已打开管理器");
    });
}

void GHLProbeLiveVoiceSender(void) {
    NSArray<NSString *> *classNames = @[
        @"IESLiveVoiceSender", @"IESLiveVoiceFragment", @"TTSVoiceModel", @"DYZSVoiceManagerView",
        @"TTSRemoteVoiceService", @"RemoteVoiceService", @"AWEIMVoiceMessageCell", @"AWELiveVoiceInputView"
    ];
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSString *name in classNames) {
        if (NSClassFromString(name)) [found addObject:name];
    }
    GHLLog(@"语音包直播探针：抖音里找到 %lu 个相关类：%@", (unsigned long)found.count, found);
    if (found.count == 0) {
        GHLLog(@"语音包直播探针：没找到直播发语音的类，往直播里发语音目前做不了（不注入、不猜）");
    } else {
        GHLLog(@"语音包直播探针：只记录类存在，不 hook、不发包，发送流程待真机日志进一步验证");
    }
}

#pragma mark - (32)-(43) xuu 行为参考功能（代码全部自己写）

static NSInteger ghlAutoLikeCount = 0;
static NSTimer *ghlHousekeepingTimer = nil;
static NSTimeInterval ghlLiveEnteredTime = 0;
static UILabel *ghlLiveDurationLabel = nil;
static BOOL ghlLiveRecording = NO;
static NSTimeInterval ghlRedPacketLastTap = 0;
static NSTimeInterval ghlLotteryLastTap = 0;
static BOOL ghlLiveAudioMutedByUs = NO;
static BOOL ghlFakeStatsLogged = NO;

static UIViewController *GHLTopViewController(void) {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    if ([vc isKindOfClass:[UITabBarController class]]) vc = ((UITabBarController *)vc).selectedViewController ?: vc;
    return vc;
}

BOOL GHLIsInLiveRoom(void) {
    UIViewController *vc = GHLTopViewController();
    if (!vc) return NO;
    NSString *name = NSStringFromClass([vc class]);
    if ([name rangeOfString:@"Live"].location != NSNotFound) return YES;
    // 兜底：顶层 VC 的子 VC 里找含 Live 的
    for (UIViewController *child in vc.childViewControllers) {
        if ([NSStringFromClass([child class]) rangeOfString:@"Live"].location != NSNotFound) return YES;
    }
    return NO;
}

#pragma mark (32) 自动点赞

static BOOL GHLIsCurrentVideoLiked(void) {
    __block BOOL liked = NO;
    GHLRunOnMain(^{
      UIViewController *controller = [DYYYFloatingButtonCoordinator currentInteractionController];
      if (!controller) return;
      NSMutableArray *stack = [NSMutableArray arrayWithObject:controller.view];
      while (stack.count > 0 && !liked) {
          UIView *view = stack.lastObject;
          [stack removeLastObject];
          if ([view isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")] &&
              [((AWEFeedVideoButton *)view).accessibilityLabel isEqualToString:@"点赞"]) {
              liked = ((UIButton *)view).selected;
              break;
          }
          [stack addObjectsFromArray:view.subviews];
      }
    });
    return liked;
}

void GHLMaybeAutoLike(void) {
    if (!GHLGetBool(GHL_KEY_AUTO_LIKE)) return;
    NSInteger maxCount = [GHLGetString(GHL_KEY_AUTO_LIKE_MAX) integerValue];
    if (maxCount <= 0) maxCount = 100;
    if (ghlAutoLikeCount >= maxCount) {
        GHLLog(@"自动点赞：已到本会话上限 %ld，不再自动点", (long)maxCount);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1500 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      @try {
          if (GHLIsCurrentVideoLiked()) return; // 已点赞的不重复点（避免点一下变取消）
          UIViewController *controller = [DYYYFloatingButtonCoordinator currentInteractionController];
          if ([controller respondsToSelector:@selector(performLikeAction)]) {
              [(AWEPlayInteractionViewController *)controller performLikeAction];
              ghlAutoLikeCount++;
              GHLLog(@"自动点赞：已点第 %ld 个", (long)ghlAutoLikeCount);
          }
      } @catch (__unused NSException *exception) {
      }
    });
}

#pragma mark (33)(39) 直播间输入框发消息（尽力找输入框+发送按钮）

void GHLTrySendLiveMessage(NSString *text) {
    if (text.length == 0) return;
    GHLRunOnMain(^{
      @try {
          UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
          NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
          UITextField *textField = nil;
          UITextView *textView = nil;
          UIButton *sendButton = nil;
          while (stack.count > 0) {
              UIView *view = stack.lastObject;
              [stack removeLastObject];
              if (!textField && [view isKindOfClass:[UITextField class]]) {
                  NSString *placeholder = ((UITextField *)view).placeholder ?: @"";
                  if ([placeholder containsString:@"说"] || [placeholder containsString:@"聊"] || [placeholder containsString:@"评论"] || placeholder.length == 0) {
                      textField = (UITextField *)view;
                  }
              }
              if (!textView && [view isKindOfClass:[UITextView class]]) textView = (UITextView *)view;
              if (!sendButton && [view isKindOfClass:[UIButton class]]) {
                  NSString *title = ((UIButton *)view).titleLabel.text ?: @"";
                  if ([title isEqualToString:@"发送"]) sendButton = (UIButton *)view;
              }
              [stack addObjectsFromArray:view.subviews];
          }
          if (textField) {
              textField.text = text;
              [textField sendActionsForControlEvents:UIControlEventEditingChanged];
          } else if (textView) {
              textView.text = text;
          } else {
              GHLLog(@"直播间发消息：没找到输入框，消息没发出去");
              return;
          }
          if (sendButton) {
              [sendButton sendActionsForControlEvents:UIControlEventTouchUpInside];
              GHLLog(@"直播间发消息：已发“%@”", text);
          } else {
              GHLLog(@"直播间发消息：已填文字但没找到发送按钮，请手动点发送");
          }
      } @catch (__unused NSException *exception) {
      }
    });
}

#pragma mark (33) 自动抢红包 / (34) 自动开直播抽奖

static void GHLScanAndTapButtonContaining(NSString *keyword, NSTimeInterval *lastTap, NSTimeInterval minInterval, NSString *logName) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - *lastTap < minInterval) return;
    __block UIButton *target = nil;
    GHLRunOnMain(^{
      UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
      NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
      while (stack.count > 0 && !target) {
          UIView *view = stack.lastObject;
          [stack removeLastObject];
          if ([view isKindOfClass:[UIButton class]] && !view.hidden && view.alpha > 0.05 && view.window) {
              UIButton *button = (UIButton *)view;
              NSString *title = button.titleLabel.text ?: @"";
              NSString *label = button.accessibilityLabel ?: @"";
              if ([title containsString:keyword] || [label containsString:keyword]) target = button;
          }
          [stack addObjectsFromArray:view.subviews];
      }
    });
    if (!target) return;
    *lastTap = now;
    NSString *delayText = GHLGetString(GHL_KEY_RED_PACKET_DELAY);
    NSTimeInterval delay = delayText.length > 0 ? [delayText doubleValue] : 1.0;
    if (delay < 0) delay = 0;
    if (delay > 10) delay = 10;
    GHLLog(@"%@：发现按钮，%.1f 秒后点", logName, delay);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [target sendActionsForControlEvents:UIControlEventTouchUpInside];
      GHLLog(@"%@：已点", logName);
      if ([logName isEqualToString:@"自动抢红包"] && GHLGetBool(GHL_KEY_RED_PACKET_AUTO_REPLY)) {
          NSString *reply = GHLGetString(GHL_KEY_RED_PACKET_REPLY_TEXT);
          if (reply.length == 0) reply = @"谢谢老板";
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GHLTrySendLiveMessage(reply);
          });
      }
    });
}

#pragma mark (38) 自定义底栏

static void GHLApplyCustomTabBar(void) {
    NSString *hiddenText = GHLGetString(GHL_KEY_HIDDEN_TABS);
    if (hiddenText.length == 0) return;
    NSMutableArray<NSString *> *hiddenTabs = [NSMutableArray array];
    for (NSString *item in [hiddenText componentsSeparatedByString:@","]) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [hiddenTabs addObject:trimmed];
    }
    if (hiddenTabs.count == 0) return;
    GHLRunOnMain(^{
      UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
      NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
      while (stack.count > 0) {
          UIView *view = stack.lastObject;
          [stack removeLastObject];
          if ([view isKindOfClass:[UITabBar class]]) {
              for (UIView *tabButton in view.subviews) {
                  NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                  GHLCollectLabelsInView(tabButton, labels);
                  for (UILabel *label in labels) {
                      if (label.text.length > 0 && [hiddenTabs containsObject:label.text]) {
                          tabButton.hidden = YES;
                          GHLLog(@"自定义底栏：已隐藏“%@”", label.text);
                          break;
                      }
                  }
              }
              return;
          }
          [stack addObjectsFromArray:view.subviews];
      }
    });
}

#pragma mark (39) 直播时长 / 直播录制

void GHLUpdateLiveDurationLabel(void) {
    BOOL inLive = GHLIsInLiveRoom();
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (inLive && ghlLiveEnteredTime == 0) {
        ghlLiveEnteredTime = now;
        GHLLog(@"直播时长：进入直播间，开始计时");
        // (39) 进直播间发消息：开关开了就发一次设置好的内容
        if (GHLGetBool(GHL_KEY_LIVE_SEND_MESSAGE)) {
            NSString *message = GHLGetString(GHL_KEY_LIVE_SEND_MESSAGE_TEXT);
            if (message.length > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                  if (GHLIsInLiveRoom()) GHLTrySendLiveMessage(message);
                });
            }
        }
    } else if (!inLive && ghlLiveEnteredTime != 0) {
        ghlLiveEnteredTime = 0;
        [ghlLiveDurationLabel removeFromSuperview];
        ghlLiveDurationLabel = nil;
        GHLLog(@"直播时长：离开直播间，计时清零");
    }
    if (inLive && GHLGetBool(GHL_KEY_LIVE_DURATION)) {
        GHLRunOnMain(^{
          UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
          if (!ghlLiveDurationLabel) {
              ghlLiveDurationLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 64, 130, 26)];
              ghlLiveDurationLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
              ghlLiveDurationLabel.textColor = [UIColor colorWithRed:245 / 255.0 green:215 / 255.0 blue:110 / 255.0 alpha:1.0];
              ghlLiveDurationLabel.font = [UIFont boldSystemFontOfSize:13];
              ghlLiveDurationLabel.textAlignment = NSTextAlignmentCenter;
              ghlLiveDurationLabel.layer.cornerRadius = 13;
              ghlLiveDurationLabel.layer.masksToBounds = YES;
              [window addSubview:ghlLiveDurationLabel];
          }
          NSInteger elapsed = (NSInteger)([[NSDate date] timeIntervalSince1970] - ghlLiveEnteredTime);
          ghlLiveDurationLabel.text = [NSString stringWithFormat:@"直播 %02ld:%02ld", (long)(elapsed / 60), (long)(elapsed % 60)];
        });
    }
    // 直播录制：进直播间开录，离开停录并弹保存预览
    if (inLive && GHLGetBool(GHL_KEY_LIVE_RECORD) && !ghlLiveRecording) {
        ghlLiveRecording = YES;
        [[RPScreenRecorder sharedRecorder] startRecordingWithHandler:^(NSError *error) {
          if (error) {
              GHLLog(@"直播录制：开始失败 %@", error.localizedDescription);
              ghlLiveRecording = NO;
          } else {
              GHLLog(@"直播录制：已开始");
          }
        }];
    } else if (!inLive && ghlLiveRecording) {
        ghlLiveRecording = NO;
        [[RPScreenRecorder sharedRecorder] stopRecordingWithHandler:^(RPPreviewViewController *previewVC, NSError *error) {
          if (error || !previewVC) {
              GHLLog(@"直播录制：停止失败 %@", error.localizedDescription);
              return;
          }
          previewVC.modalPresentationStyle = UIModalPresentationFullScreen;
          [GHLTopViewController() presentViewController:previewVC animated:YES completion:nil];
          GHLLog(@"直播录制：已停止，弹出保存预览");
        }];
    }
}

#pragma mark (42) 改数字显示

static NSString *GHLFormatFakeCount(NSString *raw) {
    if (raw.length == 0) return nil;
    // 用户填纯数字就直接显示；填了带单位的也原样显示
    return raw;
}

void GHLApplyFakeStatsInView(UIView *view) {
    if (!GHLGetBool(GHL_KEY_FAKE_STATS)) return;
    // 节流：最多 2 秒跑一次（viewDidLayoutSubviews 调用很频繁）
    static NSTimeInterval lastRun = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastRun < 2.0) return;
    lastRun = now;
    NSString *fakeLike = GHLFormatFakeCount(GHLGetString(GHL_KEY_FAKE_LIKE_COUNT));
    NSString *fakePlay = GHLFormatFakeCount(GHLGetString(GHL_KEY_FAKE_PLAY_COUNT));
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count > 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        // 点赞按钮里的数字标签 → 改成用户填的点赞数
        if (fakeLike && [candidate isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")] &&
            [((AWEFeedVideoButton *)candidate).accessibilityLabel isEqualToString:@"点赞"]) {
            NSMutableArray<UILabel *> *labels = [NSMutableArray array];
            GHLCollectLabelsInView(candidate, labels);
            for (UILabel *label in labels) {
                if (label.text.length > 0) {
                    label.text = fakeLike;
                    if (!ghlFakeStatsLogged) GHLLog(@"改数字显示：点赞数已改成 %@", fakeLike);
                }
            }
        }
        // 含“播放”的标签 → 把前面的数字换成用户填的播放数
        if (fakePlay) {
            for (UIView *subview in candidate.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)subview;
                    if (label.text.length > 0 && [label.text containsString:@"播放"]) {
                        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.,万千"];
                        NSRange range = [label.text rangeOfCharacterFromSet:digits];
                        if (range.location != NSNotFound) {
                            label.text = [label.text stringByReplacingCharactersInRange:NSMakeRange(0, range.location + range.length) withString:fakePlay];
                            if (!ghlFakeStatsLogged) GHLLog(@"改数字显示：播放数已改成 %@", fakePlay);
                        }
                    }
                }
            }
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
    // 直播间人数：只在直播间里找含“人”的标签改
    if (GHLGetBool(GHL_KEY_FAKE_LIVE_USER_COUNT) && GHLIsInLiveRoom()) {
        NSString *fakeCount = GHLFormatFakeCount(GHLGetString(GHL_KEY_FAKE_LIVE_USER_COUNT_VALUE));
        if (fakeCount) {
            UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
            NSMutableArray *liveStack = [NSMutableArray arrayWithObject:window];
            while (liveStack.count > 0) {
                UIView *candidate = liveStack.lastObject;
                [liveStack removeLastObject];
                if ([candidate isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)candidate;
                    if (label.text.length > 0 && [label.text containsString:@"人"] && label.text.length < 20) {
                        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.,万千"];
                        NSRange range = [label.text rangeOfCharacterFromSet:digits];
                        if (range.location != NSNotFound) {
                            label.text = [label.text stringByReplacingCharactersInRange:NSMakeRange(0, range.location + range.length) withString:fakeCount];
                            if (!ghlFakeStatsLogged) GHLLog(@"改数字显示：直播间人数已改成 %@", fakeCount);
                        }
                    }
                }
                [liveStack addObjectsFromArray:candidate.subviews];
            }
        }
    }
    ghlFakeStatsLogged = YES;
}

#pragma mark (37) 双击下载（带进度）

void GHLDownloadCurrentVideoWithProgress(void) {
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    if (!model || !model.video) {
        [DYYYUtils showToast:@"没找到当前视频"];
        return;
    }
    NSURL *videoURL = nil;
    NSURL *audioURL = nil;
    if (model.video.h264URL && model.video.h264URL.originURLList.count > 0) {
        videoURL = [NSURL URLWithString:model.video.h264URL.originURLList.firstObject];
    } else if (model.video.playURL && model.video.playURL.originURLList.count > 0) {
        videoURL = [NSURL URLWithString:model.video.playURL.originURLList.firstObject];
    }
    if (model.music && model.music.playURL && model.music.playURL.originURLList.count > 0) {
        audioURL = [NSURL URLWithString:model.music.playURL.originURLList.firstObject];
    }
    if (!videoURL) {
        [DYYYUtils showToast:@"拿不到视频地址"];
        return;
    }
    __block NSInteger lastLoggedPercent = -1;
    [DYYYUtils showToast:@"开始下载当前视频…"];
    [DYYYManager downloadMediaWithProgress:videoURL
                                 mediaType:MediaTypeVideo
                                     audio:audioURL
                                  progress:^(float progress) {
                                    if (!GHLGetBool(GHL_KEY_DOWNLOAD_PROGRESS)) return;
                                    NSInteger percent = (NSInteger)(progress * 100);
                                    if (percent - lastLoggedPercent >= 25 || percent == 100) {
                                        lastLoggedPercent = percent;
                                        GHLLog(@"下载进度：%ld%%", (long)percent);
                                    }
                                  }
                                completion:^(BOOL success, NSURL *fileURL) {
                                  GHLLog(@"双击下载：%@", success ? @"成功" : @"失败");
                                  GHLRunOnMain(^{
                                    [DYYYUtils showToast:success ? @"视频已保存" : @"下载失败"];
                                  });
                                }];
}

#pragma mark (38) 界面缩放 / 深色键盘

void GHLApplyInterfaceScaleInView(UIView *view) {
    if (!GHLGetBool(GHL_KEY_INTERFACE_SCALE)) {
        // 开关关了就恢复原大小（只处理已经缩放过的）
        NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
        while (stack.count > 0) {
            UIView *candidate = stack.lastObject;
            [stack removeLastObject];
            if ([candidate isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")] && !CGAffineTransformIsIdentity(candidate.transform)) {
                candidate.transform = CGAffineTransformIdentity;
            }
            [stack addObjectsFromArray:candidate.subviews];
        }
        return;
    }
    CGFloat scale = [GHLGetString(GHL_KEY_INTERFACE_SCALE_VALUE) floatValue];
    if (scale < 0.5f) scale = 0.5f;
    if (scale > 2.0f) scale = 2.0f;
    if (scale == 0) scale = 1.0f;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count > 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        if ([candidate isKindOfClass:NSClassFromString(@"AWEFeedVideoButton")]) {
            candidate.transform = CGAffineTransformMakeScale(scale, scale);
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
}

void GHLApplyDarkKeyboardInView(UIView *view) {
    if (!GHLGetBool(GHL_KEY_DARK_KEYBOARD)) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count > 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        if ([candidate isKindOfClass:[UITextField class]]) {
            ((UITextField *)candidate).keyboardAppearance = UIKeyboardAppearanceDark;
        } else if ([candidate isKindOfClass:[UITextView class]]) {
            ((UITextView *)candidate).keyboardAppearance = UIKeyboardAppearanceDark;
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
    GHLLog(@"深色键盘：已把输入框键盘改成深色");
}

#pragma mark (35)(36)(41) 探针（只记日志，不 hook、不猜实现）

void GHLProbePrivacyFeatures(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *typing = [NSMutableArray array];
    NSMutableArray<NSString *> *readReceipt = [NSMutableArray array];
    NSMutableArray<NSString *> *burn = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name containsString:@"Typing"]) {
            if (typing.count < 20) [typing addObject:name];
        } else if ([name containsString:@"ReadReceipt"] || [name containsString:@"ReadStatus"]) {
            if (readReceipt.count < 20) [readReceipt addObject:name];
        } else if ([name containsString:@"Burn"] || [name containsString:@"Disappear"] || [name containsString:@"SecretChat"]) {
            if (burn.count < 20) [burn addObject:name];
        }
    }
    free(classes);
    GHLLog(@"隐私探针：正在输入相关 %lu 个：%@", (unsigned long)typing.count, typing);
    GHLLog(@"隐私探针：已读回执相关 %lu 个：%@", (unsigned long)readReceipt.count, readReceipt);
    GHLLog(@"隐私探针：阅后即焚相关 %lu 个：%@", (unsigned long)burn.count, burn);
    GHLLog(@"隐私探针：以上只做记录；隐藏正在输入/已读回执/防阅后即焚没有可验证的 hook 点，目前做不了，开关先留着等日志");
}

void GHLProbeCommentVoice(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (([name containsString:@"Comment"] || [name containsString:@"Voice"]) && ([name containsString:@"Audio"] || [name containsString:@"Voice"])) {
            if (hits.count < 30) [hits addObject:name];
        }
    }
    free(classes);
    GHLLog(@"评论语音探针：疑似评论语音相关类 %lu 个：%@", (unsigned long)hits.count, hits);
    if (hits.count == 0) {
        GHLLog(@"评论语音探针：没找到评论语音的类，播放/保存做不了，开关先留着等日志");
    } else {
        GHLLog(@"评论语音探针：只记录类存在，播放/保存流程待真机日志进一步验证");
    }
}

void GHLProbeLiveRoom(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name hasPrefix:@"AWELive"] || [name hasPrefix:@"IESLive"]) {
            if (hits.count < 30) [hits addObject:name];
        }
    }
    free(classes);
    GHLLog(@"直播间探针：AWELive/IESLive 类 %lu 个（前 30）：%@", (unsigned long)hits.count, hits);
}

// 1.0.2 语音四项探针：语音消息转发 / 设置语音秒数 / 替换语音评论 / 保存语音评论。
// 只做运行期类/方法/属性 introspection 并记日志，不注入、不改行为、不发包。
// 已知：AWECommentAudioModel 有 content 和 audioFilePath（本地文件路径，-11.log 证实）；
// AWEIMVoiceMessageCell 类存在但转发/发送方法未知；语音录制时长接口、评论发语音接口未知。
void GHLProbeVoiceFeatures(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    NSArray<NSString *> *keywords = @[ @"VoiceMessage", @"AudioMessage", @"IMAudio", @"VoiceRecorder", @"AudioRecorder", @"CommentAudio" ];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        for (NSString *kw in keywords) {
            if ([name containsString:kw]) {
                if (hits.count < 30) [hits addObject:name];
                break;
            }
        }
    }
    free(classes);
    GHLLog(@"语音四项探针：疑似语音相关类 %lu 个（前 30）：%@", (unsigned long)hits.count, hits);

    // AWECommentAudioModel 的属性清单（评论语音有没有音频地址，看这里）
    Class audioModelClass = NSClassFromString(@"AWECommentAudioModel");
    if (audioModelClass) {
        unsigned int propCount = 0;
        objc_property_t *props = class_copyPropertyList(audioModelClass, &propCount);
        NSMutableArray<NSString *> *propNames = [NSMutableArray array];
        for (unsigned int i = 0; i < propCount; i++) {
            [propNames addObject:[NSString stringWithUTF8String:property_getName(props[i])]];
        }
        free(props);
        GHLLog(@"语音四项探针：AWECommentAudioModel 属性 %lu 个：%@", (unsigned long)propNames.count, propNames);
    } else {
        GHLLog(@"语音四项探针：AWECommentAudioModel 类不存在，评论语音保存/替换做不了");
    }

    // AWEIMVoiceMessageCell 的方法清单（私信语音转发有没有现成入口，看这里）
    Class voiceCellClass = NSClassFromString(@"AWEIMVoiceMessageCell");
    if (voiceCellClass) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(voiceCellClass, &methodCount);
        NSMutableArray<NSString *> *methodNames = [NSMutableArray array];
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *selName = NSStringFromSelector(method_getName(methods[i]));
            if ([selName containsString:@"forward"] || [selName containsString:@"Forward"] || [selName containsString:@"send"] || [selName containsString:@"Send"] || [selName containsString:@"share"] || [selName containsString:@"Share"]) {
                if (methodNames.count < 20) [methodNames addObject:selName];
            }
        }
        free(methods);
        GHLLog(@"语音四项探针：AWEIMVoiceMessageCell 转发/发送相关方法 %lu 个：%@", (unsigned long)methodNames.count, methodNames);
    } else {
        GHLLog(@"语音四项探针：AWEIMVoiceMessageCell 类不存在，语音消息转发做不了");
    }

    GHLLog(@"语音四项探针：只记录类/方法存在，转发/秒数/替换/保存流程待真机日志进一步验证");
}

#pragma mark - 1.0.18 浮动按钮＋卡片面板（快手「人民的快手」式入口，只学样子与行为）

// 参照视频（皇上 22:40 发的快手录屏）：视频页左上角一个红色浮动钮，点开一张深色毛玻璃卡片，
// 顶上标题＋搜索框，下面两列按钮＋底下「完成」。我们用自己的龙头图＋金色视觉
// （长按网格／关于页那套：深色毛玻璃、圆角 16/24、金边金图标），绝不抄它的代码／资源。
// 1.0.19：浮动钮＋卡片面板（設定頁本身做成卡片）。
// 皇上 2026-11-15 00:01 確認：點龍頭浮動鈕彈出的卡片，不要 1.0.18 那張深色導航卡片
// （通用設置／首頁／朋友／消息／我／播放互動／診斷反饋／關於 8 個按鈕＋搜索＋完成），
// 要直接就是設定頁本身做成卡片——像皇上發的設定頁截圖那樣：白卡頭＋搜索框＋分區列表。
// 做法：卡片裡嵌一個 UINavigationController，根就是現成的 DYYYSettingViewController
// （不重寫列表，否則兩份列表會漂移；分區行點了在卡片內的導航棧上推子頁）。
// 卡片放在自己的 UIWindow（level alert）裡，rootVC 是個空殼宿主 VC，
// 子頁導航棧都在卡片內，不動 feed 的 VC 層級；點卡片外／點「關閉」關掉。
// 點按回調掛在 GHLFeatures 的類方法上（見 @implementation GHLFeatures 的 ghl_floatPanel*）。
// 1.0.20：遮罩手勢只認卡片外（delegate＋cancelsTouchesInView=NO），卡片改深色毛玻璃＋
// 底部「完成」鈕（導航棧縮進 10pt 露出毛玻璃邊框）；所有入口都開卡片（見 GHLShowFloatPanel）；
// 卡片記住上次停的那頁（GHLSave/RestoreFloatPanelLastPage）。
// 1.0.21：卡片加了 8 按鍵首頁（通用設置／首頁／朋友／消息／我／播放互動／診斷反饋／關於）。
// 1.0.22：卡片玻璃重做（遮罩 0.12、ExtraLight 糊、tint 0.06、卡片收小）。
// 1.0.23：首頁拿掉、卡片改回照片那款 A——根就是設定頁本身、淺色實心卡（見下面）。

static UIButton *ghlFloatPanelButton = nil;
static UIWindow *ghlFloatPanelWindow = nil;            // 卡片自己的窗口（不搶 keyWindow）
static UIViewController *ghlFloatPanelHostVC = nil;    // 窗口的 rootVC（空殼，view 就是遮罩）
static UIView *ghlFloatPanelCard = nil;                // 圓角卡片
static UINavigationController *ghlFloatPanelNav = nil; // 卡片內的導航棧（根＝設定頁）
static BOOL ghlFloatPanelOpen = NO;
static id ghlFloatPanelOrientationToken = nil; // 轉屏重排卡片（只註冊一次）
// 1.0.23：卡片改回照片那款 A——浅色实心卡，不追毛玻璃：糊和 tint 整个拿掉，
// 卡片底就是一层实心浅灰（照片里卡片外框那个灰）；字靠不透明的内页保证清楚。
static UIButton *ghlFloatPanelDoneButton = nil;         // 卡片底部「完成」按钮（金色 pill）
// 1.0.21：卡片共用的设置页实例——1.0.23 起它就是卡片导航栈的根（设置页本身）；
// 关于页拿它当配置三行的帮手。只建一份（设置页建起来不便宜）；推上去时若已在栈里就回到它，不重复推。
static DYYYSettingViewController *ghlFloatPanelSharedSettingsVC = nil;

// 1.0.20：卡片内边距（导航栈缩进 10pt，实心卡边框露出来）＋底部「完成」条高 64pt。
static const CGFloat kGHLFloatPanelNavInset = 10;
static const CGFloat kGHLFloatPanelDoneBarHeight = 64;
// 1.0.20：卡片记住上次停在哪一页（偏好里记顶页标识；恢复失败就回根）。
static NSString *const kGHLFloatPanelLastPageKey = @"GHLFloatPanelLastPage";

static BOOL GHLFloatPanelButtonEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:GHL_KEY_FLOAT_PANEL_BUTTON];
    if (!value) return YES; // 没设置过默认开（DYYY.xm %ctor 也 registerDefaults 了，双保险）
    return [value boolValue];
}

static void GHLRefreshFloatPanelButton(void) {
    // 只在主线程调（巡检 tick 是主线程）。
    if (![NSThread isMainThread]) return;
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (!ghlFloatPanelButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:GHLLogoImage() forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFill;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        button.layer.cornerRadius = 20;
        button.layer.masksToBounds = YES;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [DYYYUtils dYYYGoldAccentColor].CGColor;
        button.accessibilityLabel = @"顾海龙抖音快捷面板";
        [button addTarget:[GHLFeatures class] action:@selector(ghl_floatPanelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:button];
        ghlFloatPanelButton = button;
        GHLLog(@"快捷面板：浮动钮已建（龙头，左上角）");
    }
    // 卡片开着时钮藏起来（不然它会被 2 秒巡检重新加到窗口最上层，盖在卡片上）。
    if (ghlFloatPanelOpen) {
        ghlFloatPanelButton.hidden = YES;
        return;
    }
    if (ghlFloatPanelButton.window != window) [window addSubview:ghlFloatPanelButton];
    // 位置：左上角、状态栏下方；小一点（40pt），不挡操作。
    CGFloat topInset = 0;
    if (@available(iOS 11.0, *)) topInset = window.safeAreaInsets.top;
    ghlFloatPanelButton.frame = CGRectMake(10, topInset + 8, 40, 40);
    // 显隐：开关开＋正在视频 feed 页（有当前互动控制器）＋不在直播间／设置／关于／日志／评论页。
    BOOL show = NO;
    if (GHLFloatPanelButtonEnabled() && [DYYYFloatingButtonCoordinator currentInteractionController]) {
        NSString *topName = NSStringFromClass([GHLTopViewController() class]);
        BOOL inOverlayPage = [topName containsString:@"Setting"] || [topName containsString:@"About"] ||
                             [topName containsString:@"LogViewer"] || [topName containsString:@"Comment"] ||
                             [topName containsString:@"Live"];
        show = !inOverlayPage;
    }
    ghlFloatPanelButton.hidden = !show;
}

// 卡片几何：1.0.22 收小——不要近全屏（1.0.21 是 390×800 级，读起来像实心灰板）。
// 宽留 48pt 边距（最多 400），高留 240pt（最少 300）：一眼看出是张卡片。
// 1.0.23：实心卡不再透视频，尺寸照旧（iPhone 11 上卡高 656pt，导航栏＋完成条约 110pt）。
static CGRect GHLFloatPanelCardFrameForBounds(CGRect bounds) {
    CGFloat cardWidth = MIN(bounds.size.width - 48, 400);
    CGFloat cardHeight = MAX(bounds.size.height - 240, 300);
    return CGRectMake((bounds.size.width - cardWidth) / 2, (bounds.size.height - cardHeight) / 2, cardWidth, cardHeight);
}

// 卡片重排（转屏／窗口尺寸变了时调；只在卡片建好后有用）。
static void GHLLayoutFloatPanel(void) {
    if (!ghlFloatPanelWindow || !ghlFloatPanelCard) return;
    CGRect bounds = ghlFloatPanelWindow.bounds;
    ghlFloatPanelCard.frame = GHLFloatPanelCardFrameForBounds(bounds);
    CGRect cardBounds = ghlFloatPanelCard.bounds;
    if (ghlFloatPanelNav) {
        ghlFloatPanelNav.view.frame = CGRectMake(kGHLFloatPanelNavInset, kGHLFloatPanelNavInset,
                                                 cardBounds.size.width - kGHLFloatPanelNavInset * 2,
                                                 cardBounds.size.height - kGHLFloatPanelNavInset - kGHLFloatPanelDoneBarHeight);
        // 1.0.22：立即强制排一次——导航栈里的子页 view 是在 viewDidLoad 时按屏幕尺寸建的
        // （表/滚动视图按 414 宽建），不强制排，子页可能一直按屏幕宽排、右边被卡片裁掉。
        [ghlFloatPanelNav.view setNeedsLayout];
        [ghlFloatPanelNav.view layoutIfNeeded];
    }
    if (ghlFloatPanelDoneButton) {
        ghlFloatPanelDoneButton.frame = CGRectMake(16, cardBounds.size.height - kGHLFloatPanelDoneBarHeight + 8,
                                                   cardBounds.size.width - 32, kGHLFloatPanelDoneBarHeight - 16);
    }
}

// 1.0.24：换背景图后重铺卡片底图（设置页「更换背景图」/「恢复默认背景」后调；
// 卡片没建好或没打开时什么都不做；没自选图就把旧底图撤掉回实心浅灰）。
void GHLRefreshFloatPanelCardBackground(void) {
    if (!ghlFloatPanelCard) return;
    UIView *oldBG = [ghlFloatPanelCard viewWithTag:9871];
    [oldBG removeFromSuperview];
    UIImage *cardBGImage = GHLCustomBackgroundImage();
    if (!cardBGImage) return;
    UIView *cardBG = [DYYYUtils dYYYSettingsBackgroundViewForImage:cardBGImage darkMode:NO];
    cardBG.frame = ghlFloatPanelCard.bounds;
    cardBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cardBG.tag = 9871;
    [ghlFloatPanelCard insertSubview:cardBG atIndex:0];
}

static void GHLBuildFloatPanelIfNeeded(void) {
    if (ghlFloatPanelWindow) return;
    UIWindow *mainWindow = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    if (!mainWindow) return;
    CGRect bounds = mainWindow.bounds;

    UIWindow *panelWindow = [[UIWindow alloc] initWithFrame:bounds];
    if (@available(iOS 13.0, *)) {
        panelWindow.windowScene = mainWindow.windowScene;
    }
    panelWindow.windowLevel = UIWindowLevelAlert;
    panelWindow.backgroundColor = [UIColor clearColor];
    panelWindow.hidden = YES; // 建好先藏着，打开时再显示

    // 宿主 VC 是空壳，view 就是全屏遮罩（点外面关闭）；导航栈挂在它下面。
    // 1.0.23：遮罩改回黑 0.5（1.0.22 的 0.12 是给毛玻璃透亮留的；实心卡不需要透，
    // 照片里卡片外面就是压暗的视频，0.5 才对）。
    UIViewController *hostVC = [[UIViewController alloc] init];
    UIView *container = [[UIView alloc] initWithFrame:bounds];
    container.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 1.0.20：dimTap 只认卡片外的触摸（delegate 见下面 GHLFeatures 分类）；
    // cancelsTouchesInView=NO 是第二道保险——手势认出来也不取消别的 view 的触摸。
    // 以前两个都没做，卡片里所有轻点都被取消（touchesCancelled 代替 touchesEnded），
    // 整个设置列表点不了（6.log：卡片开了 9 分钟，点半天没反应）。
    UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_floatPanelDimTapped:)];
    dimTap.delegate = (id<UIGestureRecognizerDelegate>)[GHLFeatures class];
    dimTap.cancelsTouchesInView = NO;
    [container addGestureRecognizer:dimTap];
    hostVC.view = container;
    panelWindow.rootViewController = hostVC;

// 卡片：1.0.23 改回照片那款 A——浅色实心卡，不追毛玻璃了（1.0.21/1.0.22 两版
// 玻璃真机都没糊出皇上要的效果，改回实心最稳）：卡片底就是实心浅灰，
// 10pt 边框露出来就是照片里卡片外框那个灰；内页（设置列表／关于／日志）
// 本来就是不透明的，字清楚，不用再赌糊不糊得出来。
// 1.0.24：自定义背景图改全屏——有自选图时整张图铺满整个卡片背后（导航栏、
// 列表、「完成」条都在图上），图上再盖一层淡白遮罩（跟设置页表底同一套，
// 字才看得清）；没自选图时卡片还是实心浅灰，不变。
    UIView *card = [[UIView alloc] initWithFrame:GHLFloatPanelCardFrameForBounds(bounds)];
    card.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    card.layer.cornerRadius = 24;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6].CGColor;
    // 居中不随尺寸变：四边留白自适应，转屏时靠下面的重排再算一次。
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                            UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    UIImage *cardBGImage = GHLCustomBackgroundImage();
    if (cardBGImage) {
        UIView *cardBG = [DYYYUtils dYYYSettingsBackgroundViewForImage:cardBGImage darkMode:NO];
        cardBG.frame = card.bounds;
        cardBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cardBG.tag = 9871; // 换背景图时按 tag 找到重铺（GHLRefreshFloatPanelCardBackground）
        [card addSubview:cardBG];
    }
    [container addSubview:card];

    // 卡片里的导航栈：1.0.23 根改回设置页本身（1.0.19/1.0.20 就是这样，皇上
    // 2026-11-15 05:48 说改回照片那款——照片里就是直接设置列表，没有 8 按键首页）。
    // 分区行点进子页还在卡片内的导航栈上推，不展开全屏；关于、日志都从列表进。
    // 1.0.21：导航栈缩进 10pt（实心卡边框露出来）＋圆角 16，底部留 64pt 给「完成」条。
    DYYYSettingViewController *settingsVC = GHLFloatPanelSharedSettingsViewController();
    settingsVC.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:[GHLFeatures class] action:@selector(ghl_floatPanelCloseTapped)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    // 1.0.22：导航栏改不透明（录屏实锤两处：关于页里 QQ 群号透过导航栏看得见；关于页滚到顶时
    // 内容顶到半透明导航栏下面被白条盖住）。不透明导航栏下，子页 view 自动排在导航栏下面，
    // 内容再也不会从导航栏下透出来、也不会被导航栏盖住。导航栈底色也盖实，免得页面之间透。
    // 1.0.24：全屏背景图——导航栏改透明、导航栈底色改透明，卡片底的整张背景图从导航栏
    // 后面透出来；各页自己都是浅色半透明白行 + 卡片底的淡白遮罩，字看得清。
    // 推页时上一页从半透明行后面透出来的老问题靠「所有页共用同一张卡片底图」顶住：
    // 透出来的底色永远是同一张图，不再是上一页的内容。
    nav.navigationBar.translucent = YES;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = [UIColor clearColor];
        nav.navigationBar.standardAppearance = appearance;
        nav.navigationBar.scrollEdgeAppearance = appearance;
    } else {
        nav.navigationBar.barTintColor = [UIColor clearColor];
    }
    nav.view.backgroundColor = [UIColor clearColor];
    nav.view.frame = CGRectMake(kGHLFloatPanelNavInset, kGHLFloatPanelNavInset,
                                card.bounds.size.width - kGHLFloatPanelNavInset * 2,
                                card.bounds.size.height - kGHLFloatPanelNavInset - kGHLFloatPanelDoneBarHeight);
    nav.view.layer.cornerRadius = 16;
    nav.view.layer.masksToBounds = YES;
    [hostVC addChildViewController:nav];
    [card addSubview:nav.view];
    [nav didMoveToParentViewController:hostVC];

    // 1.0.21：底部「完成」按钮改成金色 pill（浅色卡片上金字太淡，金底深字才醒目）；
    // 放在卡片的实心浅灰底上，左右留 16pt。
    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [doneButton setTitle:@"完成" forState:UIControlStateNormal];
    [doneButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    doneButton.backgroundColor = [DYYYUtils dYYYGoldAccentColor];
    doneButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    doneButton.layer.cornerRadius = 12;
    doneButton.layer.masksToBounds = YES;
    doneButton.frame = CGRectMake(16, card.bounds.size.height - kGHLFloatPanelDoneBarHeight + 8,
                                  card.bounds.size.width - 32, kGHLFloatPanelDoneBarHeight - 16);
    [doneButton addTarget:[GHLFeatures class] action:@selector(ghl_floatPanelCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:doneButton];

    ghlFloatPanelWindow = panelWindow;
    ghlFloatPanelHostVC = hostVC;
    ghlFloatPanelCard = card;
    ghlFloatPanelNav = nav;
    ghlFloatPanelDoneButton = doneButton;

    // 转屏时重排卡片（只注册一次；进程内常驻，和巡检定时器一样不摘）。
    if (!ghlFloatPanelOrientationToken) {
        ghlFloatPanelOrientationToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
          if (ghlFloatPanelOpen) GHLLayoutFloatPanel();
        }];
    }
}

// 1.0.21：卡片共用的设置页实例（懒建一份；通用设置推它、关于页拿它当配置三行的帮手）。
DYYYSettingViewController *GHLFloatPanelSharedSettingsViewController(void) {
    if (!ghlFloatPanelSharedSettingsVC) {
        ghlFloatPanelSharedSettingsVC = [[DYYYSettingViewController alloc] init];
        ghlFloatPanelSharedSettingsVC.ghlInFloatPanel = YES;
    }
    return ghlFloatPanelSharedSettingsVC;
}

// 卡片首页「关闭」按钮／底栏切换成功后关卡片用的公开入口（GHLShowFloatPanel 的反向）。
void GHLCloseFloatPanel(void) {
    GHLRunOnMain(^{
      GHLHideFloatPanel();
    });
}

// 1.0.20：卡片记住上次停在哪一页——关卡片时把顶页标识记进偏好（root / section:N / about / log），
// 下次打开恢复；标识对不上就回根。1.0.21：存/恢复都记一行（日志里能验记页到底灵不灵）。
static void GHLSaveFloatPanelLastPage(void) {
    if (!ghlFloatPanelNav) return;
    UIViewController *topVC = ghlFloatPanelNav.topViewController;
    NSString *page = @"root";
    if ([topVC isKindOfClass:[DYYYSettingViewController class]]) {
        NSInteger sectionIndex = [(DYYYSettingViewController *)topVC ghlDisplaySectionIndex];
        if (sectionIndex != NSNotFound) page = [NSString stringWithFormat:@"section:%ld", (long)sectionIndex];
    } else if ([topVC isKindOfClass:[GHLAboutViewController class]]) {
        page = @"about";
    } else if ([topVC isKindOfClass:[GHLLogViewerViewController class]]) {
        page = @"log";
    }
    [[NSUserDefaults standardUserDefaults] setObject:page forKey:kGHLFloatPanelLastPageKey];
    GHLLog(@"卡片记页：已存「%@」", page);
}

static void GHLHideFloatPanel(void); // 定义在下面（GHLCloseFloatPanel 先用到）

static void GHLRestoreFloatPanelLastPage(void) {
    if (!ghlFloatPanelNav) return;
    [ghlFloatPanelNav popToRootViewControllerAnimated:NO];
    NSString *page = [[NSUserDefaults standardUserDefaults] stringForKey:kGHLFloatPanelLastPageKey];
    if (!page || [page isEqualToString:@"root"]) {
        GHLLog(@"卡片记页：恢复到设置列表（%@）", page ?: @"没记过");
        return;
    }
    // 1.0.23：根页改回设置页本身（记页恢复失败就回根＝设置列表）。
    @try {
        if ([page hasPrefix:@"section:"]) {
            NSInteger sectionIndex = [[page substringFromIndex:@"section:".length] integerValue];
            // 分区共 11 个（setupSectionTitles 与 settingSections 11/11 对齐）；越界就回根。
            if (sectionIndex < 0 || sectionIndex >= 11) {
                GHLLog(@"卡片记页：分区 %@ 越界，回设置列表", page);
                return;
            }
            DYYYSettingViewController *subVC = [[DYYYSettingViewController alloc] initWithSectionIndex:sectionIndex];
            subVC.ghlInFloatPanel = YES;
            [ghlFloatPanelNav pushViewController:subVC animated:NO];
            GHLLog(@"卡片记页：恢复到分区 %ld", (long)sectionIndex);
        } else if ([page isEqualToString:@"about"]) {
            GHLAboutViewController *aboutVC = [[GHLAboutViewController alloc] init];
            aboutVC.settingsViewController = GHLFloatPanelSharedSettingsViewController();
            [ghlFloatPanelNav pushViewController:aboutVC animated:NO];
            GHLLog(@"卡片记页：恢复到关于页");
        } else if ([page isEqualToString:@"log"]) {
            GHLLogViewerViewController *logVC = [[GHLLogViewerViewController alloc] init];
            logVC.ghlInFloatPanel = YES;
            [ghlFloatPanelNav pushViewController:logVC animated:NO];
            GHLLog(@"卡片记页：恢复到日志页");
        } else {
            GHLLog(@"卡片记页：标识「%@」对不上，回设置列表", page);
        }
    } @catch (__unused NSException *exception) {
        // 恢复失败就回根（顶页在旧版删了、分区变了，都不崩）。
        [ghlFloatPanelNav popToRootViewControllerAnimated:NO];
        GHLLog(@"卡片记页：恢复「%@」时异常，回设置列表", page);
    }
}

void GHLShowFloatPanel(void) {
    if (![NSThread isMainThread]) {
        GHLRunOnMain(^{
          GHLShowFloatPanel();
        });
        return;
    }
    GHLBuildFloatPanelIfNeeded();
    if (!ghlFloatPanelWindow) return;
    // 每次打开都按当前屏幕尺寸重排（转屏后第一次打开也不会错位）。
    GHLLayoutFloatPanel();
    // 1.0.20：不再每次回到根——恢复上次停的那页（恢复失败就回根）。
    GHLRestoreFloatPanelLastPage();
    ghlFloatPanelWindow.hidden = NO;
    ghlFloatPanelOpen = YES;
    if (ghlFloatPanelButton) ghlFloatPanelButton.hidden = YES;
    ghlFloatPanelWindow.alpha = 0;
    ghlFloatPanelCard.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.2 animations:^{
      ghlFloatPanelWindow.alpha = 1;
      ghlFloatPanelCard.transform = CGAffineTransformIdentity;
    }];
    GHLLog(@"快捷面板：已打开");
}

static void GHLHideFloatPanel(void) {
    if (!ghlFloatPanelOpen || !ghlFloatPanelWindow) return;
    // 1.0.20：关之前记下顶页，下次打开回到这里。
    GHLSaveFloatPanelLastPage();
    ghlFloatPanelOpen = NO;
    [UIView animateWithDuration:0.15 animations:^{
      ghlFloatPanelWindow.alpha = 0;
    } completion:^(__unused BOOL finished) {
      ghlFloatPanelWindow.hidden = YES;
      ghlFloatPanelWindow.alpha = 1;
    }];
    GHLLog(@"快捷面板：已关闭");
}

// 遮罩点按：点到卡片上不关，点到卡片外才关（手势挂在遮罩上，用位置判断）。
static void GHLFloatPanelHandleDimTap(UITapGestureRecognizer *gesture) {
    if (!ghlFloatPanelWindow || !ghlFloatPanelCard) return;
    UIView *container = ghlFloatPanelHostVC.view;
    if (!container) return;
    CGPoint point = [gesture locationInView:container];
    if (CGRectContainsPoint(ghlFloatPanelCard.frame, point)) return;
    GHLHideFloatPanel();
}

static void GHLToggleFloatPanel(void) {
    if (ghlFloatPanelOpen) {
        GHLHideFloatPanel();
    } else {
        GHLShowFloatPanel();
    }
}

// 1.0.20：dimTap 的手势代理——卡片里的触摸不交给 dimTap（行选中、开关、按钮都走正常触摸），
// 只有卡片外的触摸才让手势认（点卡片外关掉）。没有这个，光靠 handler 里「点在卡片内就 return」
// 救不回来——触摸在 handler 跑之前就已经被取消了（6.log 诊断实锤）。
@implementation GHLFeatures (GHLFloatPanelGestureDelegate)

+ (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    if (!ghlFloatPanelCard || !ghlFloatPanelHostVC) return YES;
    UIView *container = ghlFloatPanelHostVC.view;
    if (!container) return YES;
    CGPoint point = [touch locationInView:container];
    if (CGRectContainsPoint(ghlFloatPanelCard.frame, point)) return NO;
    return YES;
}

@end

#pragma mark 主线程卡住看门狗（1.0.21，诊断用）

// 冻住的证据收集器：后台线程每 500ms ping 一次主线程，3 秒没回应＝主线程卡住了。
// （皇上 1.0.20：抖音整个不能动，只能杀掉重开；巡检最长 7.2ms、布局最长 3.7ms 都已排除，
//  冻住的原因还没定死——这个看门狗只抓证据，不修冻住。日志写盘走 GHLLog 的串行队列，
//  线程安全；“最近活动”读 GHLLastLogMessage（同样走日志队列，线程安全）。）
static dispatch_source_t ghlMainThreadWatchdogTimer = nil;
static CFAbsoluteTime ghlMainThreadStuckSince = 0;
static CFAbsoluteTime ghlMainThreadWatchdogLastReminder = 0;
// 1.0.24：巡检最后一次跑的时间（主线程写、看门狗读，诊断用；double 读写本身够用）。
// 巡检定时器是默认 mode（滑动时暂停），所以“巡检停了”本身不等于冻住；
// 看门狗拿它和主线程 ping 的结果交叉验证：ping 不通 + 巡检停了＝主线程真死了；
// ping 通但巡检停了 30 秒以上＝定时器/runloop 有问题（看门狗以前的盲区）。
static CFAbsoluteTime ghlLastHousekeepingTickTime = 0;
static BOOL ghlWatchdogTickStaleLogged = NO;

static void GHLStartMainThreadWatchdog(void) {
    if (ghlMainThreadWatchdogTimer) return;
    dispatch_queue_t queue = dispatch_queue_create("com.guhailong.douyin.mainthreadwatchdog", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), 500 * NSEC_PER_MSEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
      // 主线程回一个信号就放行；3 秒等不到＝卡住了（定时器在后台队列等，不占主线程）。
      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
      dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_semaphore_signal(sema);
      });
      CFAbsoluteTime waitStart = CFAbsoluteTimeGetCurrent();
      long result = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
      CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
      // 1.0.24：巡检停了多久（-1 表示还没跑过第一次巡检）。
      double tickStaleSec = (ghlLastHousekeepingTickTime > 0) ? (now - ghlLastHousekeepingTickTime) : -1;
      if (result != 0) {
          // 卡住了：第一次记一行，之后每 5 秒再记一行（别刷屏），恢复时记卡住时长。
          if (ghlMainThreadStuckSince == 0) {
              ghlMainThreadStuckSince = waitStart;
              ghlMainThreadWatchdogLastReminder = now;
              GHLLog(@"主线程卡住：已无响应 3 秒，最近活动：%@；巡检最后一次是 %.0f 秒前", GHLLastNonWatchdogMessage() ?: @"（无）", tickStaleSec);
          } else if (now - ghlMainThreadWatchdogLastReminder >= 5) {
              ghlMainThreadWatchdogLastReminder = now;
              GHLLog(@"主线程卡住：仍无响应，已卡 %.0f 秒，最近活动：%@；巡检最后一次是 %.0f 秒前", now - ghlMainThreadStuckSince, GHLLastNonWatchdogMessage() ?: @"（无）", tickStaleSec);
          }
      } else if (ghlMainThreadStuckSince > 0) {
          GHLLog(@"主线程恢复：卡住约 %.1f 秒，最近活动：%@；巡检最后一次是 %.0f 秒前", now - ghlMainThreadStuckSince, GHLLastNonWatchdogMessage() ?: @"（无）", tickStaleSec);
          ghlMainThreadStuckSince = 0;
      } else if (tickStaleSec > 30 && !ghlWatchdogTickStaleLogged) {
          // 1.0.24：主线程还在回 ping，但巡检 30 秒没跑——定时器被挂起或 runloop
          // 卡在别的 mode（滑动只会停几秒，30 秒不是滑动）；只记一次，巡检恢复后重置。
          ghlWatchdogTickStaleLogged = YES;
          GHLLog(@"主线程看门狗：主线程还在回 ping，但巡检已停 %.0f 秒（定时器/runloop 异常）", tickStaleSec);
      }
    });
    dispatch_resume(timer);
    ghlMainThreadWatchdogTimer = timer;
    GHLLog(@"主线程看门狗：已启动（每 500ms 探一次，3 秒没回应就记「主线程卡住」）");
}

#pragma mark 巡检定时器（2 秒一次）

#pragma mark - 1.0.23 第二批：影片功能（48/59/70/71/73/75）

// 48 自动连播：没有播放结束回调（BDSimMediaPlayer 不暴露进度），
// 用 2 秒巡检累计当前视频已播时长（videoDuration 是毫秒），播满就切下一个。
// 直播间不跑（直播没有固定时长）；切视频/换作者就重置累计。
static NSString *ghlAutoPlayItemID = nil;
static double ghlAutoPlayElapsed = 0;
void GHLCheckAutoPlayNext(void) {
    if (!GHLGetBool(GHL_KEY_AUTO_PLAY_NEXT)) {
        ghlAutoPlayItemID = nil;
        ghlAutoPlayElapsed = 0;
        return;
    }
    if (GHLIsInLiveRoom()) {
        ghlAutoPlayItemID = nil;
        ghlAutoPlayElapsed = 0;
        return;
    }
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    if (!model || !model.itemID) {
        ghlAutoPlayItemID = nil;
        ghlAutoPlayElapsed = 0;
        return;
    }
    double duration = model.videoDuration / 1000.0;
    if (duration <= 0) {
        ghlAutoPlayItemID = nil;
        ghlAutoPlayElapsed = 0;
        return;
    }
    if (![model.itemID isEqualToString:ghlAutoPlayItemID]) {
        ghlAutoPlayItemID = [model.itemID copy];
        ghlAutoPlayElapsed = 0;
        return;
    }
    ghlAutoPlayElapsed += 2.0;
    if (ghlAutoPlayElapsed >= duration) {
        ghlAutoPlayElapsed = 0;
        ghlAutoPlayItemID = nil;
        GHLLog(@"自动连播：当前视频播满 %.0f 秒，切下一个", duration);
        GHLScrollFeedToNextVideo();
    }
}

// 59 仅看一次开启下载按钮：probe-only——GHLProbePrivacyFeatures 已 dump 过
// Burn/Disappear/SecretChat 相关类，没找到可验证的 hook 点；
// 开关开后这里再 dump 一次含 Once/ViewOnce/Flash 的类名，等真机日志定 hook 点。
void GHLProbeViewOnce(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name containsString:@"ViewOnce"] || [name containsString:@"Once"] || [name containsString:@"Flash"]) {
            if (hits.count < 30) [hits addObject:name];
        }
    }
    free(classes);
    GHLLog(@"仅看一次探针：疑似相关类 %lu 个：%@", (unsigned long)hits.count, hits);
    GHLLog(@"仅看一次探针：以上只做记录；没找到可验证的 hook 点，下载按钮目前加不上，开关先留着等日志");
}

// 70/71/73 消息页手势：IM 控制器类名没写进 AwemeHeaders（只有少量 AWEIM* 声明），
// 所以按类名含 "IM" 找顶层消息控制器，再在它的 view 里找消息列表（UITableView）。
// 找到才装手势，只装一次；不在消息页时什么都不做。
static void GHLCollectIMViewControllers(UIViewController *vc, NSMutableArray<UIViewController *> *out) {
    if (!vc) return;
    if ([NSStringFromClass([vc class]) containsString:@"IM"]) [out addObject:vc];
    for (UIViewController *child in vc.childViewControllers) GHLCollectIMViewControllers(child, out);
    GHLCollectIMViewControllers(vc.presentedViewController, out);
}

static UIViewController *GHLTopIMViewController(void) {
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return nil;
    NSMutableArray<UIViewController *> *found = [NSMutableArray array];
    GHLCollectIMViewControllers(window.rootViewController, found);
    return found.lastObject;
}

// 最顶层控制器（沿 presented 链走到头）：续火花点开会话后，输入框在新推上来的聊天页里。
static UIViewController *GHLTopmostViewController(void) {
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static UITableView *GHLFindTableViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *found = GHLFindTableViewInView(sub);
        if (found) return found;
    }
    return nil;
}

// 消息输入框：抖音消息页一般是 UITextView，兜底也认 UITextField；
// 是启发式找的（第一个文本输入框），万一找到的是搜索框，真机日志会露出来。
static UIView *GHLFindTextInputInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextView class]] || [view isKindOfClass:[UITextField class]]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = GHLFindTextInputInView(sub);
        if (found) return found;
    }
    return nil;
}

static UIButton *GHLFindSendButtonInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
        NSString *axLabel = button.accessibilityLabel ?: @"";
        if ([title containsString:@"发送"] || [axLabel containsString:@"发送"]) return button;
    }
    for (UIView *sub in view.subviews) {
        UIButton *found = GHLFindSendButtonInView(sub);
        if (found) return found;
    }
    return nil;
}

// 71 探针：dump 消息页输入栏一带的按钮类名（只跑一次），等真机日志定加号按钮的 hook 点。
static void GHLProbeIMInputBar(UIViewController *imVC) {
    if (!imVC) return;
    NSMutableArray<NSString *> *buttons = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:imVC.view];
    while (stack.count > 0 && buttons.count < 20) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            NSString *title = [button titleForState:UIControlStateNormal] ?: (button.accessibilityLabel ?: @"");
            [buttons addObject:[NSString stringWithFormat:@"%@(%@)", NSStringFromClass([view class]), title]];
        }
        [stack addObjectsFromArray:view.subviews];
    }
    GHLLog(@"消息加号探针：消息页按钮 %lu 个：%@", (unsigned long)buttons.count, buttons);
    GHLLog(@"消息加号探针：以上只做记录；加号按钮的 hook 点还没定，开关目前只记日志");
}

static char kGHLIMGesturesInstalledKey;

void GHLInstallIMGesturesIfNeeded(void) {
    if (!GHLGetBool(GHL_KEY_IM_DOUBLE_TAP_REPLY) && !GHLGetBool(GHL_KEY_STREAK_AUTO_SEND) && !GHLGetBool(GHL_KEY_IM_PLUS_ALBUM_PROBE)) return;
    UIViewController *imVC = GHLTopIMViewController();
    if (!imVC) return;
    UITableView *table = GHLFindTableViewInView(imVC.view);
    if (!table) return;
    if (objc_getAssociatedObject(table, &kGHLIMGesturesInstalledKey)) return;
    objc_setAssociatedObject(table, &kGHLIMGesturesInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (GHLGetBool(GHL_KEY_IM_PLUS_ALBUM_PROBE)) {
        static BOOL ghlIMProbeDone = NO;
        if (!ghlIMProbeDone) {
            ghlIMProbeDone = YES;
            GHLProbeIMInputBar(imVC);
        }
    }
    if (GHLGetBool(GHL_KEY_IM_DOUBLE_TAP_REPLY)) {
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleIMDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.numberOfTouchesRequired = 1;
        doubleTap.cancelsTouchesInView = NO;
        [table addGestureRecognizer:doubleTap];
    }
    if (GHLGetBool(GHL_KEY_STREAK_AUTO_SEND)) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:[GHLFeatures class] action:@selector(ghl_handleIMAvatarLongPress:)];
        longPress.minimumPressDuration = 0.5;
        longPress.cancelsTouchesInView = NO;
        [table addGestureRecognizer:longPress];
    }
    GHLLog(@"消息手势：已装到 %@（双击回复 %@，长按头像续火花 %@）", NSStringFromClass([imVC class]),
           GHLGetBool(GHL_KEY_IM_DOUBLE_TAP_REPLY) ? @"开" : @"关",
           GHLGetBool(GHL_KEY_STREAK_AUTO_SEND) ? @"开" : @"关");
}

// 70 双击消息快捷回复：双击消息列表，聚焦输入框（只聚焦，不替用户发）。
static void GHLHandleIMDoubleTapReply(void) {
    UIViewController *imVC = GHLTopIMViewController();
    if (!imVC) return;
    UIView *input = GHLFindTextInputInView(imVC.view);
    if (!input) {
        GHLLog(@"双击消息快捷回复：没找到输入框");
        return;
    }
    [input becomeFirstResponder];
    GHLLog(@"双击消息快捷回复：已聚焦输入框");
}

// 73 续火花：长按联系人头像才触发（不要自动发）——点开该会话、填模板、点发送按钮。
// 模板在设置里填，用 | 分隔多条；多条时目前只发第 1 条（多选 UI 还没做，
// 提示里会列出全部模板，想发别的条先在设置里把它放第一行）。
// 发送按钮找不到时只填文字不自动发（留给用户自己点发送），绝不静默重试。
static void GHLHandleIMAvatarLongPress(UITableView *table, CGPoint point) {
    if (!table) return;
    NSIndexPath *indexPath = [table indexPathForRowAtPoint:point];
    if (!indexPath) return;
    UITableViewCell *cell = [table cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    // 头像判断：cell 里靠左（x < 70）的方形图片（28–64pt）；点在别处不触发。
    BOOL hitAvatar = NO;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:cell.contentView];
    while (stack.count > 0 && !hitAvatar) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:[UIImageView class]] && view.superview) {
            CGRect frame = [cell.contentView convertRect:view.frame fromView:view.superview];
            CGFloat w = CGRectGetWidth(frame), h = CGRectGetHeight(frame);
            if (CGRectGetMinX(frame) < 70 && w >= 28 && w <= 64 && fabs(w - h) < 6) hitAvatar = YES;
        }
        [stack addObjectsFromArray:view.subviews];
    }
    if (!hitAvatar) return;
    NSString *templatesRaw = GHLGetString(GHL_KEY_STREAK_TEMPLATES) ?: @"";
    NSMutableArray<NSString *> *templates = [NSMutableArray array];
    for (NSString *part in [templatesRaw componentsSeparatedByString:@"|"]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [templates addObject:trimmed];
    }
    if (templates.count == 0) {
        [DYYYUtils showToast:@"续火花：先在设置里填自动发送的文本模板"];
        GHLLog(@"续火花：没填模板，长按头像没发");
        return;
    }
    NSString *text = templates.firstObject;
    void (^sendNow)(void) = ^{
      // 点开该会话（长按本身不会触发选中，手动调 delegate 打开聊天页）。
      id<UITableViewDelegate> delegate = table.delegate;
      if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
          [delegate tableView:table didSelectRowAtIndexPath:indexPath];
      }
      // 等会话页打开，再填文本、点发送。
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *chatVC = GHLTopmostViewController();
        UIView *input = chatVC ? GHLFindTextInputInView(chatVC.view) : nil;
        if (!input) {
            GHLLog(@"续火花：会话打开了，但没找到输入框，没发");
            [DYYYUtils showToast:@"续火花：没找到输入框，没发出去"];
            return;
        }
        if ([input respondsToSelector:@selector(setText:)]) {
            [input performSelector:@selector(setText:) withObject:text];
        }
        UIButton *sendButton = chatVC ? GHLFindSendButtonInView(chatVC.view) : nil;
        if (!sendButton) {
            GHLLog(@"续火花：已填好文本，但没找到发送按钮，只填文字不自动发");
            [DYYYUtils showToast:@"续火花：已填好文本，请手动点发送"];
            return;
        }
        [sendButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        GHLLog(@"续火花：已发「%@」", text);
      });
    };
    if (templates.count > 1) {
        NSMutableString *list = [NSMutableString string];
        [templates enumerateObjectsUsingBlock:^(NSString *templateText, NSUInteger idx, BOOL *stop) {
          (void)stop;
          [list appendFormat:@"%lu. %@\n", (unsigned long)(idx + 1), templateText];
        }];
        [DYYYBottomAlertView showAlertWithTitle:@"续火花自动发消息"
                                         message:[NSString stringWithFormat:@"共 %lu 条模板，点确定发第 1 条：\n%@（想发别的条，先在设置里把它放第一行）", (unsigned long)templates.count, list]
                                       avatarURL:nil
                                cancelButtonText:@"取消"
                               confirmButtonText:@"发送第 1 条"
                                    cancelAction:nil
                                     closeAction:nil
                                   confirmAction:sendNow];
        return;
    }
    sendNow();
}

// 75 玻璃评论面板 + AI 解析：页签只在玻璃开关开时装（hook 里已判断）；
// AI 解析要用户自己填 OpenAI 兼容接口的 Key＋地址＋模型，没填 Key 时只显示配置提示，
// 不编造解析结果、不调任何默认接口。
static char kGHLAISegmentKey;
static char kGHLAIOverlayKey;
static char kGHLAIResultViewKey;
static char kGHLAIStatusLabelKey;

void GHLInstallCommentAIParseSegment(UIViewController *commentVC) {
    if (!commentVC || !commentVC.view) return;
    if (objc_getAssociatedObject(commentVC, &kGHLAISegmentKey)) return;
    GHLRunOnMain(^{
      UIView *view = commentVC.view;
      UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[@"评论", @"AI 解析"]];
      segment.selectedSegmentIndex = 0;
      segment.frame = CGRectMake(16, 8, view.bounds.size.width - 32, 30);
      segment.autoresizingMask = UIViewAutoresizingFlexibleWidth;
      [segment addTarget:[GHLFeatures class] action:@selector(ghl_handleAISegmentChanged:) forControlEvents:UIControlEventValueChanged];
      [view addSubview:segment];
      objc_setAssociatedObject(commentVC, &kGHLAISegmentKey, segment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 46, view.bounds.size.width, view.bounds.size.height - 46)];
      panel.backgroundColor = [UIColor whiteColor];
      panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      panel.hidden = YES;
      UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panel.bounds.size.width - 32, 20)];
      statusLabel.font = [UIFont systemFontOfSize:13];
      statusLabel.textColor = [UIColor grayColor];
      statusLabel.text = @"点「开始解析」总结当前评论区";
      statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
      [panel addSubview:statusLabel];
      UIButton *parseButton = [UIButton buttonWithType:UIButtonTypeSystem];
      [parseButton setTitle:@"开始解析" forState:UIControlStateNormal];
      parseButton.frame = CGRectMake(16, 40, 100, 36);
      [parseButton addTarget:[GHLFeatures class] action:@selector(ghl_handleAIParseStart:) forControlEvents:UIControlEventTouchUpInside];
      [panel addSubview:parseButton];
      UITextView *resultView = [[UITextView alloc] initWithFrame:CGRectMake(12, 84, panel.bounds.size.width - 24, panel.bounds.size.height - 96)];
      resultView.font = [UIFont systemFontOfSize:15];
      resultView.editable = NO;
      resultView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      [panel addSubview:resultView];
      [view addSubview:panel];
      objc_setAssociatedObject(commentVC, &kGHLAIOverlayKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(commentVC, &kGHLAIResultViewKey, resultView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(commentVC, &kGHLAIStatusLabelKey, statusLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      GHLLog(@"AI 解析页签：已装到评论面板");
    });
}

static void GHLHandleAISegmentChanged(UISegmentedControl *segment) {
    if (!segment) return;
    UIResponder *responder = segment.nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = responder.nextResponder;
    UIViewController *vc = (UIViewController *)responder;
    if (!vc) return;
    UIView *panel = objc_getAssociatedObject(vc, &kGHLAIOverlayKey);
    if (panel) panel.hidden = (segment.selectedSegmentIndex == 0);
    GHLLog(@"AI 解析页签：切到 %@", segment.selectedSegmentIndex == 0 ? @"评论" : @"AI 解析");
}

static void GHLHandleAIParseStart(UIButton *button) {
    if (!button) return;
    UIResponder *responder = button.nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = responder.nextResponder;
    UIViewController *vc = (UIViewController *)responder;
    if (!vc) return;
    UITextView *resultView = objc_getAssociatedObject(vc, &kGHLAIResultViewKey);
    UILabel *statusLabel = objc_getAssociatedObject(vc, &kGHLAIStatusLabelKey);
    GHLAIParseCommentsFromView(vc.view, resultView, statusLabel);
}

void GHLAIParseCommentsFromView(UIView *panelView, UITextView *resultView, UILabel *statusLabel) {
    NSString *apiKey = GHLGetString(GHL_KEY_AI_PARSE_KEY) ?: @"";
    NSString *baseURL = GHLGetString(GHL_KEY_AI_PARSE_BASE_URL) ?: @"";
    NSString *model = GHLGetString(GHL_KEY_AI_PARSE_MODEL) ?: @"";
    if (apiKey.length == 0) {
        if (statusLabel) statusLabel.text = @"先在设置里填 AI 接口 Key（OpenAI 兼容接口）";
        GHLLog(@"AI 解析：没填 Key，只显示配置提示");
        return;
    }
    if (baseURL.length == 0) baseURL = @"https://api.openai.com/v1";
    if (model.length == 0) model = @"gpt-3.5-turbo";
    // 收集评论文字：遍历面板里的 UILabel，取长度 >= 4 的正文，最多 20 条；
    // 跳过 AI 面板自己里面的字（不然会把上次的解析结果也当评论喂进去）。
    UIView *aiPanel = resultView ? resultView.superview : nil;
    NSMutableArray<NSString *> *comments = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:panelView];
    while (stack.count > 0 && comments.count < 20) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if (aiPanel && (view == aiPanel || [view isDescendantOfView:aiPanel])) continue;
        if ([view isKindOfClass:[UILabel class]]) {
            NSString *text = [(UILabel *)view text];
            if (text.length >= 4 && ![comments containsObject:text]) [comments addObject:text];
        }
        [stack addObjectsFromArray:view.subviews];
    }
    if (comments.count == 0) {
        if (statusLabel) statusLabel.text = @"没找到评论文字，先滑一滑评论区再试";
        GHLLog(@"AI 解析：没找到评论文字");
        return;
    }
    if (statusLabel) statusLabel.text = [NSString stringWithFormat:@"正在解析 %lu 条评论…", (unsigned long)comments.count];
    NSString *prompt = [NSString stringWithFormat:@"请用简体中文总结以下抖音评论的主要观点和情绪（不超过 200 字）：\n%@", [comments componentsJoinedByString:@"\n"]];
    NSDictionary *body = @{@"model" : model,
                           @"messages" : @[ @{@"role" : @"user", @"content" : prompt} ]};
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!bodyData) {
        if (statusLabel) statusLabel.text = @"请求组装失败";
        GHLLog(@"AI 解析：请求组装失败 %@", jsonError);
        return;
    }
    NSString *trimmedBaseURL = [baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmedBaseURL hasSuffix:@"/"]) trimmedBaseURL = [trimmedBaseURL substringToIndex:trimmedBaseURL.length - 1];
    NSURL *url = [NSURL URLWithString:[trimmedBaseURL stringByAppendingString:@"/chat/completions"]];
    if (!url) {
        if (statusLabel) statusLabel.text = @"接口地址填错了，检查一下";
        GHLLog(@"AI 解析：接口地址无效 %@", baseURL);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = bodyData;
    request.timeoutInterval = 30;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      (void)response;
      NSString *summary = nil;
      NSString *statusText = nil;
      if (error) {
          statusText = [NSString stringWithFormat:@"请求失败：%@", error.localizedDescription];
          GHLLog(@"AI 解析：请求失败 %@", error);
      } else {
          NSError *parseError = nil;
          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
          id content = json[@"choices"][0][@"message"][@"content"];
          if ([content isKindOfClass:[NSString class]] && [(NSString *)content length] > 0) {
              summary = (NSString *)content;
              statusText = @"解析完成";
          } else {
              statusText = @"接口没返回解析结果（检查 Key/地址/模型）";
              GHLLog(@"AI 解析：接口返回异常 %@", json);
          }
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (summary && resultView) resultView.text = summary;
        if (statusLabel) statusLabel.text = statusText;
      });
    }];
    [task resume];
    GHLLog(@"AI 解析：已发请求（%lu 条评论，模型 %@）", (unsigned long)comments.count, model);
}

void GHLHousekeepingTick(void) {
    // 1.0.18 计时日志（只加日志，不改行为）：每跳记耗时＋上跳间隔——
    // 某跳 >500ms 或间隔明显拉长（主线程被堵、定时器晚跳）即证实是 tick 拖慢主线程；
    // 每跳都 <50ms 即排除 tick。卡住诊断的证据就靠这一行。
    static CFAbsoluteTime ghlLastTickStart = 0;
    CFAbsoluteTime tickStart = CFAbsoluteTimeGetCurrent();
    double tickIntervalMs = (ghlLastTickStart > 0) ? (tickStart - ghlLastTickStart) * 1000.0 : 0;
    ghlLastTickStart = tickStart;
    // 1.0.24：给看门狗留时间戳（巡检跑了就更新；看门狗拿它和主线程 ping 交叉验证）。
    ghlLastHousekeepingTickTime = tickStart;
    ghlWatchdogTickStaleLogged = NO;
    @try {
        // 1.0.17：进直播间时探一次拉流地址（与 (39) 开关无关；只在进/出切换时跑一次，
        // 不进巡检循环；用自己的进出标记，不动 GHLUpdateLiveDurationLabel 的调用条件）。
        // 1.0.18：探针改后台跑，不堵主线程；结果只看日志（进直播间探一次是诊断用）。
        static BOOL ghlLiveProbeDoneForCurrentRoom = NO;
        if (GHLIsInLiveRoom()) {
            if (!ghlLiveProbeDoneForCurrentRoom) {
                ghlLiveProbeDoneForCurrentRoom = YES;
                GHLProbeLiveStreamURLAsync(nil);
            }
        } else {
            ghlLiveProbeDoneForCurrentRoom = NO;
        }
        // 1.0.18：浮动钮显隐每 2 秒刷一次（只在视频 feed 页出现；开关关了就藏）。
        GHLRefreshFloatPanelButton();
        // 1.0.23 第二批：48 自动连播、70/71/73 消息手势（只在相关开关开时跑）。
        GHLCheckAutoPlayNext();
        GHLInstallIMGesturesIfNeeded();
        if (GHLGetBool(GHL_KEY_LIVE_DURATION) || GHLGetBool(GHL_KEY_LIVE_RECORD)) {
            GHLUpdateLiveDurationLabel();
        }
        if (GHLGetBool(GHL_KEY_AUTO_RED_PACKET)) {
            NSString *blacklist = GHLGetString(GHL_KEY_RED_PACKET_BLACKLIST);
            if (blacklist.length > 0) {
                GHLLog(@"自动抢红包：黑名单 %@ 已填，但直播间里拿不到作者抖音号，黑名单暂时匹配不上，仍会抢（等日志确认作者锚点）", blacklist);
            }
            GHLScanAndTapButtonContaining(@"红包", &ghlRedPacketLastTap, 5.0, @"自动抢红包");
        }
        if (GHLGetBool(GHL_KEY_AUTO_LIVE_LOTTERY)) {
            GHLScanAndTapButtonContaining(@"抽奖", &ghlLotteryLastTap, 10.0, @"自动开直播抽奖");
        }
        if (GHLGetBool(GHL_KEY_CUSTOM_TAB_BAR)) {
            GHLApplyCustomTabBar();
        }
        if (GHLGetBool(GHL_KEY_FAKE_STATS)) {
            UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
            UIViewController *controller = [DYYYFloatingButtonCoordinator currentInteractionController];
            if (controller) GHLApplyFakeStatsInView(controller.view);
            (void)window;
        }
        if (GHLGetBool(GHL_KEY_LIVE_AUDIO_MUTE)) {
            AVPlayer *player = GHLFindPlayingAVPlayer();
            if (GHLIsInLiveRoom() && player && player.volume > 0) {
                player.volume = 0;
                ghlLiveAudioMutedByUs = YES;
                GHLLog(@"直播音频：已单独静音");
            } else if (!GHLIsInLiveRoom() && ghlLiveAudioMutedByUs && player) {
                player.volume = 1.0;
                ghlLiveAudioMutedByUs = NO;
                GHLLog(@"直播音频：离开直播间，已恢复音量");
            }
        }
    } @catch (__unused NSException *exception) {
    }
    double tickDurationMs = (CFAbsoluteTimeGetCurrent() - tickStart) * 1000.0;
    GHLLog(@"巡检计时：本跳耗时 %.1fms，上跳间隔 %.0fms%@", tickDurationMs, tickIntervalMs,
           tickDurationMs > 500 ? @"（超过 500ms，疑似拖慢主线程）" : @"");
}

void GHLStartHousekeepingTimer(void) {
    if (ghlHousekeepingTimer) return;
    ghlHousekeepingTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           repeats:YES
                                                             block:^(NSTimer *timer) {
                                                               (void)timer;
                                                               GHLHousekeepingTick();
                                                             }];
    GHLLog(@"巡检定时器：已启动（2 秒一次，管红包/抽奖/直播时长/底栏/数字改写/直播静音/自动连播/消息手势）");
}

