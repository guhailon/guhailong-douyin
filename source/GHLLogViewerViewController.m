// GHLLogViewerViewController — 抖音日志查看页（1.0.6）
// 读 GHLLogFilePath()（Documents/DYYY/GuHaiLongDouyin.log），只显示最后约 200KB；
// 刷新、清空（先弹确认框）、分享（系统分享单，和配置导出同一套）。
// 1.0.20：加「复制日志」文字按钮（整份日志拷到剪贴簿）＋搜索框（过滤日志行）。
// 文件读在后台队列做，UI 回主线程；文件不存在或为空显示“暂无日志”，不崩。
#import "GHLLogViewerViewController.h"
#import "DYYYBottomAlertView.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

// 最多显示的字节数（超了只读最后这段，前面省略并在顶部注明）。
static const unsigned long long kGHLLogViewerMaxBytes = 200 * 1024;

@interface GHLLogViewerViewController () <UISearchBarDelegate>
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
@property(nonatomic, strong, nullable) UIView *backgroundView;
@property(nonatomic, strong) UIBarButtonItem *shareItem;
// 1.0.20：搜索框＋整份日志原文（过滤和复制都用它；textView 只负责显示）。
@property(nonatomic, strong, nullable) UISearchBar *searchBar;
@property(nonatomic, strong, nullable) NSString *fullLogText;
@end

@implementation GHLLogViewerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"抖音日志";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(ghlRefreshLog)];
    self.shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(ghlShareLog)];
    self.navigationItem.rightBarButtonItems = @[ refreshItem, self.shareItem ];

    // 1.0.20：搜索框（过滤日志行，搜「语音包」「错误」等；右上角图标可能被导航栏底色糊掉，
    // 文字按钮不会——复制放到底部工具列，和清空放一起）。
    UISearchBar *searchBar = [[UISearchBar alloc] init];
    searchBar.placeholder = @"搜索日志，如：语音包、错误";
    searchBar.delegate = self;
    searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:searchBar];
    [NSLayoutConstraint activateConstraints:@[
        [searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [searchBar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [searchBar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];
    self.searchBar = searchBar;

    UITextView *textView = [[UITextView alloc] init];
    textView.editable = NO;
    textView.selectable = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:searchBar.bottomAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
    self.textView = textView;

    UIBarButtonItem *copyItem = [[UIBarButtonItem alloc] initWithTitle:@"复制日志" style:UIBarButtonItemStylePlain target:self action:@selector(ghlCopyLog)];
    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"清空日志" style:UIBarButtonItemStylePlain target:self action:@selector(ghlConfirmClearLog)];
    clearItem.tintColor = [UIColor systemRedColor];
    UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[ flexible, copyItem, flexible, clearItem, flexible ];
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
// 1.0.22：卡片内不铺自定义背景图、页底和日志底都改不透明（1.0.21 是半透明，
// 背后的视频透过日志文字显示，行尾还被裁到卡片外面；玻璃感只留给卡片外壳）。
- (BOOL)ghlDarkModeActive {
    if (self.ghlInFloatPanel) return NO; // 卡片内永远按浅色算，深色字才看得清
    return GHLFollowSystemDarkEnabled() && [DYYYUtils isDarkMode];
}

- (void)ghlApplyAppearance {
    if (self.ghlInFloatPanel) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.backgroundImage = nil;
        [self.backgroundView removeFromSuperview];
        self.backgroundView = nil;
        // 1.0.24：卡片内页底/日志底都透明，共用卡片底的整张背景图；
        // 日志字是深色，图上有淡白遮罩，看得清。
        self.view.backgroundColor = [UIColor clearColor];
        self.textView.backgroundColor = [UIColor clearColor];
        self.textView.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        self.searchBar.backgroundColor = [UIColor clearColor];
        return;
    }
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
            self.fullLogText = nil;
            self.textView.text = @"暂无日志\n\n诊断日志还没生成。进抖音刷几个视频、动几个开关，日志就会写到 Documents/DYYY/GuHaiLongDouyin.log，再点右上角刷新查看。";
            return;
        }
        self.fullLogText = content;
        // 1.0.22：重读记一行（每次打开都重新读文件，见 viewWillAppear；这行能从下次日志里验重读到底跑没跑）。
        GHLLog(@"日志页：已重新读文件（%lu 字节）", (unsigned long)content.length);
        [self ghlApplyLogFilter];
      });
    });
}

