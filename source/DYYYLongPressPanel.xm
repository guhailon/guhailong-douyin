#import "AwemeHeaders.h"
#import "GHLFeatures.h"
#import "DYYYBottomAlertView.h"
#import "DYYYConfirmCloseView.h"
#import "DYYYCustomInputView.h"
#import "DYYYFilterSettingsView.h"
#import "DYYYKeywordListView.h"
#import "DYYYLongPressGridPanelView.h"
#import "DYYYManager.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"

// ===== 1.0.9/1.0.10：网格长按面板用的缓存（放文件顶部，dataArray 钩子在下面就用）=====
// 1.0.9 用的是弱引用：dataArray 一返回、表格还没取完数据之前弱引用就可能死掉，
// 结果就是皇上真机上网格一次都没盖上、日志里连一行“长按面板”都没有（1.0.10 之前
// 所有失败分支都是静默 return）。1.0.10 改成强引用，持有到面板收起。
// 强引用经 viewModel 的 action block（block 捕获了面板控制器）会留住控制器，
// 所以收起时必须放掉：viewDidDisappear 判定已收起 / dealloc / 下滑收起
// 都会清缓存；同一时间只可能有一个长按面板，用全局变量没问题。
// 1.0.15：没有「更多」了——长按只出网格，原生面板不再出现；「已回原生不再重盖」的
// 标记（gDYYYLongPressGridPanelNativeVC）随之删掉。
static NSArray *gDYYYLongPressPanelData = nil;
// 当前盖在面板上的网格视图（弱引用：它由面板控制器的 view 持有，收起后自动释放）。
static __weak DYYYLongPressGridPanelView *gDYYYLongPressGridPanel = nil;
// 1.0.10：诊断日志去重用的状态——同一控制器、同一原因只记一行（viewDidLayoutSubviews
// 每轮布局都会调盖网格函数，不去重会刷屏；控制器换了或原因变了就再记一行）。
static __weak UIViewController *gDYYYLongPressGridDiagVC = nil;
static NSString *gDYYYLongPressGridDiagReason = nil;
// 前置声明（dataArray 钩子在 1.0.9 的盖网格函数之前就用到）。
static void DYYYShowLongPressGridPanelIfNeeded(UIViewController *vc);
static void DYYYLongPressGridPanelRetryAfterData(UIViewController *vc);
static UITableView *_Nullable DYYYLongPressFindTableViewInView(UIView *view);
// 1.0.24：网格盖上时藏起来的原生 table 所在的面板控制器（弱引用；收起时恢复显示）。
static __weak UIViewController *gDYYYLongPressGridHiddenVC = nil;

%hook AWELongPressPanelViewGroupModel
%property(nonatomic, assign) BOOL isDYYYCustomGroup;
%end

