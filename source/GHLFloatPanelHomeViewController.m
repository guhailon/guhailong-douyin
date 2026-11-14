// GHLFloatPanelHomeViewController — 卡片首页（1.0.22）
// 影片的做法：标题＋搜索框＋两列按键；照片里文件夹的浅色毛玻璃：卡片本身是
// UIVisualEffectView（ExtraLight，1.0.22 起更透），本页 view 透明、按键半透明白底＋金色图标＋深色字，
// 玻璃感从卡片底透出来。设置列表／关于页／日志页点按键在卡片内导航栈上推，
// 不是全屏（皇上：任何出来就是卡片界面）。推上去的页面背景是不透明的（1.0.22），
// 只有首页和卡片 10pt 边框露玻璃——不然上一页从下面透出来。
#import "GHLFloatPanelHomeViewController.h"

#import "DYYYSettingViewController.h"
#import "DYYYUtils.h"
#import "GHLAboutViewController.h"
#import "GHLFeatures.h"
#import "GHLLogViewerViewController.h"

// 按键：标题＋SF Symbol（金色）＋动作。
typedef NS_ENUM(NSInteger, GHLFloatPanelHomeAction) {
    GHLFloatPanelHomeActionSettings = 0, // 通用设置→设置列表根页
    GHLFloatPanelHomeActionHomeTab = 1,  // 首页→切抖音底栏（探针）
    GHLFloatPanelHomeActionFriendsTab = 2, // 朋友→切抖音底栏（探针）
    GHLFloatPanelHomeActionMessagesTab = 3, // 消息→切抖音底栏（探针）
    GHLFloatPanelHomeActionMineTab = 4,  // 我→切抖音底栏（探针）
    GHLFloatPanelHomeActionPlay = 5,     // 播放互动→设置列表「常用功能」分区
    GHLFloatPanelHomeActionDiagnose = 6, // 诊断反馈→顾海龙日志页
    GHLFloatPanelHomeActionAbout = 7,    // 关于→关于页
};

@interface GHLFloatPanelHomeViewController ()

@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, strong) NSMutableArray<UIButton *> *tileButtons;
@property(nonatomic, strong) NSArray<NSDictionary *> *tileSpecs;

@end

@implementation GHLFloatPanelHomeViewController

#pragma mark - 按键定义

// 标题、图标、动作一一对应（顺序就是两列从上到下的顺序）。
- (NSArray<NSDictionary *> *)ghl_tileSpecs {
    return @[
        @{@"title": @"通用设置", @"icon": @"gearshape", @"action": @(GHLFloatPanelHomeActionSettings)},
        @{@"title": @"首页", @"icon": @"house", @"action": @(GHLFloatPanelHomeActionHomeTab)},
        @{@"title": @"朋友", @"icon": @"person.2", @"action": @(GHLFloatPanelHomeActionFriendsTab)},
        @{@"title": @"消息", @"icon": @"message", @"action": @(GHLFloatPanelHomeActionMessagesTab)},
        @{@"title": @"我", @"icon": @"person", @"action": @(GHLFloatPanelHomeActionMineTab)},
        @{@"title": @"播放互动", @"icon": @"play.circle", @"action": @(GHLFloatPanelHomeActionPlay)},
        @{@"title": @"诊断反馈", @"icon": @"doc.text.magnifyingglass", @"action": @(GHLFloatPanelHomeActionDiagnose)},
        @{@"title": @"关于", @"icon": @"info.circle", @"action": @(GHLFloatPanelHomeActionAbout)},
    ];
}

