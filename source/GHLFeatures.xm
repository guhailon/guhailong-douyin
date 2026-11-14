// 顾海龙抖音 (GHL) — 新增功能实现
// 基于 DYYY (MIT, Copyright (c) 2024 huami) 的个人二创，仅自用，不对外发布。
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
#import "DYYYToast.h"
#import <AVKit/AVKit.h>
#import <ReplayKit/ReplayKit.h>
#import <objc/runtime.h>

@class GHLFeatures;

@interface GHLFeatures : NSObject
@end

// 前向声明（part 4 定义，part 2 的左滑返回要用）
static UIViewController *GHLTopViewController(void);

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
           @"1.0.11：长按项开关默认全开（12 个 DYYY 开关，没存过值时才默认开，亲手关掉的不会被覆盖），普通视频的网格从 2 行（6 项）变成 4 行（9 项+更多；格子收小到 92pt，下面还有时显示滚动条）；面板设置里加「长按面板头像」，能从相册任意换头像或恢复默认龙头，换完下一次长按就生效，不用重启抖音；网格盖上时的日志补上各项标题。";
}

static void GHLCollectPlayerLayersInView(UIView *view, NSMutableArray<AVPlayerLayer *> *out) {
    if (!view) return;
    for (CALayer *sublayer in view.layer.sublayers ?: @[]) {
        if ([sublayer isKindOfClass:[AVPlayerLayer class]]) {
            [out addObject:(AVPlayerLayer *)sublayer];
        }
    }
    for (UIView *subview in view.subviews) {
        GHLCollectPlayerLayersInView(subview, out);
    }
}

AVPlayerLayer *GHLFindPlayingAVPlayerLayer(void) {
    __block AVPlayerLayer *found = nil;
    void (^collect)(void) = ^{
      @try {
          UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
          NSMutableArray<AVPlayerLayer *> *layers = [NSMutableArray array];
          GHLCollectPlayerLayersInView(window, layers);
          for (AVPlayerLayer *layer in layers) {
              AVPlayer *player = layer.player;
              if (player && player.rate > 0) {
                  found = layer;
                  break;
              }
          }
          if (!found && layers.count > 0) found = layers.firstObject;
      } @catch (__unused NSException *exception) {
      }
    };
    if ([NSThread isMainThread]) {
        collect();
    } else {
        dispatch_sync(dispatch_get_main_queue(), collect);
    }
    return found;
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

void GHLStartPiP(void) {
    GHLRunOnMain(^{
      if (![AVPictureInPictureController isPictureInPictureSupported]) {
          [DYYYUtils showToast:@"当前设备不支持画中画"];
          GHLLog(@"画中画：设备不支持");
          return;
      }
      AVPlayerLayer *layer = GHLFindPlayingAVPlayerLayer();
      if (!layer || !layer.player) {
          [DYYYUtils showToast:@"没找到正在播放的视频"];
          GHLLog(@"画中画：没找到播放器图层");
          return;
      }
      @try {
          ghlPiPController = [[AVPictureInPictureController alloc] initWithPlayerLayer:layer];
          [ghlPiPController startPictureInPicture];
          GHLLog(@"画中画：已启动");
      } @catch (NSException *exception) {
          [DYYYUtils showToast:@"画中画启动失败"];
          GHLLog(@"画中画启动失败：%@", exception.reason);
      }
    });
}

#pragma mark - (4) 记忆倍速（按作者）

static NSString *GHLAuthorKeyForModel(AWEAwemeModel *model) {
    AWEUserModel *author = model.author;
    if (!author) return nil;
    if (author.userID.length > 0) return author.userID;
    if (author.secUserID.length > 0) return author.secUserID;
    if (author.shortID.length > 0) return author.shortID;
    return author.nickname;
}

static void GHLRecordSpeedForCurrentAuthor(double speed) {
    if (!GHLGetBool(GHL_KEY_REMEMBER_SPEED_PER_AUTHOR)) return;
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    NSString *authorKey = GHLAuthorKeyForModel(model);
    if (!authorKey) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *speeds = [[defaults objectForKey:@"GHLAuthorSpeeds"] mutableCopy] ?: [NSMutableDictionary dictionary];
    speeds[authorKey] = @(speed);
    [defaults setObject:speeds forKey:@"GHLAuthorSpeeds"];
    GHLLog(@"记忆倍速：作者 %@ 记为 %.2f", authorKey, speed);
}

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

static void GHLApplyStoredSpeedForCurrentAuthor(void) {
    if (!GHLGetBool(GHL_KEY_REMEMBER_SPEED_PER_AUTHOR)) return;
    AWEAwemeModel *model = GHLCurrentAwemeModel();
    NSString *authorKey = GHLAuthorKeyForModel(model);
    if (!authorKey) return;
    NSNumber *speed = [[NSUserDefaults standardUserDefaults] objectForKey:@"GHLAuthorSpeeds"][authorKey];
    if (!speed) return;
    UIWindow *window = [DYYYUtils getActiveWindow] ?: [UIApplication sharedApplication].keyWindow;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    NSMutableArray *players = [NSMutableArray array];
    GHLFindPlayerViewControllersInVC(root, players);
    for (id playerVC in players) {
        if ([playerVC respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) {
            @try {
                [(AWEAwemePlayVideoViewController *)playerVC setVideoControllerPlaybackRate:[speed doubleValue]];
                GHLLog(@"记忆倍速：作者 %@ 恢复 %.2f", authorKey, [speed doubleValue]);
            } @catch (__unused NSException *exception) {
            }
            break;
        }
    }
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

@end

#pragma mark - Hooks

// (4) 记忆倍速：切视频后恢复该作者的倍速；倍速变化时记下来
%hook AWEFeedContainerViewController
- (void)aweme:(id)arg1 currentIndexDidChange:(NSInteger)arg2 {
    %orig;
    if (GHLGetBool(GHL_KEY_REMEMBER_SPEED_PER_AUTHOR)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          GHLApplyStoredSpeedForCurrentAuthor();
        });
    }
    GHLMaybeAutoLike();
}
%end

%hook AWEAwemePlayVideoViewController
- (void)setVideoControllerPlaybackRate:(double)arg0 {
    %orig;
    GHLRecordSpeedForCurrentAuthor(arg0);
}
%end

%hook AWEDPlayerFeedPlayerViewController
- (void)setVideoControllerPlaybackRate:(double)arg0 {
    %orig;
    GHLRecordSpeedForCurrentAuthor(arg0);
}
%end

%hook AWEDPlayerViewController_Merge
- (void)setVideoControllerPlaybackRate:(double)arg0 {
    %orig;
    GHLRecordSpeedForCurrentAuthor(arg0);
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
    %orig;
    GHLApplySidebarOrderInView(self.view);
    // 1.0.8：右侧边栏美化在排序之后跑（缩放/间距/圆角底）。
    GHLApplySidebarBeautifyInView(self.view);
    GHLApplyInterfaceScaleInView(self.view);
    GHLApplyFakeStatsInView(self.view);
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
        GHLLog(@"顾海龙抖音 1.0.11 已加载（基于 DYYY MIT，仅自用）");
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          GHLHandleScreenshotTaken(note);
                        }];
        [center addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          GHLHandleVolumeChange(note);
                        }];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                          if (GHLGetBool(GHL_KEY_BACKGROUND_AUDIO)) {
                              GHLStartPiP();
                          }
                        }];
        GHLStartHousekeepingTimer();
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