// Modern风格长按面板（新版UI）
%hook AWEModernLongPressPanelTableViewController
- (NSArray *)dataArray {
    [DYYYManager setAlbumDescriptionContextWithAwemeModel:self.awemeModel];
    // 检查是否开启精简模式
    BOOL simplifyPanel = DYYYGetBool(@"DYYYSimplifyLongPressPanel");

    NSArray *originalArray = %orig;
    if (!originalArray) {
        originalArray = @[];
    }

    // 如果开启精简模式，直接跳过原始面板处理，只返回自定义选项
    if (simplifyPanel) {
        originalArray = @[]; // 清空原始数组
    } else {
        // 获取需要隐藏的按钮设置（从文本输入框读取，逗号分隔）
        NSString *hidePanelItems = DYYYGetString(@"DYYYHidePanelItems");
        NSMutableSet<NSString *> *hideItemsLowerSet = [NSMutableSet set];

        if (hidePanelItems && hidePanelItems.length > 0) {
            // 支持中英文逗号分隔
            NSString *normalizedItems = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
            NSArray *items = [normalizedItems componentsSeparatedByString:@","];
            for (NSString *item in items) {
                NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedItem.length > 0) {
                    [hideItemsLowerSet addObject:[trimmedItem lowercaseString]];
                }
            }
        }

        // 如果有需要隐藏的项目，才进行过滤
        if (hideItemsLowerSet.count > 0) {
            NSMutableArray *modifiedOriginalGroups = [NSMutableArray array];

            for (id group in originalArray) {
                if ([group isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                    AWELongPressPanelViewGroupModel *groupModel = (AWELongPressPanelViewGroupModel *)group;
                    NSMutableArray *filteredGroupArr = [NSMutableArray array];

                    for (id item in groupModel.groupArr) {
                        if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                            AWELongPressPanelBaseViewModel *viewModel = (AWELongPressPanelBaseViewModel *)item;
                            NSString *descString = viewModel.describeString;

                            BOOL shouldHide = NO;
                            if (descString && descString.length > 0) {
                                NSString *descLower = [descString lowercaseString];

                                // 精确匹配
                                if ([hideItemsLowerSet containsObject:descLower]) {
                                    shouldHide = YES;
                                } else {
                                    // 部分匹配
                                    for (NSString *hideItemLower in hideItemsLowerSet) {
                                        if ([descLower containsString:hideItemLower] || [hideItemLower containsString:descLower]) {
                                            shouldHide = YES;
                                            break;
                                        }
                                    }
                                }
                            }

                            if (!shouldHide) {
                                [filteredGroupArr addObject:item];
                            }
                        } else {
                            [filteredGroupArr addObject:item];
                        }
                    }

                    if (filteredGroupArr.count > 0) {
                        AWELongPressPanelViewGroupModel *filteredGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
                        filteredGroup.groupType = groupModel.groupType;
                        filteredGroup.isModern = groupModel.isModern;
                        filteredGroup.groupArr = filteredGroupArr;
                        [modifiedOriginalGroups addObject:filteredGroup];
                    }
                } else {
                    [modifiedOriginalGroups addObject:group];
                }
            }
            originalArray = modifiedOriginalGroups;
        }
    }

    // 检查是否启用了任意长按功能
    BOOL hasAnyFeatureEnabled = NO;
    // 检查各个单独的功能开关
    BOOL enableSaveVideo = DYYYGetBool(@"DYYYLongPressSaveVideo");
    BOOL enableSaveCover = DYYYGetBool(@"DYYYLongPressSaveCover");
    BOOL enableSaveAudio = DYYYGetBool(@"DYYYLongPressSaveAudio");
    BOOL enableSaveCurrentImage = DYYYGetBool(@"DYYYLongPressSaveCurrentImage");
    BOOL enableSaveAllImages = DYYYGetBool(@"DYYYLongPressSaveAllImages");
    BOOL enableCopyText = DYYYGetBool(@"DYYYLongPressCopyText");
    BOOL enableCopyLink = DYYYGetBool(@"DYYYLongPressCopyLink");
    BOOL enableApiDownload = DYYYGetBool(@"DYYYLongPressApiDownload");
    BOOL enableFilterUser = DYYYGetBool(@"DYYYLongPressFilterUser");
    BOOL enableFilterKeyword = DYYYGetBool(@"DYYYLongPressFilterTitle");
    BOOL enableTimerClose = DYYYGetBool(@"DYYYLongPressTimerClose");
    BOOL enableCreateVideo = DYYYGetBool(@"DYYYLongPressCreateVideo");

    // 检查是否有任何功能启用
    hasAnyFeatureEnabled = enableSaveVideo || enableSaveCover || enableSaveAudio || enableSaveCurrentImage || enableSaveAllImages || enableCopyText || enableCopyLink || enableApiDownload ||
                           enableFilterUser || enableFilterKeyword || enableTimerClose || enableCreateVideo ||
                           GHLGetBool(GHL_KEY_EXTRACT_AUDIO) || GHLGetBool(GHL_KEY_NO_WATERMARK_SHARE_LINK) ||
                           GHLGetBool(GHL_KEY_BACKGROUND_AUDIO) || GHLGetBool(GHL_KEY_VOICE_PACKAGE) ||
                           GHLGetBool(GHL_KEY_SAVE_AVATAR) || GHLGetBool(GHL_KEY_COPY_PROFILE) || GHLGetBool(GHL_KEY_AUDIO_SHARE);

    // 如果没有任何功能启用，仅使用官方按钮
    if (!hasAnyFeatureEnabled) {
        return originalArray;
    }

    // 创建自定义功能按钮
    NSMutableArray *viewModels = [NSMutableArray array];

    BOOL isNewLivePhoto = (self.awemeModel.video && self.awemeModel.animatedImageVideoInfo != nil);

    // 视频下载功能 (非实况照片才显示)
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && !isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        downloadViewModel.awemeModel = self.awemeModel;
        downloadViewModel.actionType = 666;
        downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        downloadViewModel.describeString = @"保存视频";
        downloadViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          AWEMusicModel *musicModel = awemeModel.music;
          NSURL *audioURL = nil;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
          }

                  if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                      NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                      [DYYYManager downloadMedia:url
                                       mediaType:MediaTypeVideo
                                           audio:audioURL
                                      completion:^(BOOL success){
                                      }];
                  }
              
          
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:downloadViewModel];
    }

    //  新版实况照片保存
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *livePhotoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        livePhotoViewModel.awemeModel = self.awemeModel;
        livePhotoViewModel.actionType = 679;
        livePhotoViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        livePhotoViewModel.describeString = @"保存实况";
        livePhotoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;

          // 使用封面URL作为图片URL
          NSURL *imageURL = nil;
          if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
          }

          // 视频URL从视频模型获取
          NSURL *videoURL = nil;
          if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
          } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
          }

          // 下载实况照片
          if (imageURL && videoURL) {
              [DYYYManager downloadLivePhoto:imageURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:livePhotoViewModel];
    }

    // 当前图片/实况下载功能
    if (enableSaveCurrentImage && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
        AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imageViewModel.awemeModel = self.awemeModel;
        imageViewModel.actionType = 669;
        imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";

        if (self.awemeModel.albumImages.count == 1) {
            imageViewModel.describeString = @"保存图片";
        } else {
            imageViewModel.describeString = @"保存当前图片";
        }

        AWEImageAlbumImageModel *currimge = self.awemeModel.albumImages[self.awemeModel.currentImageIndex - 1];
        if (currimge.clipVideo != nil || self.awemeModel.isLivePhoto) {
            if (self.awemeModel.albumImages.count == 1) {
                imageViewModel.describeString = @"保存实况";
            } else {
                imageViewModel.describeString = @"保存当前实况";
            }
        }
        imageViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEImageAlbumImageModel *currentImageModel = nil;
          if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
              currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
          } else {
              currentImageModel = awemeModel.albumImages.firstObject;
          }
          // 如果是实况的话
          // 查找非.image后缀的URL
          NSURL *downloadURL = nil;
          for (NSString *urlString in currentImageModel.urlList) {
              NSURL *url = [NSURL URLWithString:urlString];
              NSString *pathExtension = [url.path.lowercaseString pathExtension];
              if (![pathExtension isEqualToString:@"image"]) {
                  downloadURL = url;
                  break;
              }
          }

          if (currentImageModel.clipVideo != nil) {
              NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
              [DYYYManager downloadLivePhoto:downloadURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          } else if (currentImageModel && currentImageModel.urlList.count > 0) {
              if (downloadURL) {
                  [DYYYManager downloadMedia:downloadURL
                                   mediaType:MediaTypeImage
                                       audio:nil
                                  completion:^(BOOL success) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:@"图片保存已取消"];
                                    }
                                  }];
              } else {
                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
              }
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imageViewModel];
    }

    // 保存所有图片/实况功能
    if (enableSaveAllImages && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 1) {
        AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        allImagesViewModel.awemeModel = self.awemeModel;
        allImagesViewModel.actionType = 670;
        allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        allImagesViewModel.describeString = @"保存所有图片";
        // 检查是否有实况照片并更改按钮文字
        BOOL hasLivePhoto = NO;
        for (AWEImageAlbumImageModel *imageModel in self.awemeModel.albumImages) {
            if (imageModel.clipVideo != nil) {
                hasLivePhoto = YES;
                break;
            }
        }
        if (hasLivePhoto) {
            allImagesViewModel.describeString = @"保存所有实况";
        }
        allImagesViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSMutableArray *imageURLs = [NSMutableArray array];
          NSMutableArray *livePhotos = [NSMutableArray array];

          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSURL *downloadURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          downloadURL = url;
                          break;
                      }
                  }

                  if (!downloadURL && imageModel.urlList.count > 0) {
                      downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                  }

                  // 检查是否是实况照片
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                  } else {
                      [imageURLs addObject:downloadURL.absoluteString];
                  }
              }
          }

          // 分别处理普通图片和实况照片
          if (livePhotos.count > 0) {
              [DYYYManager downloadAllLivePhotos:livePhotos];
          }

          if (imageURLs.count > 0) {
              [DYYYManager downloadAllImages:imageURLs];
          }

          if (livePhotos.count == 0 && imageURLs.count == 0) {
              [DYYYUtils showToast:@"没有找到合适格式的图片"];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:allImagesViewModel];
    }

    // 接口保存功能
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
    // 1.0.23 第二批：49 接口保存——没填接口地址也显示，点按时提示去设置里填（跟他的一键保存做法一致，按钮一直都在）。
    if (enableApiDownload) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存";
        apiDownload.action = ^{
          if (apiKey.length == 0) {
              [DYYYUtils showToast:@"先在设置 → 功能设置 → 接口解析保存媒体 里填接口地址"];
              return;
          }
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          if (shareLink.length == 0) {
              [DYYYUtils showToast:@"无法获取分享链接"];
              return;
          }
          // 使用封装的方法进行解析下载
          [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:apiDownload];
    }

    // 封面下载功能
    if (enableSaveCover && self.awemeModel.awemeType != 68) {
        AWELongPressPanelBaseViewModel *coverViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        coverViewModel.awemeModel = self.awemeModel;
        coverViewModel.actionType = 667;
        coverViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        coverViewModel.describeString = @"保存封面";
        coverViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          if (videoModel && videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                if (success) {
                                } else {
                                    [DYYYUtils showToast:@"封面保存已取消"];
                                }
                              }];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:coverViewModel];
    }

    // 音频下载功能
    if (enableSaveAudio) {
        AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioViewModel.awemeModel = self.awemeModel;
        audioViewModel.actionType = 668;
        audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        audioViewModel.describeString = @"保存音频";
        audioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEMusicModel *musicModel = awemeModel.music;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioViewModel];
    }

    // 创建视频功能
    if (enableCreateVideo && self.awemeModel.awemeType == 68) {
        AWELongPressPanelBaseViewModel *createVideoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        createVideoViewModel.awemeModel = self.awemeModel;
        createVideoViewModel.actionType = 677;
        createVideoViewModel.duxIconName = @"ic_videosearch_outlined_20";
        createVideoViewModel.describeString = @"保存视频"; // 1.0.23 第二批：68 按他的说法改叫保存视频
        createVideoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;

          // 收集普通图片URL
          NSMutableArray *imageURLs = [NSMutableArray array];
          // 收集实况照片信息（图片URL+视频URL）
          NSMutableArray *livePhotos = [NSMutableArray array];

          // 获取背景音乐URL
          NSString *bgmURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              bgmURL = awemeModel.music.playURL.originURLList.firstObject;
          }

          // 处理所有图片和实况
          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSString *bestURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          bestURL = urlString;
                          break;
                      }
                  }

                  if (!bestURL && imageModel.urlList.count > 0) {
                      bestURL = imageModel.urlList.firstObject;
                  }

                  // 如果是实况照片，需要收集图片和视频URL
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      if (videoURL) {
                          [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                      }
                  } else {
                      // 普通图片
                      [imageURLs addObject:bestURL];
                  }
              }
          }

          // 调用视频创建API
          [DYYYManager createVideoFromMedia:imageURLs
              livePhotos:livePhotos
              bgmURL:bgmURL
              progress:^(NSInteger current, NSInteger total, NSString *status) {
              }
              completion:^(BOOL success, NSString *message) {
                if (success) {
                } else {
                    [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                }
              }];

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:createVideoViewModel];
    }

    // 复制文案功能
    if (enableCopyText) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";
        copyText.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          [[UIPasteboard generalPasteboard] setString:descText];
          [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyText];
    }

    // 复制分享链接功能
    if (enableCopyLink) {
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制链接";
        copyShareLink.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          NSString *cleanedURL = cleanShareURL(shareLink);
          [[UIPasteboard generalPasteboard] setString:cleanedURL];
          [DYYYToast showSuccessToastWithMessage:@"分享链接已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyShareLink];
    }

    // 过滤用户功能
    if (enableFilterUser) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 674;
        filterKeywords.duxIconName = @"ic_userban_outlined_20";
        filterKeywords.describeString = @"过滤用户";
        filterKeywords.action = ^{
          AWEUserModel *author = self.awemeModel.author;
          NSString *nickname = author.nickname ?: @"未知用户";
          NSString *shortId = author.shortID ?: @"";
          // 创建当前用户的过滤格式 "nickname-shortid"
          NSString *currentUserFilter = [NSString stringWithFormat:@"%@-%@", nickname, shortId];
          // 获取保存的过滤用户列表
          NSString *savedUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"] ?: @"";
          NSArray *userArray = [savedUsers length] > 0 ? [savedUsers componentsSeparatedByString:@","] : @[];
          BOOL userExists = NO;
          for (NSString *userInfo in userArray) {
              NSArray *components = [userInfo componentsSeparatedByString:@"-"];
              if (components.count >= 2) {
                  NSString *userId = [components lastObject];
                  if ([userId isEqualToString:shortId] && shortId.length > 0) {
                      userExists = YES;
                      break;
                  }
              }
          }
          NSString *actionButtonText = userExists ? @"取消过滤" : @"添加过滤";
          [DYYYBottomAlertView showAlertWithTitle:@"过滤用户视频"
              message:[NSString stringWithFormat:@"用户: %@ (ID: %@)", nickname, shortId]
              avatarURL:nil
              cancelButtonText:@"管理过滤列表"
              confirmButtonText:actionButtonText
              cancelAction:^{
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:userArray];
                keywordListView.onConfirm = ^(NSArray *users) {
                  NSString *userString = [users componentsJoinedByString:@","];
                  [[NSUserDefaults standardUserDefaults] setObject:userString forKey:@"DYYYFilterUsers"];
                  [DYYYUtils showToast:@"过滤用户列表已更新"];
                };
                [keywordListView show];
              }
              closeAction:nil
              confirmAction:^{
                // 添加或移除用户过滤
                NSMutableArray *updatedUsers = [NSMutableArray arrayWithArray:userArray];
                if (userExists) {
                    // 移除用户
                    NSMutableArray *toRemove = [NSMutableArray array];
                    for (NSString *userInfo in updatedUsers) {
                        NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                        if (components.count >= 2) {
                            NSString *userId = [components lastObject];
                            if ([userId isEqualToString:shortId]) {
                                [toRemove addObject:userInfo];
                            }
                        }
                    }
                    [updatedUsers removeObjectsInArray:toRemove];
                    [DYYYUtils showToast:@"已从过滤列表中移除此用户"];
                } else {
                    // 添加用户
                    [updatedUsers addObject:currentUserFilter];
                    [DYYYUtils showToast:@"已添加此用户到过滤列表"];
                }
                // 保存更新后的列表
                NSString *updatedUserString = [updatedUsers componentsJoinedByString:@","];
                [[NSUserDefaults standardUserDefaults] setObject:updatedUserString forKey:@"DYYYFilterUsers"];
              }];
        };
        [viewModels addObject:filterKeywords];
    }

    // 过滤文案功能
    if (enableFilterKeyword) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 675;
        filterKeywords.duxIconName = @"ic_funnel_outlined_20";
        filterKeywords.describeString = @"过滤文案";
        filterKeywords.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          NSString *propName = nil;
          if (self.awemeModel.propGuideV2) {
              propName = self.awemeModel.propGuideV2.propName;
          }
          DYYYFilterSettingsView *filterView = [[DYYYFilterSettingsView alloc] initWithTitle:@"过滤关键词调整" text:descText propName:propName];
          filterView.onConfirm = ^(NSString *selectedText) {
            if (selectedText.length > 0) {
                NSString *currentKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"] ?: @"";
                NSString *newKeywords;
                if (currentKeywords.length > 0) {
                    newKeywords = [NSString stringWithFormat:@"%@,%@", currentKeywords, selectedText];
                } else {
                    newKeywords = selectedText;
                }
                [[NSUserDefaults standardUserDefaults] setObject:newKeywords forKey:@"DYYYFilterKeywords"];
                [DYYYUtils showToast:[NSString stringWithFormat:@"已添加过滤词: %@", selectedText]];
            }
          };
          // 设置过滤关键词按钮回调
          filterView.onKeywordFilterTap = ^{
            // 获取保存的关键词
            NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"] ?: @"";
            NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
            // 创建并显示关键词列表视图
            DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];
            // 设置确认回调
            keywordListView.onConfirm = ^(NSArray *keywords) {
              // 将关键词数组转换为逗号分隔的字符串
              NSString *keywordString = [keywords componentsJoinedByString:@","];
              // 保存到用户默认设置
              [[NSUserDefaults standardUserDefaults] setObject:keywordString forKey:@"DYYYFilterKeywords"];
              // 显示提示
              [DYYYUtils showToast:@"过滤关键词已更新"];
            };
            // 显示关键词列表视图
            [keywordListView show];
          };
          [filterView show];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:filterKeywords];
    }

    if (enableTimerClose) {
        AWELongPressPanelBaseViewModel *timerCloseViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        timerCloseViewModel.awemeModel = self.awemeModel;
        timerCloseViewModel.actionType = 676;
        timerCloseViewModel.duxIconName = @"ic_c_alarm_outlined";
        // 检查是否已有定时任务在运行
        NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
        BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
        timerCloseViewModel.describeString = hasActiveTimer ? @"取消定时" : @"定时关闭";
        timerCloseViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
          BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
          if (hasActiveTimer) {
              [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYTimerShutdownTime"];
              [DYYYUtils showToast:@"已取消定时关闭任务"];
              return;
          }
          // 读取上次设置的时间
          NSInteger defaultMinutes = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYTimerCloseMinutes"];
          if (defaultMinutes <= 0) {
              defaultMinutes = 5;
          }
          NSString *defaultText = [NSString stringWithFormat:@"%ld", (long)defaultMinutes];
          DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"设置定时关闭时间" defaultText:defaultText placeholder:@"请输入关闭时间(单位:分钟)"];
          inputView.onConfirm = ^(NSString *inputText) {
            NSInteger minutes = [inputText integerValue];
            if (minutes <= 0) {
                minutes = 5;
            }
            // 保存用户设置的时间以供下次使用
            [[NSUserDefaults standardUserDefaults] setInteger:minutes forKey:@"DYYYTimerCloseMinutes"];
            NSInteger seconds = minutes * 60;
            NSTimeInterval shutdownTimeValue = [[NSDate date] timeIntervalSince1970] + seconds;
            [[NSUserDefaults standardUserDefaults] setObject:@(shutdownTimeValue) forKey:@"DYYYTimerShutdownTime"];
            [DYYYUtils showToast:[NSString stringWithFormat:@"抖音将在%ld分钟后关闭...", (long)minutes]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              NSNumber *currentShutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
              if (currentShutdownTime != nil && [currentShutdownTime doubleValue] <= [[NSDate date] timeIntervalSince1970]) {
                  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYTimerShutdownTime"];
                  // 显示确认关闭弹窗，而不是直接退出
                  DYYYConfirmCloseView *confirmView = [[DYYYConfirmCloseView alloc] initWithTitle:@"定时关闭" message:@"定时关闭时间已到，是否关闭抖音？"];
                  [confirmView show];
              }
            });
          };
          [inputView show];
        };
        [viewModels addObject:timerCloseViewModel];
    }

    // ===== 顾海龙抖音长按项（686-695）=====
    if (GHLGetBool(GHL_KEY_EXTRACT_AUDIO)) {
        AWELongPressPanelBaseViewModel *extractAudioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        extractAudioViewModel.awemeModel = self.awemeModel;
        extractAudioViewModel.actionType = 686;
        extractAudioViewModel.duxIconName = @"ic_music_outlined";
        extractAudioViewModel.describeString = @"提取原声";
        extractAudioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLExtractOriginalAudioForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:extractAudioViewModel];
    }

    if (GHLGetBool(GHL_KEY_NO_WATERMARK_SHARE_LINK)) {
        AWELongPressPanelBaseViewModel *noWatermarkViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        noWatermarkViewModel.awemeModel = self.awemeModel;
        noWatermarkViewModel.actionType = 687;
        noWatermarkViewModel.duxIconName = @"ic_link_outlined";
        noWatermarkViewModel.describeString = @"复制无水印链接";
        noWatermarkViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLCopyNoWatermarkLinkForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:noWatermarkViewModel];
    }

    if (GHLGetBool(GHL_KEY_BACKGROUND_AUDIO)) {
        AWELongPressPanelBaseViewModel *pipViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        pipViewModel.awemeModel = self.awemeModel;
        pipViewModel.actionType = 688;
        pipViewModel.duxIconName = @"ic_pip_outlined";
        pipViewModel.describeString = @"画中画播放";
        pipViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          // 1.0.19：先把 sheet 收掉再找播放器——sheet 盖着时查找只能看到面板自己的控制器，
          // feed 的播放器被挡住，B 路 0 个控制器（1.0.18 日志 15:50:38 那次）。
          // 等 0.4 秒让收起动画跑完再触发。
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GHLStartPiPWithCaller(@"网格点按");
          });
        };
        [viewModels addObject:pipViewModel];
    }

    if (GHLGetBool(GHL_KEY_VOICE_PACKAGE)) {
        AWELongPressPanelBaseViewModel *voicePreviewViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        voicePreviewViewModel.awemeModel = self.awemeModel;
        voicePreviewViewModel.actionType = 689;
        voicePreviewViewModel.duxIconName = @"ic_voice_outlined";
        voicePreviewViewModel.describeString = @"语音包试听";
        voicePreviewViewModel.action = ^{
          GHLPreviewVoicePackage(GHLGetString(GHL_KEY_VOICE_PACKAGE_ID));
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:voicePreviewViewModel];

        AWELongPressPanelBaseViewModel *voiceShareViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        voiceShareViewModel.awemeModel = self.awemeModel;
        voiceShareViewModel.actionType = 690;
        voiceShareViewModel.duxIconName = @"ic_share_outlined";
        voiceShareViewModel.describeString = @"语音包读文案并分享";
        voiceShareViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSString *text = awemeModel.descriptionString;
          if (text.length == 0) text = @"顾海龙抖音";
          NSString *voiceId = GHLGetString(GHL_KEY_VOICE_PACKAGE_ID);
          [DYYYUtils showToast:@"正在用语音包合成语音…"];
          GHLSynthesizeVoicePackageText(text, voiceId, ^(NSURL *fileURL) {
            if (!fileURL) {
                [DYYYUtils showToast:@"语音合成失败"];
                return;
            }
            UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            [rootVC presentViewController:activityVC animated:YES completion:nil];
          });
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:voiceShareViewModel];
    }

    if (GHLGetBool(GHL_KEY_SAVE_AVATAR)) {
        AWELongPressPanelBaseViewModel *avatarViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        avatarViewModel.awemeModel = self.awemeModel;
        avatarViewModel.actionType = 691;
        avatarViewModel.duxIconName = @"ic_avatar_outlined";
        avatarViewModel.describeString = @"保存头像";
        avatarViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSURL *avatarURL = nil;
          if (awemeModel.author && awemeModel.author.avatarMedium && awemeModel.author.avatarMedium.originURLList.count > 0) {
              avatarURL = [NSURL URLWithString:awemeModel.author.avatarMedium.originURLList.firstObject];
          }
          if (!avatarURL) {
              [DYYYUtils showToast:@"拿不到头像地址"];
          } else {
              [DYYYManager downloadMedia:avatarURL
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                GHLLog(@"保存头像：%@", success ? @"成功" : @"失败");
                              }];
              [DYYYUtils showToast:@"头像保存中…"];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:avatarViewModel];
    }

    if (GHLGetBool(GHL_KEY_COPY_PROFILE)) {
        AWELongPressPanelBaseViewModel *profileViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        profileViewModel.awemeModel = self.awemeModel;
        profileViewModel.actionType = 692;
        profileViewModel.duxIconName = @"ic_user_outlined";
        profileViewModel.describeString = @"复制个人资料";
        profileViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEUserModel *author = awemeModel.author;
          if (!author) {
              [DYYYUtils showToast:@"拿不到作者资料"];
          } else {
              NSString *profile = [NSString stringWithFormat:@"昵称：%@\n抖音号：%@\n简介：%@", author.nickname ?: @"", author.shortID ?: @"", author.signature ?: @""];
              [[UIPasteboard generalPasteboard] setString:profile];
              [DYYYUtils showToast:@"个人资料已复制"];
              GHLLog(@"复制个人资料：%@", author.nickname);
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:profileViewModel];
    }

    if (GHLGetBool(GHL_KEY_AUDIO_SHARE)) {
        AWELongPressPanelBaseViewModel *audioShareViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioShareViewModel.awemeModel = self.awemeModel;
        audioShareViewModel.actionType = 693;
        audioShareViewModel.duxIconName = @"ic_share_outlined";
        audioShareViewModel.describeString = @"分享音频";
        audioShareViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSURL *audioURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:awemeModel.music.playURL.originURLList.firstObject];
          }
          if (!audioURL) {
              [DYYYUtils showToast:@"这个视频没有背景音乐"];
          } else {
              [DYYYManager downloadMediaWithProgress:audioURL
                                           mediaType:MediaTypeAudio
                                               audio:nil
                                            progress:nil
                                          completion:^(BOOL success, NSURL *fileURL) {
                                            if (!success || !fileURL) {
                                                [DYYYUtils showToast:@"音频下载失败"];
                                                return;
                                            }
                                            GHLRunOnMain(^{
                                              UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
                                              UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                                              [rootVC presentViewController:activityVC animated:YES completion:nil];
                                            });
                                          }];
              [DYYYUtils showToast:@"音频下载中，好了就弹分享…"];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioShareViewModel];
    }

    // 1.0.23：长按面板新增两项（清单 9 号，按抖音图层的做法）。
    // 「复制下载链接」和「解析保存（影片/音频）」他那套里有，咱们已经有了——
    // 复制下载链接＝687 复制无水印链接（解析后的直链），解析保存＝673 接口保存＋
    // 666 保存视频／668 保存音频；不重复加，只补没有的两项。
    if (GHLGetBool(GHL_KEY_AWEME_DATA)) {
        AWELongPressPanelBaseViewModel *awemeDataViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        awemeDataViewModel.awemeModel = self.awemeModel;
        awemeDataViewModel.actionType = 694;
        awemeDataViewModel.duxIconName = @"ic_data_outlined";
        awemeDataViewModel.describeString = @"获取作品数据";
        awemeDataViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLShowAwemeDataForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:awemeDataViewModel];
    }

    if (GHLGetBool(GHL_KEY_IMAGE_PREVIEW)) {
        AWELongPressPanelBaseViewModel *imagePreviewViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imagePreviewViewModel.awemeModel = self.awemeModel;
        imagePreviewViewModel.actionType = 695;
        imagePreviewViewModel.duxIconName = @"ic_image_outlined";
        imagePreviewViewModel.describeString = @"图片预览";
        imagePreviewViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLPreviewAwemeImagesForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imagePreviewViewModel];
    }

    // 创建自定义组
    NSMutableArray *customGroups = [NSMutableArray array];
    NSInteger totalButtons = viewModels.count;

    // 根据按钮总数确定每行的按钮数
    NSInteger firstRowCount = 0;
    NSInteger secondRowCount = 0;

    // 确定分配方式与原代码相同
    if (totalButtons <= 2) {
        firstRowCount = totalButtons;
    } else if (totalButtons <= 4) {
        firstRowCount = totalButtons / 2;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 5) {
        firstRowCount = 3;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 6) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 8) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else {
        firstRowCount = 5;
        secondRowCount = totalButtons - firstRowCount;
    }

    // 创建第一行
    if (firstRowCount > 0) {
        NSArray<AWELongPressPanelBaseViewModel *> *firstRowButtons = [viewModels subarrayWithRange:NSMakeRange(0, firstRowCount)];
        AWELongPressPanelViewGroupModel *firstRowGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
        firstRowGroup.isDYYYCustomGroup = YES;
        firstRowGroup.groupType = (firstRowCount <= 3) ? 11 : 12;
        firstRowGroup.isModern = YES;
        firstRowGroup.groupArr = firstRowButtons;
        [customGroups addObject:firstRowGroup];
    }

    // 创建第二行
    if (secondRowCount > 0) {
        NSArray<AWELongPressPanelBaseViewModel *> *secondRowButtons = [viewModels subarrayWithRange:NSMakeRange(firstRowCount, secondRowCount)];
        AWELongPressPanelViewGroupModel *secondRowGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
        secondRowGroup.isDYYYCustomGroup = YES;
        secondRowGroup.groupType = (secondRowCount <= 3) ? 11 : 12;
        secondRowGroup.isModern = YES;
        secondRowGroup.groupArr = secondRowButtons;
        [customGroups addObject:secondRowGroup];
    }

    NSArray *finalArray = [customGroups arrayByAddingObjectsFromArray:originalArray];
    gDYYYLongPressPanelData = finalArray; // 1.0.10：强引用持有到面板收起
    DYYYLongPressGridPanelRetryAfterData(self); // 1.0.10：数据一到就主线程补一次盖网格
    return finalArray;
}
%end

