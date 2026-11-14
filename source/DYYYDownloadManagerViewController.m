// DYYYDownloadManagerViewController — 下载管理页（1.0.4）
#import "DYYYDownloadManagerViewController.h"
#import "DYYYBottomAlertView.h"
#import "DYYYManager.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

@interface DYYYDownloadManagerViewController ()
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
@end

@implementation DYYYDownloadManagerViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"下载管理";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self ghlApplyAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ghlApplyAppearance];
    [self.tableView reloadData];
}

// 统一视觉：跟设置主页同一套（金色点缀、圆角卡片、深色跟随、自定义背景铺底）。
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"下载统计" : @"缓存清理";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"下载的视频/图片直接存进相册，这里不保留文件清单；成功次数从 1.0.4 起统计，批量下载按文件记。";
    return @"只清理本插件自己的临时文件（下载中转、合成产物），不会删相册里的东西，也不会动抖音自己的缓存。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GHLDownloadManagerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
    }
    BOOL dark = [self ghlDarkModeActive];
    cell.backgroundColor = [DYYYUtils dYYYSettingsCellBackgroundColorForBackgroundImage:self.backgroundImage darkMode:dark];
    cell.textLabel.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
    cell.detailTextLabel.textColor = [DYYYUtils dYYYSettingsSecondaryTextColorDarkMode:dark];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.textLabel.text = @"成功下载（自 1.0.4 起）";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 次", (long)[DYYYManager ghlSavedMediaCount]];
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        cell.textLabel.text = @"临时缓存占用";
        cell.detailTextLabel.text = [DYYYUtils formattedSize:[DYYYManager ghlOurTemporaryCacheSize]];
    } else {
        cell.textLabel.text = @"清理临时缓存";
        cell.detailTextLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    [DYYYBottomAlertView showAlertWithTitle:@"清理临时缓存"
                                     message:@"只清理本插件自己的临时文件（下载中转、合成产物），不会删相册里的东西。"
                                   avatarURL:nil
                            cancelButtonText:@"取消"
                           confirmButtonText:@"清理"
                                cancelAction:nil
                                 closeAction:nil
                               confirmAction:^{
                                 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                                   unsigned long long freed = [DYYYManager ghlClearOurTemporaryCache];
                                   GHLRunOnMain(^{
                                     [DYYYUtils showToast:[NSString stringWithFormat:@"已清理 %@", [DYYYUtils formattedSize:freed]]];
                                     [self.tableView reloadData];
                                   });
                                 });
                               }];
}

@end
