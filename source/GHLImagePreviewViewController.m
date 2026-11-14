// GHLImagePreviewViewController — 图集图片全屏翻页预览（1.0.23，长按面板「图片预览」）
#import "GHLImagePreviewViewController.h"

@interface GHLImagePreviewViewController () <UIScrollViewDelegate>

@property(nonatomic, copy) NSArray<NSURL *> *imageURLs;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UILabel *pageLabel;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIImageView *> *pageImageViews;

@end

@implementation GHLImagePreviewViewController

- (instancetype)initWithImageURLs:(NSArray<NSURL *> *)imageURLs {
    self = [super init];
    if (!self) return nil;
    _imageURLs = [imageURLs copy];
    _pageImageViews = [NSMutableDictionary dictionary];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.pagingEnabled = YES;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.delegate = self;
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    for (NSInteger i = 0; i < (NSInteger)self.imageURLs.count; i++) {
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.backgroundColor = [UIColor blackColor];
        [scrollView addSubview:imageView];
        self.pageImageViews[@(i)] = imageView;
    }

    UILabel *pageLabel = [[UILabel alloc] init];
    pageLabel.textColor = [UIColor whiteColor];
    pageLabel.font = [UIFont systemFontOfSize:14];
    pageLabel.textAlignment = NSTextAlignmentCenter;
    pageLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    pageLabel.layer.cornerRadius = 11;
    pageLabel.layer.masksToBounds = YES;
    [self.view addSubview:pageLabel];
    self.pageLabel = pageLabel;

    // 点一下关闭（再加右上角关闭按钮，两个都能关）。
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ghl_dismiss)];
    [self.view addGestureRecognizer:tap];
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"✕ 关闭" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [closeButton addTarget:self action:@selector(ghl_dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
    ]];

    [self ghl_layoutPages];
    [self ghl_updatePageLabel];
    [self ghl_loadVisiblePages];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ghl_layoutPages];
    self.pageLabel.frame = CGRectMake((self.view.bounds.size.width - 80) / 2,
                                      self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 44,
                                      80, 22);
}

- (void)ghl_layoutPages {
    CGSize size = self.view.bounds.size;
    if (size.width <= 0) return;
    self.scrollView.frame = self.view.bounds;
    self.scrollView.contentSize = CGSizeMake(size.width * self.imageURLs.count, size.height);
    for (NSInteger i = 0; i < (NSInteger)self.imageURLs.count; i++) {
        self.pageImageViews[@(i)].frame = CGRectMake(i * size.width, 0, size.width, size.height);
    }
}

- (void)ghl_loadVisiblePages {
    if (self.imageURLs.count == 0) return;
    NSInteger page = (NSInteger)round(self.scrollView.contentOffset.x / MAX(self.view.bounds.size.width, 1));
    for (NSInteger i = MAX(0, page - 1); i <= MIN((NSInteger)self.imageURLs.count - 1, page + 1); i++) {
        [self ghl_loadPage:i];
    }
}

- (void)ghl_loadPage:(NSInteger)page {
    UIImageView *imageView = self.pageImageViews[@(page)];
    if (!imageView || imageView.image) return;
    NSURL *url = self.imageURLs[page];
    // 正在下载的标记：tag 是下载中（1），避免滚动回来重复下载。
    if (imageView.tag == 1) return;
    imageView.tag = 1;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                                 UIImage *image = (data.length > 0) ? [UIImage imageWithData:data] : nil;
                                                                 if (image) {
                                                                     imageView.image = image;
                                                                 } else {
                                                                     imageView.tag = 0;
                                                                     (void)response;
                                                                     (void)error;
                                                                 }
                                                               });
                                                             }];
    [task resume];
}

- (void)ghl_updatePageLabel {
    NSInteger page = (NSInteger)round(self.scrollView.contentOffset.x / MAX(self.view.bounds.size.width, 1)) + 1;
    page = MAX(1, MIN(page, (NSInteger)self.imageURLs.count));
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %lu", (long)page, (unsigned long)self.imageURLs.count];
}

- (void)ghl_dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    (void)scrollView;
    [self ghl_updatePageLabel];
    [self ghl_loadVisiblePages];
}

@end
