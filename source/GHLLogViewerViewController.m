// GHLLogViewerViewController — 顾海龙日志查看页（1.0.6）
// 读 GHLLogFilePath()（Documents/DYYY/GuHaiLongDouyin.log），只显示最后约 200KB；
// 刷新、清空（先弹确认框）、分享（系统分享单，和配置导出同一套）。
// 文件读在后台队列做，UI 回主线程；文件不存在或为空显示“暂无日志”，不崩。
#import "GHLLogViewerViewController.h"
#import "DYYYBottomAlertView.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

// 最多显示的字节数（超了只读最后这段，前面省略并在顶部注明）。
static const unsigned long long kGHLLogViewerMaxBytes = 200 * 1024;

@interface GHLLogViewerViewController ()
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
@property(nonatomic, strong, nullable) UIView *backgroundView;
@property(nonatomic, strong) UIBarButtonItem *shareItem;
@end

@implementation GHLLogViewerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"顾海龙日志";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(ghlRefreshLog)];
    self.shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(ghlShareLog)];
    self.navigationItem.rightBarButtonItems = @[ refreshItem, self.shareItem ];

    UITextView *textView = [[UITextView alloc] init];
    textView.editable = NO;
    textView.selectable = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
    self.textView = textView;

    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"清空日志" style:UIBarButtonItemStylePlain target:self action:@selector(ghlConfirmClearLog)];
    clearItem.tintColor = [UIColor systemRedColor];
    UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[ flexible, clearItem, flexible ];
    [self ghlApplyAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ghlApplyAppearance];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self ghlLoadLog];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
}

// 统一视觉：跟设置主页同一套（金色点缀、圆角卡片、深色跟随、自定义背景铺底）。
- (BOOL)ghlDarkModeActive {
    return GHLFollowSystemDarkEnabled() && [DYYYUtils isDarkMode];
}

- (void)ghlApplyAppearance {
    BOOL dark = [self ghlDarkModeActive];
    self.overrideUserInterfaceStyle = GHLFollowSystemDarkEnabled() ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleLight;
    self.backgroundImage = GHLCustomBackgroundImage();
    [self.backgroundView removeFromSuperview];
    UIView *backgroundView = [DYYYUtils dYYYSettingsBackgroundViewForImage:self.backgroundImage darkMode:dark];
    backgroundView.frame = self.view.bounds;
    backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:backgroundView atIndex:0];
    self.backgroundView = backgroundView;
    self.textView.backgroundColor = [DYYYUtils dYYYSettingsCellBackgroundColorForBackgroundImage:self.backgroundImage darkMode:dark];
    self.textView.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
}

- (void)ghlRefreshLog {
    [self ghlLoadLog];
}

// 文件读在后台做，读完回主线程刷 UI；日志再大也不会卡设置页。
- (void)ghlLoadLog {
    self.textView.text = @"正在加载日志…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      NSString *content = [self ghlReadCappedLogAtPath:GHLLogFilePath()];
      GHLRunOnMain(^{
        if (!content) {
            self.textView.text = @"暂无日志\n\n诊断日志还没生成。进抖音刷几个视频、动几个开关，日志就会写到 Documents/DYYY/GuHaiLongDouyin.log，再点右上角刷新查看。";
            return;
        }
        self.textView.text = content;
        // 滚到最后，看最新的一段。
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
      });
    });
}

// 只读最后约 200KB；文件不存在、为空或读失败返回 nil（不崩）。
- (nullable NSString *)ghlReadCappedLogAtPath:(nullable NSString *)path {
    if (!path) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!attrs) return nil;
    unsigned long long size = [attrs fileSize];
    if (size == 0) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    NSData *data = nil;
    BOOL truncated = NO;
    @try {
        if (size > kGHLLogViewerMaxBytes) {
            [handle seekToFileOffset:size - kGHLLogViewerMaxBytes];
            truncated = YES;
        }
        data = [handle readDataToEndOfFile];
    } @catch (__unused NSException *exception) {
        data = nil;
    } @finally {
        [handle closeFile];
    }
    if (!data || data.length == 0) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    // 从中间截断可能切到一行中间：丢掉第一行不完整的残行。
    if (truncated) {
        NSRange firstNewline = [text rangeOfString:@"\n"];
        if (firstNewline.location != NSNotFound) {
            text = [text substringFromIndex:firstNewline.location + 1];
        }
        text = [@"（日志较大，只显示最后约 200KB，前面已省略）\n\n" stringByAppendingString:text];
    }
    return text;
}

- (void)ghlConfirmClearLog {
    [DYYYBottomAlertView showAlertWithTitle:@"清空日志"
                                    message:@"会删掉 Documents/DYYY/GuHaiLongDouyin.log，下次写日志时重新生成。"
                                  avatarURL:nil
                           cancelButtonText:@"取消"
                          confirmButtonText:@"清空"
                               cancelAction:nil
                                closeAction:nil
                              confirmAction:^{
                                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                                  [[NSFileManager defaultManager] removeItemAtPath:GHLLogFilePath() error:nil];
                                  GHLRunOnMain(^{
                                    [DYYYUtils showToast:@"已清空日志"];
                                    [self ghlLoadLog];
                                  });
                                });
                              }];
}

- (void)ghlShareLog {
    NSString *path = GHLLogFilePath();
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [DYYYUtils showToast:@"暂无日志可分享"];
        return;
    }
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ [NSURL fileURLWithPath:path] ] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.barButtonItem = self.shareItem;
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

@end
