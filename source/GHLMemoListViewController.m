// GHLMemoListViewController — 文案备忘录（1.0.24，清单 20 号，只做备忘）
#import "GHLMemoListViewController.h"
#import "DYYYCustomInputView.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

static NSString *GHLMemoDateText(NSTimeInterval timestamp) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.dateFormat = @"yyyy-MM-dd HH:mm";
      formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

@interface GHLMemoListViewController () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *memos;
@property(nonatomic, strong) UILabel *emptyLabel;

@end

@implementation GHLMemoListViewController

#pragma mark - 存储

+ (NSMutableArray<NSDictionary *> *)ghl_loadMemos {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:GHL_KEY_MEMO_LIST];
    NSMutableArray<NSDictionary *> *memos = [NSMutableArray array];
    for (id item in stored) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = item[@"text"];
        if (![text isKindOfClass:[NSString class]] || text.length == 0) continue;
        NSNumber *date = item[@"date"];
        if (![date isKindOfClass:[NSNumber class]]) date = @([[NSDate date] timeIntervalSince1970]);
        [memos addObject:@{@"text": text, @"date": date}];
    }
    return memos;
}

+ (void)ghl_saveMemos:(NSArray<NSDictionary *> *)memos {
    [[NSUserDefaults standardUserDefaults] setObject:memos forKey:GHL_KEY_MEMO_LIST];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"文案备忘录";
    self.memos = [[self class] ghl_loadMemos];

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 64;
    [self.view addSubview:tableView];
    self.tableView = tableView;

    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = @"还没有备忘，点右上角 + 写一句";
    emptyLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    emptyLabel.font = [UIFont systemFontOfSize:15];
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    tableView.backgroundView = emptyLabel;
    self.emptyLabel = emptyLabel;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(ghl_addMemo)];

    [self ghl_applyAppearance];
    [self ghl_refreshEmptyState];
}

- (void)ghl_applyAppearance {
    if (self.ghlInFloatPanel) {
        // 卡片内：页底透明，共用卡片底的整张背景图；行半透明白，字看得清。
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
    } else {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
}

- (void)ghl_refreshEmptyState {
    self.emptyLabel.hidden = (self.memos.count > 0);
}

#pragma mark - 新增

- (void)ghl_addMemo {
    __weak typeof(self) weakSelf = self;
    DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"新增备忘"
                                                                     defaultText:@""
                                                                     placeholder:@"写一句文案…"];
    inputView.onConfirm = ^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            [DYYYUtils showToast:@"备忘是空的，没存"];
            return;
        }
        [strongSelf.memos insertObject:@{@"text": trimmed, @"date": @([[NSDate date] timeIntervalSince1970])} atIndex:0];
        [[self class] ghl_saveMemos:strongSelf.memos];
        [strongSelf.tableView reloadData];
        [strongSelf ghl_refreshEmptyState];
        [DYYYUtils showToast:@"已存到备忘录"];
    };
    inputView.onCancel = ^{};
    [inputView show];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.memos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"GHLMemoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    NSDictionary *memo = self.memos[(NSUInteger)indexPath.row];
    cell.textLabel.text = memo[@"text"];
    cell.detailTextLabel.text = GHLMemoDateText([memo[@"date"] doubleValue]);
    if (self.ghlInFloatPanel) {
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    } else {
        cell.backgroundColor = [UIColor whiteColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *text = self.memos[(NSUInteger)indexPath.row][@"text"];
    if (text.length == 0) return;
    [[UIPasteboard generalPasteboard] setString:text];
    [DYYYUtils showToast:@"已复制，去粘贴吧"];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self.memos removeObjectAtIndex:(NSUInteger)indexPath.row];
    [[self class] ghl_saveMemos:self.memos];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self ghl_refreshEmptyState];
}

@end