// ===== 1.0.9：网格长按面板（深色毛玻璃 + 三列金色图标 + 顶部金色龙头）=====
// 自定义项：Modern 钩子标了 isDYYYCustomGroup；旧钩子没标，用 actionType 认
//（666-679 是 DYYY 长按项，686-695 是顾海龙长按项）。
static BOOL DYYYLongPressItemIsCustom(AWELongPressPanelBaseViewModel *item, AWELongPressPanelViewGroupModel *group) {
    if (!item) return NO;
    if (group && group.isDYYYCustomGroup) return YES;
    return item.actionType >= 666 && item.actionType <= 699;
}

// 隐藏列表匹配（和 dataArray 钩子里同一套：小写精确或包含匹配）。
static BOOL DYYYLongPressItemHiddenByHideList(NSString *desc, NSSet<NSString *> *hideSet) {
    if (!desc || desc.length == 0 || hideSet.count == 0) return NO;
    NSString *descLower = [desc lowercaseString];
    if ([hideSet containsObject:descLower]) return YES;
    for (NSString *hideItem in hideSet) {
        if ([descLower containsString:hideItem] || [hideItem containsString:descLower]) return YES;
    }
    return NO;
}

// 只放数据缓存（下滑收起时用；面板彻底收起走下面的 ClearAll）。
static void DYYYLongPressGridPanelClearData(void) {
    gDYYYLongPressPanelData = nil;
}