// 播放互动对应的分区：「常用功能」（0）——画中画＋后台播放／记忆倍速／快进手势都在这里。
- (NSInteger)ghl_playSectionIndex {
    return 0;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"顾海龙抖音";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    // 卡片是浅色玻璃：本页强制浅色、view 透明，让卡片底的毛玻璃透出来。
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.view.backgroundColor = [UIColor clearColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(ghl_closeTapped)];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    // 搜索框：只过滤按键（影片里的做法；设置列表自己的搜索在设置页里）。
    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    searchBar.placeholder = @"搜索设置...";
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    [scrollView addSubview:searchBar];
    self.searchBar = searchBar;

    self.tileSpecs = [self ghl_tileSpecs];
    self.tileButtons = [NSMutableArray array];
    UIColor *gold = [DYYYUtils dYYYGoldAccentColor];
    for (NSInteger i = 0; i < (NSInteger)self.tileSpecs.count; i++) {
        NSDictionary *spec = self.tileSpecs[i];
        UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
        // 半透明白底＋细亮边＋圆角 14：玻璃上的按键（影片的按键感＋照片的浅色玻璃）。
        tile.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        tile.layer.cornerRadius = 14;
        tile.layer.borderWidth = 1.0;
        tile.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65].CGColor;
        tile.tag = i;
        [tile addTarget:self action:@selector(ghl_tileTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIImageView *iconView = [[UIImageView alloc] init];
        iconView.image = [UIImage systemImageNamed:spec[@"icon"]];
        iconView.tintColor = gold;
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tag = 1001;
        [tile addSubview:iconView];

        UILabel *label = [[UILabel alloc] init];
        label.text = spec[@"title"];
        label.font = [UIFont systemFontOfSize:15];
        label.textColor = [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1.0];
        label.textAlignment = NSTextAlignmentCenter;
        label.tag = 1002;
        [tile addSubview:label];

        [scrollView addSubview:tile];
        [self.tileButtons addObject:tile];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ghl_layoutTiles];
}

// 两列按键布局：只排没被搜索滤掉的（滤掉的藏起来不占位）。
- (void)ghl_layoutTiles {
    if (!self.scrollView) return;
    CGFloat width = self.view.bounds.size.width;
    if (width <= 0) return;
    CGFloat margin = 16;
    CGFloat spacing = 10;
    CGFloat searchHeight = 44;
    self.searchBar.frame = CGRectMake(margin, 12, width - margin * 2, searchHeight);
    CGFloat tileWidth = (width - margin * 2 - spacing) / 2;
    CGFloat tileHeight = 92;
    NSInteger visibleRow = 0;
    NSInteger visibleCol = 0;
    for (UIButton *tile in self.tileButtons) {
        if (tile.hidden) continue;
        CGFloat x = margin + visibleCol * (tileWidth + spacing);
        CGFloat y = 12 + searchHeight + 12 + visibleRow * (tileHeight + spacing);
        tile.frame = CGRectMake(x, y, tileWidth, tileHeight);
        UIImageView *iconView = [tile viewWithTag:1001];
        UILabel *label = [tile viewWithTag:1002];
        iconView.frame = CGRectMake((tileWidth - 34) / 2, 16, 34, 34);
        label.frame = CGRectMake(4, 56, tileWidth - 8, 20);
        visibleCol++;
        if (visibleCol >= 2) {
            visibleCol = 0;
            visibleRow++;
        }
    }
    NSInteger visibleCount = 0;
    for (UIButton *tile in self.tileButtons) {
        if (!tile.hidden) visibleCount++;
    }
    NSInteger rows = (NSInteger)ceil((double)MAX(visibleCount, 0) / 2.0);
    CGFloat contentHeight = 12 + searchHeight + 12 + rows * tileHeight + (rows > 0 ? (rows - 1) * spacing : 0) + 16;
    self.scrollView.frame = self.view.bounds;
    self.scrollView.contentSize = CGSizeMake(width, MAX(contentHeight, self.view.bounds.size.height));
}

#pragma mark - 搜索（只过滤按键）

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    NSString *query = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSInteger i = 0; i < (NSInteger)self.tileButtons.count; i++) {
        NSString *title = self.tileSpecs[i][@"title"];
        self.tileButtons[i].hidden = (query.length > 0 && [title rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound);
    }
    [self ghl_layoutTiles];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - 按键动作

- (void)ghl_closeTapped {
    GHLCloseFloatPanel();
}

- (void)ghl_tileTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.tileSpecs.count) return;
    NSDictionary *spec = self.tileSpecs[sender.tag];
    NSString *title = spec[@"title"] ?: @"";
    GHLFloatPanelHomeAction action = (GHLFloatPanelHomeAction)[spec[@"action"] integerValue];
    GHLLog(@"快捷面板：已点按键「%@」", title);
    switch (action) {
        case GHLFloatPanelHomeActionSettings: {
            // 通用设置→设置列表根页（卡片共用的那一份，推上去；已在栈里就回到它）。
            DYYYSettingViewController *settingsVC = GHLFloatPanelSharedSettingsViewController();
            settingsVC.ghlInFloatPanel = YES;
            if ([self.navigationController.viewControllers containsObject:settingsVC]) {
                [self.navigationController popToViewController:settingsVC animated:YES];
            } else {
                [self.navigationController pushViewController:settingsVC animated:YES];
            }
            break;
        }
        case GHLFloatPanelHomeActionPlay: {
            // 播放互动→设置列表「常用功能」分区（画中画／后台播放／快进手势／记忆倍速）。
            DYYYSettingViewController *subVC = [[DYYYSettingViewController alloc] initWithSectionIndex:[self ghl_playSectionIndex]];
            subVC.ghlInFloatPanel = YES;
            [self.navigationController pushViewController:subVC animated:YES];
            break;
        }
        case GHLFloatPanelHomeActionDiagnose: {
            GHLLogViewerViewController *logVC = [[GHLLogViewerViewController alloc] init];
            logVC.ghlInFloatPanel = YES;
            [self.navigationController pushViewController:logVC animated:YES];
            break;
        }
        case GHLFloatPanelHomeActionAbout: {
            GHLAboutViewController *aboutVC = [[GHLAboutViewController alloc] init];
            // 关于页里导出/导入/恢复默认三行要一个设置页实例当帮手（卡片共用的那一份；
            // 它不在栈里时，导出/导入的弹出改由最上层 VC 承接，见 DYYYSettingViewController）。
            aboutVC.settingsViewController = GHLFloatPanelSharedSettingsViewController();
            [self.navigationController pushViewController:aboutVC animated:YES];
            break;
        }
        case GHLFloatPanelHomeActionHomeTab:
            [self ghl_switchToTabNamed:@"首页"];
            break;
        case GHLFloatPanelHomeActionFriendsTab:
            [self ghl_switchToTabNamed:@"朋友"];
            break;
        case GHLFloatPanelHomeActionMessagesTab:
            [self ghl_switchToTabNamed:@"消息"];
            break;
        case GHLFloatPanelHomeActionMineTab:
            [self ghl_switchToTabNamed:@"我"];
            break;
    }
}