// 1.0.20：按搜索框过滤日志行（大小写不敏感；没搜就显示整份，滚到最后看最新一段；
// 有搜就只显示命中的行，滚到最上面看第一条命中）。
// 1.0.21：第 8 项——搜索记一行（同一 query 只记一次：搜什么、命中几行，方便从日志验证）。
- (void)ghlApplyLogFilter {
    if (!self.fullLogText) return; // 还没读出来（正在加载或暂无日志），不动
    NSString *query = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    static NSString *lastLoggedQuery = nil;
    if (![query isEqualToString:lastLoggedQuery ?: @""]) {
        lastLoggedQuery = [query copy];
        if (query.length == 0) {
            GHLLog(@"日志页：搜索已清空");
        } else {
            NSInteger hits = 0;
            for (NSString *line in [self.fullLogText componentsSeparatedByString:@"\n"]) {
                if ([line.lowercaseString containsString:query.lowercaseString]) hits++;
            }
            GHLLog(@"日志页：搜索「%@」，命中 %ld 行", query, (long)hits);
        }
    }
    if (query.length == 0) {
        self.textView.text = self.fullLogText;
        // 1.0.22：滚到底必须等排版完再滚——以前同步调 scrollRangeToVisible 时文本框还没算好
        // contentSize，滚不动，页面一直停在最上面（录屏里看到的就是最上面那段旧日志：
        // 开头的「只显示最后约 200KB」＋17:18 的行，最新内容其实在下面，要手动滑到底才看得到）。
        // 先强制排版，再下一轮主线程里按 contentSize 滚到底；没搜的时候才滚到底。
        [self.textView layoutIfNeeded];
        dispatch_async(dispatch_get_main_queue(), ^{
          CGFloat bottom = MAX(0, self.textView.contentSize.height - self.textView.bounds.size.height + self.textView.contentInset.bottom);
          [self.textView setContentOffset:CGPointMake(0, bottom) animated:NO];
        });
        return;
    }
    NSString *lowerQuery = query.lowercaseString;
    NSMutableArray<NSString *> *matched = [NSMutableArray array];
    for (NSString *line in [self.fullLogText componentsSeparatedByString:@"\n"]) {
        if ([line.lowercaseString containsString:lowerQuery]) [matched addObject:line];
    }
    if (matched.count == 0) {
        self.textView.text = [NSString stringWithFormat:@"没有匹配「%@」的行", query];
    } else {
        self.textView.text = [matched componentsJoinedByString:@"\n"];
    }
    [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    (void)searchText;
    [self ghlApplyLogFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

// 1.0.20：复制整份日志到剪贴簿（不过滤——搜着的时候点的也是整份）。
- (void)ghlCopyLog {
    NSString *text = self.fullLogText;
    if (!text || text.length == 0) {
        [DYYYUtils showToast:@"暂无日志可复制"];
        return;
    }
    [UIPasteboard generalPasteboard].string = text;
    [DYYYUtils showToast:@"已复制日志"];
    GHLLog(@"抖音日志：已复制日志（%lu 字节）", (unsigned long)text.length);
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
    if (!text) {
        // 1.0.16：截断点可能切到多字节字符（中文 3 字节）中间，整段就解不出来、页面变「暂无日志」。
        // 往后挪 1–3 字节再试（UTF-8 一个字符最多 4 字节），挪到合法边界就解得出来；再不行才返回 nil。
        for (NSUInteger skip = 1; skip <= 3 && skip < data.length; skip++) {
            text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(skip, data.length - skip)] encoding:NSUTF8StringEncoding];
            if (text) break;
        }
    }
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