// 面板彻底收起时放掉全部状态（viewDidDisappear 判定已收起 / dealloc 时调）。
static void DYYYLongPressGridPanelClearAll(void) {
    gDYYYLongPressPanelData = nil;
    gDYYYLongPressGridDiagVC = nil;
    gDYYYLongPressGridDiagReason = nil;
    // 1.0.25：恢复表显示的同时把网格从屏幕上拿掉并置 nil（不然下一次 Show 在入口早退，
    // 再也不会走新建分支重藏；网格在、表又恢复显示就是重影）。
    if (gDYYYLongPressGridPanel) {
        [gDYYYLongPressGridPanel removeFromSuperview];
        gDYYYLongPressGridPanel = nil;
    }
    // 1.0.24：网格收起时把藏起来的原生列表恢复显示（控制器已释放就不用管）。
    if (gDYYYLongPressGridHiddenVC) {
        UITableView *nativeTable = DYYYLongPressFindTableViewInView(gDYYYLongPressGridHiddenVC.view);
        if (nativeTable) {
            nativeTable.hidden = NO;
            GHLLog(@"长按面板：原生列表已恢复");
        }
        gDYYYLongPressGridHiddenVC = nil;
    }
}

// 1.0.10：诊断日志去重——同一控制器、同一原因只记一行。
static void DYYYLongPressGridLogDiag(UIViewController *vc, NSString *reason) {
    if (!vc || reason.length == 0) return;
    if (gDYYYLongPressGridDiagVC == vc && [gDYYYLongPressGridDiagReason isEqualToString:reason]) return;
    gDYYYLongPressGridDiagVC = vc;
    gDYYYLongPressGridDiagReason = reason;
    GHLLog(@"长按面板：%@", reason);
}

// ===== 1.0.16：原生项走原生选中 =====
// 倍速不能按的根因（诊断）：原生项的动作要面板控制器上下文（倍速要点开倍速选择页，
// 大概率要从面板控制器 present），网格直接调 item.action() 上下文不对就静默失败，
// 且成功分支也不记日志，日志里没有任何点按记录。
// 修法：按 dataArray 里的组/序号找到原生格子，调抖音自己的分发，复现用户直接点原生格子的行为。
// 找不到 table/格子/delegate、校验对不上时一律返回 NO，调用方回退 item.action()；全程 try/catch，不崩。
static UITableView *_Nullable DYYYLongPressFindTableViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *found = DYYYLongPressFindTableViewInView(sub);
        if (found) return found;
    }
    return nil;
}

static UICollectionView *_Nullable DYYYLongPressFindCollectionViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UICollectionView class]]) return (UICollectionView *)view;
    for (UIView *sub in view.subviews) {
        UICollectionView *found = DYYYLongPressFindCollectionViewInView(sub);
        if (found) return found;
    }
    return nil;
}