// 底栏切换（探针）：递归全树找底栏控制器再按标题匹配，找不到就如实记一行，不硬切。
// 切成功就关卡片，让皇上直接看到那一页。
// 1.0.22：旧探针只查 rootVC 沿 presented 链走到头＋其直接子级，-9.log 里 17 次点按全死在
// 「没找到底栏控制器」；但画中画 B 路递归枚举已证实 AWENormalModeTabBarController 确实在
// 窗口层级里，只是嵌得深（根很可能是 AWEBaseRootNavigationController）。所以改成像 B 路
// 那样遍历全部窗口的控制器树：是 UITabBarController 子类、或嵌在底栏里（tabBarController
// 属性非空）的都算找到；visited 防 presented/child 成环时死循环。
- (nullable UITabBarController *)ghl_findTabBarController {
    NSArray<UIWindow *> *windows = nil;
    if (@available(iOS 13.0, *)) {
        // 和 B 路的 GHLAllAppWindows 同一套思路：所有已连接 scene 的窗口都找一遍。
        NSMutableArray<UIWindow *> *all = [NSMutableArray array];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [all addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
        if (all.count > 0) windows = all;
    }
    if (!windows) windows = [UIApplication sharedApplication].windows;
    NSMutableSet<UIViewController *> *visited = [NSMutableSet set];
    for (UIWindow *window in windows) {
        UITabBarController *found = [self ghl_findTabBarControllerInVC:window.rootViewController visited:visited];
        if (found) return found;
    }
    return nil;
}

- (nullable UITabBarController *)ghl_findTabBarControllerInVC:(nullable UIViewController *)vc visited:(NSMutableSet<UIViewController *> *)visited {
    if (!vc || [visited containsObject:vc]) return nil;
    [visited addObject:vc];
    if ([vc isKindOfClass:[UITabBarController class]]) return (UITabBarController *)vc;
    // 嵌在底栏里的子页：tabBarController 属性直接指回底栏，不用再往下翻。
    if (vc.tabBarController) return vc.tabBarController;
    for (UIViewController *child in vc.childViewControllers) {
        UITabBarController *found = [self ghl_findTabBarControllerInVC:child visited:visited];
        if (found) return found;
    }
    if (vc.presentedViewController) {
        UITabBarController *found = [self ghl_findTabBarControllerInVC:vc.presentedViewController visited:visited];
        if (found) return found;
    }
    return nil;
}

- (void)ghl_switchToTabNamed:(NSString *)tabTitle {
    UITabBarController *tabBarController = [self ghl_findTabBarController];
    if (!tabBarController) {
        GHLLog(@"快捷面板：底栏「%@」没找到底栏控制器（探针，全树已找过）", tabTitle);
        return;
    }
    NSArray<UIViewController *> *tabs = tabBarController.viewControllers ?: @[];
    // 标题列表原样记下来：空标题记「（空）」，下次日志能定标题是不是空的。
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSInteger emptyCount = 0;
    for (UIViewController *vc in tabs) {
        NSString *title = vc.tabBarItem.title.length > 0 ? vc.tabBarItem.title : (vc.title.length > 0 ? vc.title : @"");
        if (title.length == 0) {
            emptyCount++;
            [titles addObject:@"（空）"];
        } else {
            [titles addObject:title];
        }
    }
    GHLLog(@"快捷面板：底栏控制器是 %@，共 %lu 个 tab（空标题 %ld 个），标题：%@", NSStringFromClass([tabBarController class]), (unsigned long)tabs.count, (long)emptyCount, titles.count > 0 ? [titles componentsJoinedByString:@"、"] : @"（无）");
    for (NSInteger i = 0; i < (NSInteger)tabs.count; i++) {
        UIViewController *vc = tabs[i];
        NSString *title = vc.tabBarItem.title.length > 0 ? vc.tabBarItem.title : (vc.title.length > 0 ? vc.title : @"");
        if ([title isEqualToString:tabTitle]) {
            tabBarController.selectedIndex = i;
            GHLLog(@"快捷面板：已切到底栏「%@」（探针，第 %ld 个）", tabTitle, (long)i);
            GHLCloseFloatPanel();
            return;
        }
    }
    GHLLog(@"快捷面板：底栏「%@」没找到（探针，标题里没有这一项）", tabTitle);
}

@end