NSArray<GHLVoicePackageInfo *> *GHLVoicePackageList(void) {
    NSMutableArray<GHLVoicePackageInfo *> *all = [NSMutableArray arrayWithArray:GHLBuiltInVoicePackages()];
    [all addObjectsFromArray:GHLFishAudioVoicePackages()];
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
    for (GHLVoicePackageInfo *info in GHLVoicePackageList()) [ids addObject:info.voiceId];
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

@interface GHLVoicePackageManagerViewController : UITableViewController <UISearchBarDelegate>
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新在线" style:UIBarButtonItemStylePlain target:self action:@selector(ghlRefreshOnline)];
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
        if (error) {
            [DYYYUtils showToast:@"拉取失败，检查 key 和网络"];
        } else {
            [DYYYUtils showToast:[NSString stringWithFormat:@"拉到 %lu 个在线音色", (unsigned long)voices.count]];
        }
        [self.tableView reloadData];
      });
    });
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
    if (![categories[section] isEqualToString:@"在线"]) return nil;
    NSString *apiKey = GHLFishAudioAPIKey();
    if (apiKey.length == 0) return @"在线音色要先在设置页填写 Fish Audio API Key，填完点右上角“刷新在线”拉取。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GHLVoicePackageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    NSArray *categories = [self ghlVisibleCategories];
    GHLVoicePackageInfo *info = [self ghlPackagesInCategory:categories[indexPath.section]][indexPath.row];
    cell.textLabel.text = info.displayName;
    cell.detailTextLabel.text = info.voiceId;
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
    checkLabel.hidden = !selected;
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
// 已知：AWECommentAudioModel 只有 content（NSString）一个属性，未确认音频 URL 字段；
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

#pragma mark 巡检定时器（2 秒一次）

void GHLHousekeepingTick(void) {
    @try {
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
}

void GHLStartHousekeepingTimer(void) {
    if (ghlHousekeepingTimer) return;
    ghlHousekeepingTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           repeats:YES
                                                             block:^(NSTimer *timer) {
                                                               (void)timer;
                                                               GHLHousekeepingTick();
                                                             }];
    GHLLog(@"巡检定时器：已启动（2 秒一次，管红包/抽奖/直播时长/底栏/数字改写/直播静音）");
}