// groupIndex/itemIndex 是 dataArray 里的组/序号。Modern 面板每组一行横向条（条里是
// collectionView，格子在里面）；经典面板一行就是一项（走 table 的 didSelect）。
// 校验：条的 longPressViewGroupModel 必须是同一对象，或它的 dataArray 里有这一项——
// 对不上就返回 NO，绝不按错序号点到别的项。
static BOOL DYYYLongPressSelectNativeItem(UIViewController *vc, NSInteger groupIndex, NSInteger itemIndex, AWELongPressPanelBaseViewModel *item, AWELongPressPanelViewGroupModel *group) {
    if (!vc || !vc.view || !item || !group) return NO;
    @try {
        UITableView *tableView = DYYYLongPressFindTableViewInView(vc.view);
        if (!tableView) return NO;
        if (groupIndex < 0 || groupIndex >= [tableView numberOfSections]) return NO;
        NSInteger rowsInSection = [tableView numberOfRowsInSection:groupIndex];
        if (rowsInSection < 1) return NO;
        NSIndexPath *stripPath = [NSIndexPath indexPathForRow:0 inSection:groupIndex];
        UITableViewCell *stripCell = [tableView cellForRowAtIndexPath:stripPath];
        if (!stripCell) {
            // 条不在可见区：把 table 滚到那一组再取（网格盖着，用户看不到底下滚动）。
            [tableView scrollToRowAtIndexPath:stripPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
            [tableView layoutIfNeeded];
            stripCell = [tableView cellForRowAtIndexPath:stripPath];
            if (!stripCell) return NO;
        }
        UICollectionView *collectionView = DYYYLongPressFindCollectionViewInView(stripCell.contentView);
        if (!collectionView) collectionView = DYYYLongPressFindCollectionViewInView(stripCell);
        if (collectionView) {
            // Modern：条里是 collectionView，格子在里面。
            NSInteger resolvedItemIndex = itemIndex;
            if ([stripCell respondsToSelector:@selector(longPressViewGroupModel)]) {
                id cellGroup = [(id)stripCell longPressViewGroupModel];
                if (cellGroup && cellGroup != (id)group) return NO; // 不是同一组，不点
            }
            if ([stripCell respondsToSelector:@selector(dataArray)]) {
                NSArray *cellData = [(id)stripCell dataArray];
                NSInteger found = NSNotFound;
                for (NSInteger i = 0; i < (NSInteger)cellData.count; i++) {
                    id obj = cellData[i];
                    if ([obj isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                        AWELongPressPanelBaseViewModel *vm = (AWELongPressPanelBaseViewModel *)obj;
                        if (vm.actionType == item.actionType && [vm.describeString isEqualToString:item.describeString]) {
                            found = i;
                            break;
                        }
                    }
                }
                if (found == NSNotFound) return NO; // 条里没这一项，不点
                resolvedItemIndex = found;
            }
            id<UICollectionViewDelegate> delegate = collectionView.delegate;
            if (!delegate || ![delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) return NO;
            if (resolvedItemIndex < 0 || resolvedItemIndex >= [collectionView numberOfItemsInSection:0]) return NO;
            [delegate collectionView:collectionView didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:resolvedItemIndex inSection:0]];
            return YES;
        }
        // 经典面板：一行就是一项，走 table 的 didSelectRowAtIndexPath:。
        if (itemIndex < 0 || itemIndex >= rowsInSection) return NO;
        id<UITableViewDelegate> tableDelegate = tableView.delegate;
        if (!tableDelegate || ![tableDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [tableDelegate tableView:tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:itemIndex inSection:groupIndex]];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

// 1.0.16：建议的 sheet 高度——首屏露 5 行（再多就快佔滿屏了；行數少就按實際行數算）。
// 抖音自己的 presentation 不一定採納 preferredContentSize，盡力而為，真機驗。
static CGFloat DYYYLongPressGridPreferredSheetHeight(NSInteger totalItems, CGFloat safeBottom) {
    return [DYYYLongPressGridPanelView ghl_preferredSheetHeightForItemCount:totalItems safeAreaBottom:safeBottom];
}

// 1.0.10：dataArray 刚存好数据时，主线程补一次盖网格（self 就是面板控制器）。
// viewDidLoad/viewDidLayoutSubviews 可能都跑在 dataArray 之前，只靠它们会错过时机。
static void DYYYLongPressGridPanelRetryAfterData(UIViewController *vc) {
    if (!vc) return;
    __weak UIViewController *weakVC = vc;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYYYShowLongPressGridPanelIfNeeded(weakVC);
    });
}

// 在面板控制器上盖网格（viewDidLoad / viewWillAppear / viewDidLayoutSubviews 里都调一次，
// dataArray 可能在 viewDidLoad 之后才跑，靠后几次补上；已经盖上的直接返回）。
// 1.0.10：每个失败分支都记一行诊断（去重后每控制器每原因只记一次），下次网格没盖上，
// 日志里直接写明是哪一关没过，不再静默。
static void DYYYShowLongPressGridPanelIfNeeded(UIViewController *vc) {
    if (!vc || !vc.view) return;
    // 加载时记一次开关值（进程内只记一次）。
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        GHLLog(@"长按面板：加载时网格开关=%@", GHLGetBool(GHL_KEY_LONG_PRESS_GRID_PANEL) ? @"开" : @"关");
    });
    BOOL gridSwitchOn = GHLGetBool(GHL_KEY_LONG_PRESS_GRID_PANEL);
    if (!gridSwitchOn) {
        DYYYLongPressGridLogDiag(vc, @"未盖网格（开关关）");
        return;
    }
    // 1.0.25：网格还在屏幕上时，每次 Show 都重藏一次原生列表（1.0.24 只在第一次新建时藏：
    // 点网格里会开子页的项（倍速、定时关闭）时 viewDidDisappear 误判收起、把表恢复显示，
    // 之后 Show 又在入口早退，再也没人重藏，重影就一直在）。
    if (gDYYYLongPressGridPanel && gDYYYLongPressGridPanel.superview) {
        UITableView *existingTable = DYYYLongPressFindTableViewInView(vc.view);
        if (existingTable && !existingTable.hidden) {
            existingTable.hidden = YES;
            gDYYYLongPressGridHiddenVC = vc;
            GHLLog(@"长按面板：原生列表已再次隐藏");
        }
        // 1.0.26：面板复用时也刷新背景图（换图后旧面板沿用旧图，是 1.0.24 换图失败的主因），
        // 并记一行解析到的面板设置。
        [gDYYYLongPressGridPanel ghl_refreshBackgroundImage];
        [gDYYYLongPressGridPanel ghl_logResolvedSettings];
        return; // 已盖上，成功状态，不记日志
    }
    NSArray *data = gDYYYLongPressPanelData;
    if (!data || data.count == 0) {
        DYYYLongPressGridLogDiag(vc, @"未盖网格（开关开，数据为空）");
        return;
    }

    // 隐藏列表（逗号分隔，和原生面板同一份设置；网格里同样生效）。
    NSMutableSet<NSString *> *hideSet = [NSMutableSet set];
    NSString *hidePanelItems = DYYYGetString(@"DYYYHidePanelItems");
    if (hidePanelItems.length > 0) {
        NSString *normalized = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
        for (NSString *raw in [normalized componentsSeparatedByString:@","]) {
            NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) [hideSet addObject:[trimmed lowercaseString]];
        }
    }

    // 1.0.15：收集全部项（自定义＋原生，保持 dataArray 里的顺序）——没有「更多」了，
    // 原生项也进网格，长按只出网格。隐藏列表对全部项生效（dataArray 钩子里已经对
    // 原生组滤过一次，这里再统一滤一次，行为一致）。
    NSMutableArray<NSDictionary *> *gridItems = [NSMutableArray array];
    NSInteger nativeItemCount = 0;
    for (id groupObj in data) {
        if (![groupObj isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) continue;
        AWELongPressPanelViewGroupModel *group = (AWELongPressPanelViewGroupModel *)groupObj;
        for (id itemObj in group.groupArr) {
            if (![itemObj isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) continue;
            AWELongPressPanelBaseViewModel *item = (AWELongPressPanelBaseViewModel *)itemObj;
            if (item.describeString.length == 0) continue;
            if (DYYYLongPressItemHiddenByHideList(item.describeString, hideSet)) continue;
            if (!DYYYLongPressItemIsCustom(item, group)) nativeItemCount++;
            [gridItems addObject:@{@"title": item.describeString, @"actionType": @(item.actionType)}];
        }
    }
    if (gridItems.count == 0) { // 一项都没有（自定义全关、原生组也是空），没东西可盖
        DYYYLongPressGridLogDiag(vc, [NSString stringWithFormat:@"未盖网格（开关开，数据%lu组，0项）", (unsigned long)data.count]);
        return;
    }

    // 1.0.16：sheet 首屏露 5 行（系统 sheet 不一定採納，盡力而為）。
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = vc.view.safeAreaInsets.bottom;
    vc.preferredContentSize = CGSizeMake(vc.view.bounds.size.width, DYYYLongPressGridPreferredSheetHeight((NSInteger)gridItems.count, safeBottom));

    __weak UIViewController *weakVC = vc; // 点按 handler 里走原生选中要用面板控制器（弱引用，不留住它）
    DYYYLongPressGridPanelView *panel = [[DYYYLongPressGridPanelView alloc] initWithItems:gridItems
                                                                        itemActionHandler:^(NSInteger actionType, NSString *title) {
        // 点按时按 actionType + 标题找回原 viewModel。标题一起比：原生项和自定义项
        // actionType 万一撞号也不会点错。
        // 1.0.16：原生项不再直接调 item.action()——改走原生选中（DYYYLongPressSelectNativeItem），
        // 让抖音自己的分发去开倍速页/投屏等；走不通才回退 item.action()。自定义项逻辑一点没改。
        // 成功分支也记日志（之前成功了也不记，点了没反应时日志里什么都看不出来）。
        NSArray *currentData = gDYYYLongPressPanelData;
        for (NSInteger gi = 0; gi < (NSInteger)currentData.count; gi++) {
            id groupObj = currentData[gi];
            if (![groupObj isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) continue;
            AWELongPressPanelViewGroupModel *group = (AWELongPressPanelViewGroupModel *)groupObj;
            for (NSInteger ii = 0; ii < (NSInteger)group.groupArr.count; ii++) {
                id itemObj = group.groupArr[ii];
                if (![itemObj isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) continue;
                AWELongPressPanelBaseViewModel *item = (AWELongPressPanelBaseViewModel *)itemObj;
                if (item.actionType != actionType || ![item.describeString isEqualToString:title]) continue;
                if (!DYYYLongPressItemIsCustom(item, group)) {
                    if (DYYYLongPressSelectNativeItem(weakVC, gi, ii, item, group)) {
                        GHLLog(@"长按面板：原生项「%@」已走原生选中（组 %ld 序号 %ld）", title, (long)gi, (long)ii);
                        return;
                    }
                    GHLLog(@"长按面板：原生项「%@」原生选中走不通，回退 item.action()", title);
                }
                if (item.action) {
                    item.action();
                    GHLLog(@"长按面板：网格点按 actionType %ld「%@」已执行 action", (long)actionType, title);
                    return;
                }
                GHLLog(@"长按面板：网格点按 actionType %ld「%@」没找到对应项", (long)actionType, title);
                return;
            }
        }
        GHLLog(@"长按面板：网格点按 actionType %ld「%@」没找到对应项", (long)actionType, title);
    } dismissHandler:^{
        DYYYLongPressGridPanelClearData(); // 下滑收起：数据缓存放掉，viewDidDisappear 还会再清一次
        AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
        [panelManager dismissWithAnimation:YES completion:nil];
    }];
    // 1.0.24：网格盖上后把底下抖音原生的长按列表藏起来（hidden=YES）——
    // 1.0.23 把糊调成 58%、格子改 0.40 微透明之后，原生列表透过网格露出来，
    // 同一批菜单字出现两次、错位重影（真机实拍）。只藏列表，不动原生面板控制器：
    // 网格点按和关掉还靠它（原生选中要面板控制器上下文），拆掉风险大。
    UITableView *nativeTable = DYYYLongPressFindTableViewInView(vc.view);
    if (nativeTable && !nativeTable.hidden) {
        nativeTable.hidden = YES;
        gDYYYLongPressGridHiddenVC = vc;
        GHLLog(@"长按面板：网格已盖上，原生列表已隐藏");
    }
    panel.frame = vc.view.bounds;
    [vc.view addSubview:panel];
    [panel setNeedsLayout];
    // 1.0.26：新建面板也走同一套刷新＋记日志（init 只读一次图，双保险；设置值记一行，下次日志不用猜）。
    [panel ghl_refreshBackgroundImage];
    [panel ghl_logResolvedSettings];
    gDYYYLongPressGridPanel = panel;
    GHLLog(@"长按面板：网格已盖上（%lu 项，其中原生 %ld 项）：%@", (unsigned long)gridItems.count, (long)nativeItemCount, [[gridItems valueForKey:@"title"] componentsJoinedByString:@"、"]);
}

static void DYYYLayoutLongPressGridPanel(UIViewController *vc) {
    if (!vc || !vc.view) return;
    DYYYLongPressGridPanelView *panel = gDYYYLongPressGridPanel;
    if (panel && panel.superview == vc.view) {
        panel.frame = vc.view.bounds;
        [panel setNeedsLayout];
    }
}

%hook AWEModernLongPressPanelTableViewController
- (void)viewDidLoad {
    %orig;
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    DYYYLayoutLongPressGridPanel(self);
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // 1.0.10：面板真的收起时放掉全部状态（被子页面盖住时不动，回来还能再盖）。
    // 1.0.25：presentingViewController == nil 那项拿掉——经 AWELongPressPanelManager 托管的
    // sheet 这项大概率恒真，点网格里会开子页的项（倍速、定时关闭）时就误判收起、把原生表恢复显示。
    if (self.isBeingDismissed || self.isMovingFromParentViewController) {
        DYYYLongPressGridPanelClearAll();
    }
}
- (void)dealloc {
    DYYYLongPressGridPanelClearAll();
    %orig;
}
%end

// 旧版长按面板（DYYYEnableModernPanel 没开时走这里）：同一套网格，别只换新版。
%hook AWELongPressPanelTableViewController
- (void)viewDidLoad {
    %orig;
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    DYYYLayoutLongPressGridPanel(self);
    DYYYShowLongPressGridPanelIfNeeded(self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // 1.0.10：面板真的收起时放掉全部状态（被子页面盖住时不动，回来还能再盖）。
    // 1.0.25：presentingViewController == nil 那项拿掉——经 AWELongPressPanelManager 托管的
    // sheet 这项大概率恒真，点网格里会开子页的项（倍速、定时关闭）时就误判收起、把原生表恢复显示。
    if (self.isBeingDismissed || self.isMovingFromParentViewController) {
        DYYYLongPressGridPanelClearAll();
    }
}
- (void)dealloc {
    DYYYLongPressGridPanelClearAll();
    %orig;
}
%end

// 修复Modern风格长按面板水平设置单元格的大小计算
%hook AWEModernLongPressHorizontalSettingCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDYYYCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            CGFloat totalWidth = collectionView.bounds.size.width;
            NSInteger itemCount = self.dataArray.count;
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 修复Modern风格长按面板交互单元格的大小计算
%hook AWEModernLongPressInteractiveCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDYYYCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            NSInteger itemCount = self.dataArray.count;
            CGFloat totalWidth = collectionView.bounds.size.width - 12 * (itemCount - 1);
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 经典风格长按面板
%hook AWELongPressPanelTableViewController
- (NSArray *)dataArray {
    [DYYYManager setAlbumDescriptionContextWithAwemeModel:self.awemeModel];
    NSArray *originalArray = %orig;
    if (!originalArray) {
        originalArray = @[];
    }
    if (!self.awemeModel.author.nickname) {
        return originalArray;
    }

    // 检查是否开启精简模式
    BOOL simplifyPanel = DYYYGetBool(@"DYYYSimplifyLongPressPanel");

    // 如果开启精简模式，直接跳过原始面板处理，只返回自定义选项
    if (simplifyPanel) {
        originalArray = @[]; // 清空原始数组
    } else {
        // 获取需要隐藏的按钮设置（从文本输入框读取，逗号分隔）
        NSString *hidePanelItems = DYYYGetString(@"DYYYHidePanelItems");
        NSMutableSet<NSString *> *hideItemsLowerSet = [NSMutableSet set];

        if (hidePanelItems && hidePanelItems.length > 0) {
            // 支持中英文逗号分隔
            NSString *normalizedItems = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
            NSArray *items = [normalizedItems componentsSeparatedByString:@","];
            for (NSString *item in items) {
                NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedItem.length > 0) {
                    [hideItemsLowerSet addObject:[trimmedItem lowercaseString]];
                }
            }
        }

        // 如果有需要隐藏的项目，才进行过滤
        if (hideItemsLowerSet.count > 0) {
            NSMutableArray *modifiedOriginalGroups = [NSMutableArray array];

            for (id group in originalArray) {
                if ([group isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                    AWELongPressPanelViewGroupModel *groupModel = (AWELongPressPanelViewGroupModel *)group;
                    NSMutableArray *filteredGroupArr = [NSMutableArray array];

                    for (id item in groupModel.groupArr) {
                        if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                            AWELongPressPanelBaseViewModel *viewModel = (AWELongPressPanelBaseViewModel *)item;
                            NSString *descString = viewModel.describeString;

                            BOOL shouldHide = NO;
                            if (descString && descString.length > 0) {
                                NSString *descLower = [descString lowercaseString];

                                // 精确匹配
                                if ([hideItemsLowerSet containsObject:descLower]) {
                                    shouldHide = YES;
                                } else {
                                    // 部分匹配
                                    for (NSString *hideItemLower in hideItemsLowerSet) {
                                        if ([descLower containsString:hideItemLower] || [hideItemLower containsString:descLower]) {
                                            shouldHide = YES;
                                            break;
                                        }
                                    }
                                }
                            }

                            if (!shouldHide) {
                                [filteredGroupArr addObject:item];
                            }
                        } else {
                            [filteredGroupArr addObject:item];
                        }
                    }

                    if (filteredGroupArr.count > 0) {
                        AWELongPressPanelViewGroupModel *filteredGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
                        filteredGroup.groupType = groupModel.groupType;
                        filteredGroup.groupArr = filteredGroupArr;
                        [modifiedOriginalGroups addObject:filteredGroup];
                    }
                } else {
                    [modifiedOriginalGroups addObject:group];
                }
            }
            originalArray = modifiedOriginalGroups;
        }
    }

    // 检查是否启用了任意长按功能
    BOOL hasAnyFeatureEnabled = NO;

    // 检查各个单独的功能开关
    BOOL enableSaveVideo = DYYYGetBool(@"DYYYLongPressSaveVideo");
    BOOL enableSaveCover = DYYYGetBool(@"DYYYLongPressSaveCover");
    BOOL enableSaveAudio = DYYYGetBool(@"DYYYLongPressSaveAudio");
    BOOL enableSaveCurrentImage = DYYYGetBool(@"DYYYLongPressSaveCurrentImage");
    BOOL enableSaveAllImages = DYYYGetBool(@"DYYYLongPressSaveAllImages");
    BOOL enableCopyText = DYYYGetBool(@"DYYYLongPressCopyText");
    BOOL enableCopyLink = DYYYGetBool(@"DYYYLongPressCopyLink");
    BOOL enableApiDownload = DYYYGetBool(@"DYYYLongPressApiDownload");
    BOOL enableFilterUser = DYYYGetBool(@"DYYYLongPressFilterUser");
    BOOL enableFilterKeyword = DYYYGetBool(@"DYYYLongPressFilterTitle");
    BOOL enableTimerClose = DYYYGetBool(@"DYYYLongPressTimerClose");
    BOOL enableCreateVideo = DYYYGetBool(@"DYYYLongPressCreateVideo");

    // 检查是否有任何功能启用
    hasAnyFeatureEnabled = enableSaveVideo || enableSaveCover || enableSaveAudio || enableSaveCurrentImage || enableSaveAllImages || enableCopyText || enableCopyLink || enableApiDownload ||
                           enableFilterUser || enableFilterKeyword || enableTimerClose || enableCreateVideo ||
                           GHLGetBool(GHL_KEY_EXTRACT_AUDIO) || GHLGetBool(GHL_KEY_NO_WATERMARK_SHARE_LINK) ||
                           GHLGetBool(GHL_KEY_BACKGROUND_AUDIO) || GHLGetBool(GHL_KEY_VOICE_PACKAGE) ||
                           GHLGetBool(GHL_KEY_SAVE_AVATAR) || GHLGetBool(GHL_KEY_COPY_PROFILE) || GHLGetBool(GHL_KEY_AUDIO_SHARE);

    if (!hasAnyFeatureEnabled) {
        return originalArray;
    }

    // 创建自定义功能组
    AWELongPressPanelViewGroupModel *newGroupModel = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
    newGroupModel.groupType = 0;
    NSMutableArray *viewModels = [NSMutableArray array];

    BOOL isNewLivePhoto = (self.awemeModel.video && self.awemeModel.animatedImageVideoInfo != nil);

    // 视频下载功能 (非实况照片才显示)
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && !isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        downloadViewModel.awemeModel = self.awemeModel;
        downloadViewModel.actionType = 666;
        downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        downloadViewModel.describeString = @"保存视频";
        downloadViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          AWEMusicModel *musicModel = awemeModel.music;
          NSURL *audioURL = nil;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
          }

                  // 备用方法：直接使用h264URL
                  if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                      NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                      [DYYYManager downloadMedia:url
                                       mediaType:MediaTypeVideo
                                           audio:audioURL
                                      completion:^(BOOL success){
                                      }];
                  }
              
          
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:downloadViewModel];
    }

    //  新版实况照片保存
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *livePhotoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        livePhotoViewModel.awemeModel = self.awemeModel;
        livePhotoViewModel.actionType = 679;
        livePhotoViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        livePhotoViewModel.describeString = @"保存实况";
        livePhotoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;

          // 使用封面URL作为图片URL
          NSURL *imageURL = nil;
          if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
          }

          // 视频URL从视频模型获取
          NSURL *videoURL = nil;
          if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
          } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
          }

          // 下载实况照片
          if (imageURL && videoURL) {
              [DYYYManager downloadLivePhoto:imageURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:livePhotoViewModel];
    }

    // 当前图片/实况下载功能
    if (enableSaveCurrentImage && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
        AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imageViewModel.awemeModel = self.awemeModel;
        imageViewModel.actionType = 669;
        imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";

        if (self.awemeModel.albumImages.count == 1) {
            imageViewModel.describeString = @"保存图片";
        } else {
            imageViewModel.describeString = @"保存当前图片";
        }

        AWEImageAlbumImageModel *currimge = self.awemeModel.albumImages[self.awemeModel.currentImageIndex - 1];
        if (currimge.clipVideo != nil || self.awemeModel.isLivePhoto) {
            if (self.awemeModel.albumImages.count == 1) {
                imageViewModel.describeString = @"保存实况";
            } else {
                imageViewModel.describeString = @"保存当前实况";
            }
        }

        imageViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEImageAlbumImageModel *currentImageModel = nil;
          if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
              currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
          } else {
              currentImageModel = awemeModel.albumImages.firstObject;
          }
          // 如果是实况的话
          // 查找非.image后缀的URL
          NSURL *downloadURL = nil;
          for (NSString *urlString in currentImageModel.urlList) {
              NSURL *url = [NSURL URLWithString:urlString];
              NSString *pathExtension = [url.path.lowercaseString pathExtension];
              if (![pathExtension isEqualToString:@"image"]) {
                  downloadURL = url;
                  break;
              }
          }

          if (currentImageModel.clipVideo != nil) {
              NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
              [DYYYManager downloadLivePhoto:downloadURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          } else if (currentImageModel && currentImageModel.urlList.count > 0) {
              if (downloadURL) {
                  [DYYYManager downloadMedia:downloadURL
                                   mediaType:MediaTypeImage
                                       audio:nil
                                  completion:^(BOOL success) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:@"图片保存已取消"];
                                    }
                                  }];
              } else {
                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
              }
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imageViewModel];
    }

    // 保存所有图片/实况功能
    if (enableSaveAllImages && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 1) {
        AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        allImagesViewModel.awemeModel = self.awemeModel;
        allImagesViewModel.actionType = 670;
        allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        allImagesViewModel.describeString = @"保存所有图片";
        // 检查是否有实况照片并更改按钮文字
        BOOL hasLivePhoto = NO;
        for (AWEImageAlbumImageModel *imageModel in self.awemeModel.albumImages) {
            if (imageModel.clipVideo != nil) {
                hasLivePhoto = YES;
                break;
            }
        }
        if (hasLivePhoto) {
            allImagesViewModel.describeString = @"保存所有实况";
        }
        allImagesViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSMutableArray *imageURLs = [NSMutableArray array];
          NSMutableArray *livePhotos = [NSMutableArray array];

          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSURL *downloadURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          downloadURL = url;
                          break;
                      }
                  }

                  if (!downloadURL && imageModel.urlList.count > 0) {
                      downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                  }

                  // 检查是否是实况照片
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                  } else {
                      [imageURLs addObject:downloadURL.absoluteString];
                  }
              }
          }

          // 分别处理普通图片和实况照片
          if (livePhotos.count > 0) {
              [DYYYManager downloadAllLivePhotos:livePhotos];
          }

          if (imageURLs.count > 0) {
              [DYYYManager downloadAllImages:imageURLs];
          }

          if (livePhotos.count == 0 && imageURLs.count == 0) {
              [DYYYUtils showToast:@"没有找到合适格式的图片"];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:allImagesViewModel];
    }

    // 接口保存功能
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
    // 1.0.23 第二批：49 接口保存——没填接口地址也显示，点按时提示去设置里填（跟他的一键保存做法一致，按钮一直都在）。
    if (enableApiDownload) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存";
        apiDownload.action = ^{
          if (apiKey.length == 0) {
              [DYYYUtils showToast:@"先在设置 → 功能设置 → 接口解析保存媒体 里填接口地址"];
              return;
          }
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          if (shareLink.length == 0) {
              [DYYYUtils showToast:@"无法获取分享链接"];
              return;
          }
          // 使用封装的方法进行解析下载
          [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:apiDownload];
    }

    // 封面下载功能
    if (enableSaveCover && self.awemeModel.awemeType != 68) {
        AWELongPressPanelBaseViewModel *coverViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        coverViewModel.awemeModel = self.awemeModel;
        coverViewModel.actionType = 667;
        coverViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        coverViewModel.describeString = @"保存封面";
        coverViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          if (videoModel && videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                if (success) {
                                } else {
                                    [DYYYUtils showToast:@"封面保存已取消"];
                                }
                              }];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:coverViewModel];
    }

    // 音频下载功能
    if (enableSaveAudio) {
        AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioViewModel.awemeModel = self.awemeModel;
        audioViewModel.actionType = 668;
        audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        audioViewModel.describeString = @"保存音频";
        audioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEMusicModel *musicModel = awemeModel.music;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioViewModel];
    }

    // 创建视频功能
    if (enableCreateVideo && self.awemeModel.awemeType == 68) {
        AWELongPressPanelBaseViewModel *createVideoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        createVideoViewModel.awemeModel = self.awemeModel;
        createVideoViewModel.actionType = 677;
        createVideoViewModel.duxIconName = @"ic_videosearch_outlined_20";
        createVideoViewModel.describeString = @"保存视频"; // 1.0.23 第二批：68 按他的说法改叫保存视频
        createVideoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;

          // 收集普通图片URL
          NSMutableArray *imageURLs = [NSMutableArray array];
          // 收集实况照片信息（图片URL+视频URL）
          NSMutableArray *livePhotos = [NSMutableArray array];

          // 获取背景音乐URL
          NSString *bgmURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              bgmURL = awemeModel.music.playURL.originURLList.firstObject;
          }

          // 处理所有图片和实况
          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSString *bestURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          bestURL = urlString;
                          break;
                      }
                  }

                  if (!bestURL && imageModel.urlList.count > 0) {
                      bestURL = imageModel.urlList.firstObject;
                  }

                  // 如果是实况照片，需要收集图片和视频URL
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      if (videoURL) {
                          [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                      }
                  } else {
                      // 普通图片
                      [imageURLs addObject:bestURL];
                  }
              }
          }

          // 调用视频创建API
          [DYYYManager createVideoFromMedia:imageURLs
              livePhotos:livePhotos
              bgmURL:bgmURL
              progress:^(NSInteger current, NSInteger total, NSString *status) {
              }
              completion:^(BOOL success, NSString *message) {
                if (success) {
                } else {
                    [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                }
              }];

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:createVideoViewModel];
    }

    // 复制文案功能
    if (enableCopyText) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";
        copyText.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          [[UIPasteboard generalPasteboard] setString:descText];
          [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyText];
    }

    // 复制分享链接功能
    if (enableCopyLink) {
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制链接";
        copyShareLink.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          NSString *cleanedURL = cleanShareURL(shareLink);
          [[UIPasteboard generalPasteboard] setString:cleanedURL];
          [DYYYToast showSuccessToastWithMessage:@"分享链接已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyShareLink];
    }

    // 过滤用户功能
    if (enableFilterUser) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 674;
        filterKeywords.duxIconName = @"ic_userban_outlined_20";
        filterKeywords.describeString = @"过滤用户";
        filterKeywords.action = ^{
          AWEUserModel *author = self.awemeModel.author;
          NSString *nickname = author.nickname ?: @"未知用户";
          NSString *shortId = author.shortID ?: @"";
          // 创建当前用户的过滤格式 "nickname-shortid"
          NSString *currentUserFilter = [NSString stringWithFormat:@"%@-%@", nickname, shortId];
          // 获取保存的过滤用户列表
          NSString *savedUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"] ?: @"";
          NSArray *userArray = [savedUsers length] > 0 ? [savedUsers componentsSeparatedByString:@","] : @[];
          BOOL userExists = NO;
          for (NSString *userInfo in userArray) {
              NSArray *components = [userInfo componentsSeparatedByString:@"-"];
              if (components.count >= 2) {
                  NSString *userId = [components lastObject];
                  if ([userId isEqualToString:shortId] && shortId.length > 0) {
                      userExists = YES;
                      break;
                  }
              }
          }
          NSString *actionButtonText = userExists ? @"取消过滤" : @"添加过滤";
          [DYYYBottomAlertView showAlertWithTitle:@"过滤用户视频"
              message:[NSString stringWithFormat:@"用户: %@ (ID: %@)", nickname, shortId]
              avatarURL:nil
              cancelButtonText:@"管理过滤列表"
              confirmButtonText:actionButtonText
              cancelAction:^{
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:userArray];
                keywordListView.onConfirm = ^(NSArray *users) {
                  NSString *userString = [users componentsJoinedByString:@","];
                  [[NSUserDefaults standardUserDefaults] setObject:userString forKey:@"DYYYFilterUsers"];
                  [DYYYUtils showToast:@"过滤用户列表已更新"];
                };
                [keywordListView show];
              }
              closeAction:nil
              confirmAction:^{
                // 添加或移除用户过滤
                NSMutableArray *updatedUsers = [NSMutableArray arrayWithArray:userArray];
                if (userExists) {
                    // 移除用户
                    NSMutableArray *toRemove = [NSMutableArray array];
                    for (NSString *userInfo in updatedUsers) {
                        NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                        if (components.count >= 2) {
                            NSString *userId = [components lastObject];
                            if ([userId isEqualToString:shortId]) {
                                [toRemove addObject:userInfo];
                            }
                        }
                    }
                    [updatedUsers removeObjectsInArray:toRemove];
                    [DYYYUtils showToast:@"已从过滤列表中移除此用户"];
                } else {
                    // 添加用户
                    [updatedUsers addObject:currentUserFilter];
                    [DYYYUtils showToast:@"已添加此用户到过滤列表"];
                }
                // 保存更新后的列表
                NSString *updatedUserString = [updatedUsers componentsJoinedByString:@","];
                [[NSUserDefaults standardUserDefaults] setObject:updatedUserString forKey:@"DYYYFilterUsers"];
              }];
        };
        [viewModels addObject:filterKeywords];
    }

    // 过滤文案功能
    if (enableFilterKeyword) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 675;
        filterKeywords.duxIconName = @"ic_funnel_outlined_20";
        filterKeywords.describeString = @"过滤文案";
        filterKeywords.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          NSString *propName = nil;
          if (self.awemeModel.propGuideV2) {
              propName = self.awemeModel.propGuideV2.propName;
          }
          DYYYFilterSettingsView *filterView = [[DYYYFilterSettingsView alloc] initWithTitle:@"过滤关键词调整" text:descText propName:propName];
          filterView.onConfirm = ^(NSString *selectedText) {
            if (selectedText.length > 0) {
                NSString *currentKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"] ?: @"";
                NSString *newKeywords;
                if (currentKeywords.length > 0) {
                    newKeywords = [NSString stringWithFormat:@"%@,%@", currentKeywords, selectedText];
                } else {
                    newKeywords = selectedText;
                }
                [[NSUserDefaults standardUserDefaults] setObject:newKeywords forKey:@"DYYYFilterKeywords"];
                [DYYYUtils showToast:[NSString stringWithFormat:@"已添加过滤词: %@", selectedText]];
            }
          };
          // 设置过滤关键词按钮回调
          filterView.onKeywordFilterTap = ^{
            // 获取保存的关键词
            NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"] ?: @"";
            NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
            // 创建并显示关键词列表视图
            DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];
            // 设置确认回调
            keywordListView.onConfirm = ^(NSArray *keywords) {
              // 将关键词数组转换为逗号分隔的字符串
              NSString *keywordString = [keywords componentsJoinedByString:@","];
              // 保存到用户默认设置
              [[NSUserDefaults standardUserDefaults] setObject:keywordString forKey:@"DYYYFilterKeywords"];
              // 显示提示
              [DYYYUtils showToast:@"过滤关键词已更新"];
            };
            // 显示关键词列表视图
            [keywordListView show];
          };
          [filterView show];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:filterKeywords];
    }

    if (enableTimerClose) {
        AWELongPressPanelBaseViewModel *timerCloseViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        timerCloseViewModel.awemeModel = self.awemeModel;
        timerCloseViewModel.actionType = 676;
        timerCloseViewModel.duxIconName = @"ic_c_alarm_outlined";
        // 检查是否已有定时任务在运行
        NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
        BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
        timerCloseViewModel.describeString = hasActiveTimer ? @"取消定时" : @"定时关闭";
        timerCloseViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
          BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
          if (hasActiveTimer) {
              [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYTimerShutdownTime"];
              [DYYYUtils showToast:@"已取消定时关闭任务"];
              return;
          }
          // 读取上次设置的时间
          NSInteger defaultMinutes = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYTimerCloseMinutes"];
          if (defaultMinutes <= 0) {
              defaultMinutes = 5;
          }
          NSString *defaultText = [NSString stringWithFormat:@"%ld", (long)defaultMinutes];
          DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"设置定时关闭时间" defaultText:defaultText placeholder:@"请输入关闭时间(单位:分钟)"];
          inputView.onConfirm = ^(NSString *inputText) {
            NSInteger minutes = [inputText integerValue];
            if (minutes <= 0) {
                minutes = 5;
            }
            // 保存用户设置的时间以供下次使用
            [[NSUserDefaults standardUserDefaults] setInteger:minutes forKey:@"DYYYTimerCloseMinutes"];
            NSInteger seconds = minutes * 60;
            NSTimeInterval shutdownTimeValue = [[NSDate date] timeIntervalSince1970] + seconds;
            [[NSUserDefaults standardUserDefaults] setObject:@(shutdownTimeValue) forKey:@"DYYYTimerShutdownTime"];
            [DYYYUtils showToast:[NSString stringWithFormat:@"抖音将在%ld分钟后关闭...", (long)minutes]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              NSNumber *currentShutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimerShutdownTime"];
              if (currentShutdownTime != nil && [currentShutdownTime doubleValue] <= [[NSDate date] timeIntervalSince1970]) {
                  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYTimerShutdownTime"];
                  // 显示确认关闭弹窗，而不是直接退出
                  DYYYConfirmCloseView *confirmView = [[DYYYConfirmCloseView alloc] initWithTitle:@"定时关闭" message:@"定时关闭时间已到，是否关闭抖音？"];
                  [confirmView show];
              }
            });
          };
          [inputView show];
        };
        [viewModels addObject:timerCloseViewModel];
    }

    // ===== 顾海龙抖音长按项（686-695）=====
    if (GHLGetBool(GHL_KEY_EXTRACT_AUDIO)) {
        AWELongPressPanelBaseViewModel *extractAudioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        extractAudioViewModel.awemeModel = self.awemeModel;
        extractAudioViewModel.actionType = 686;
        extractAudioViewModel.duxIconName = @"ic_music_outlined";
        extractAudioViewModel.describeString = @"提取原声";
        extractAudioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLExtractOriginalAudioForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:extractAudioViewModel];
    }

    if (GHLGetBool(GHL_KEY_NO_WATERMARK_SHARE_LINK)) {
        AWELongPressPanelBaseViewModel *noWatermarkViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        noWatermarkViewModel.awemeModel = self.awemeModel;
        noWatermarkViewModel.actionType = 687;
        noWatermarkViewModel.duxIconName = @"ic_link_outlined";
        noWatermarkViewModel.describeString = @"复制无水印链接";
        noWatermarkViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLCopyNoWatermarkLinkForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:noWatermarkViewModel];
    }

    if (GHLGetBool(GHL_KEY_BACKGROUND_AUDIO)) {
        AWELongPressPanelBaseViewModel *pipViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        pipViewModel.awemeModel = self.awemeModel;
        pipViewModel.actionType = 688;
        pipViewModel.duxIconName = @"ic_pip_outlined";
        pipViewModel.describeString = @"画中画播放";
        pipViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          // 1.0.19：先把 sheet 收掉再找播放器——sheet 盖着时查找只能看到面板自己的控制器，
          // feed 的播放器被挡住，B 路 0 个控制器（1.0.18 日志 15:50:38 那次）。
          // 等 0.4 秒让收起动画跑完再触发。
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GHLStartPiPWithCaller(@"网格点按");
          });
        };
        [viewModels addObject:pipViewModel];
    }

    if (GHLGetBool(GHL_KEY_VOICE_PACKAGE)) {
        AWELongPressPanelBaseViewModel *voicePreviewViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        voicePreviewViewModel.awemeModel = self.awemeModel;
        voicePreviewViewModel.actionType = 689;
        voicePreviewViewModel.duxIconName = @"ic_voice_outlined";
        voicePreviewViewModel.describeString = @"语音包试听";
        voicePreviewViewModel.action = ^{
          GHLPreviewVoicePackage(GHLGetString(GHL_KEY_VOICE_PACKAGE_ID));
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:voicePreviewViewModel];

        AWELongPressPanelBaseViewModel *voiceShareViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        voiceShareViewModel.awemeModel = self.awemeModel;
        voiceShareViewModel.actionType = 690;
        voiceShareViewModel.duxIconName = @"ic_share_outlined";
        voiceShareViewModel.describeString = @"语音包读文案并分享";
        voiceShareViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSString *text = awemeModel.descriptionString;
          if (text.length == 0) text = @"顾海龙抖音";
          NSString *voiceId = GHLGetString(GHL_KEY_VOICE_PACKAGE_ID);
          [DYYYUtils showToast:@"正在用语音包合成语音…"];
          GHLSynthesizeVoicePackageText(text, voiceId, ^(NSURL *fileURL) {
            if (!fileURL) {
                [DYYYUtils showToast:@"语音合成失败"];
                return;
            }
            UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            [rootVC presentViewController:activityVC animated:YES completion:nil];
          });
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:voiceShareViewModel];
    }

    if (GHLGetBool(GHL_KEY_SAVE_AVATAR)) {
        AWELongPressPanelBaseViewModel *avatarViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        avatarViewModel.awemeModel = self.awemeModel;
        avatarViewModel.actionType = 691;
        avatarViewModel.duxIconName = @"ic_avatar_outlined";
        avatarViewModel.describeString = @"保存头像";
        avatarViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSURL *avatarURL = nil;
          if (awemeModel.author && awemeModel.author.avatarMedium && awemeModel.author.avatarMedium.originURLList.count > 0) {
              avatarURL = [NSURL URLWithString:awemeModel.author.avatarMedium.originURLList.firstObject];
          }
          if (!avatarURL) {
              [DYYYUtils showToast:@"拿不到头像地址"];
          } else {
              [DYYYManager downloadMedia:avatarURL
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                GHLLog(@"保存头像：%@", success ? @"成功" : @"失败");
                              }];
              [DYYYUtils showToast:@"头像保存中…"];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:avatarViewModel];
    }

    if (GHLGetBool(GHL_KEY_COPY_PROFILE)) {
        AWELongPressPanelBaseViewModel *profileViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        profileViewModel.awemeModel = self.awemeModel;
        profileViewModel.actionType = 692;
        profileViewModel.duxIconName = @"ic_user_outlined";
        profileViewModel.describeString = @"复制个人资料";
        profileViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEUserModel *author = awemeModel.author;
          if (!author) {
              [DYYYUtils showToast:@"拿不到作者资料"];
          } else {
              NSString *profile = [NSString stringWithFormat:@"昵称：%@\n抖音号：%@\n简介：%@", author.nickname ?: @"", author.shortID ?: @"", author.signature ?: @""];
              [[UIPasteboard generalPasteboard] setString:profile];
              [DYYYUtils showToast:@"个人资料已复制"];
              GHLLog(@"复制个人资料：%@", author.nickname);
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:profileViewModel];
    }

    if (GHLGetBool(GHL_KEY_AUDIO_SHARE)) {
        AWELongPressPanelBaseViewModel *audioShareViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioShareViewModel.awemeModel = self.awemeModel;
        audioShareViewModel.actionType = 693;
        audioShareViewModel.duxIconName = @"ic_share_outlined";
        audioShareViewModel.describeString = @"分享音频";
        audioShareViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSURL *audioURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:awemeModel.music.playURL.originURLList.firstObject];
          }
          if (!audioURL) {
              [DYYYUtils showToast:@"这个视频没有背景音乐"];
          } else {
              [DYYYManager downloadMediaWithProgress:audioURL
                                           mediaType:MediaTypeAudio
                                               audio:nil
                                            progress:nil
                                          completion:^(BOOL success, NSURL *fileURL) {
                                            if (!success || !fileURL) {
                                                [DYYYUtils showToast:@"音频下载失败"];
                                                return;
                                            }
                                            GHLRunOnMain(^{
                                              UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
                                              UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                                              [rootVC presentViewController:activityVC animated:YES completion:nil];
                                            });
                                          }];
              [DYYYUtils showToast:@"音频下载中，好了就弹分享…"];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioShareViewModel];
    }

    // 1.0.23：长按面板新增两项（清单 9 号，按抖音图层的做法）。
    // 「复制下载链接」和「解析保存（影片/音频）」他那套里有，咱们已经有了——
    // 复制下载链接＝687 复制无水印链接（解析后的直链），解析保存＝673 接口保存＋
    // 666 保存视频／668 保存音频；不重复加，只补没有的两项。
    if (GHLGetBool(GHL_KEY_AWEME_DATA)) {
        AWELongPressPanelBaseViewModel *awemeDataViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        awemeDataViewModel.awemeModel = self.awemeModel;
        awemeDataViewModel.actionType = 694;
        awemeDataViewModel.duxIconName = @"ic_data_outlined";
        awemeDataViewModel.describeString = @"获取作品数据";
        awemeDataViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLShowAwemeDataForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:awemeDataViewModel];
    }

    if (GHLGetBool(GHL_KEY_IMAGE_PREVIEW)) {
        AWELongPressPanelBaseViewModel *imagePreviewViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imagePreviewViewModel.awemeModel = self.awemeModel;
        imagePreviewViewModel.actionType = 695;
        imagePreviewViewModel.duxIconName = @"ic_image_outlined";
        imagePreviewViewModel.describeString = @"图片预览";
        imagePreviewViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          GHLPreviewAwemeImagesForAwemeModel(awemeModel);
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imagePreviewViewModel];
    }

    newGroupModel.groupArr = viewModels;

    // 返回自定义组+原始组的结果
    if (originalArray.count > 0) {
        NSMutableArray *resultArray = [originalArray mutableCopy];
        [resultArray insertObject:newGroupModel atIndex:0];
        NSArray *finalArray = [resultArray copy];
        gDYYYLongPressPanelData = finalArray; // 1.0.10：强引用持有到面板收起
        DYYYLongPressGridPanelRetryAfterData(self); // 1.0.10：数据一到就主线程补一次盖网格
        return finalArray;
    } else {
        NSArray *finalArray = @[ newGroupModel ];
        gDYYYLongPressPanelData = finalArray; // 1.0.10：强引用持有到面板收起
        DYYYLongPressGridPanelRetryAfterData(self); // 1.0.10：数据一到就主线程补一次盖网格
        return finalArray;
    }
}
%end

// 隐藏评论分享功能

%hook AWEIMCommentShareUserHorizontalCollectionViewCell

- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentShareToFriends"]) {
        self.hidden = YES;
    } else {
        self.hidden = NO;
    }
}

%end

%hook AWEIMCommentShareUserHorizontalSectionController

- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentShareToFriends"]) {
        return CGSizeZero;
    }
    return %orig;
}

- (void)configCell:(id)cell index:(NSInteger)index model:(id)model {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentShareToFriends"]) {
        return;
    }
    %orig;
}

%end

%ctor {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYUserAgreementAccepted"]) {
        %init;
    }
}

%group DYYYFilterSetterGroup

%hook HOOK_TARGET_OWNER_CLASS

- (void)setModelsArray:(id)arg1 {
    if (![arg1 isKindOfClass:[NSArray class]]) {
        %orig(arg1);
        return;
    }

    NSArray *inputArray = (NSArray *)arg1;
    NSMutableArray *filteredArray = nil;

    for (id item in inputArray) {
        NSString *className = NSStringFromClass([item class]);

        BOOL shouldFilter = ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelFavoriteCommentElement"] && DYYYGetBool(@"DYYYHideCommentLongPressFavorite")) ||
                            ([className isEqualToString:@"AWECommentIMSwiftImpl.CommentLongPressPanelForwardElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressDaily"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCopyElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressCopy"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSaveImageElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressSaveImage"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelReportElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressReport"]) ||

                            ([className isEqualToString:@"AWECommentStudioSwiftImpl.CommentLongPressPanelVideoReplyElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressVideoReply"]) ||

                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelPictureSearchElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressPictureSearch"]) ||

                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelSearchElement"] &&
                             [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLongPressSearch"]);

        if (shouldFilter) {
            if (!filteredArray) {
                filteredArray = [NSMutableArray arrayWithCapacity:inputArray.count];
                for (id keepItem in inputArray) {
                    if (keepItem == item)
                        break;
                    [filteredArray addObject:keepItem];
                }
            }
            continue;
        }

        if (filteredArray) {
            [filteredArray addObject:item];
        }
    }

    if (filteredArray) {
        %orig([filteredArray copy]);
    } else {
        %orig(arg1);
    }
}

%end
%end

%ctor {
    Class ownerClass = objc_getClass("AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionViewModel");
    if (ownerClass) {
        %init(DYYYFilterSetterGroup, HOOK_TARGET_OWNER_CLASS = ownerClass);
    }
}
