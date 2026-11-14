#import "DYYYAboutDialogView.h"
#import "DYYYUtils.h"

@interface DYYYAboutDialogView () <UITextViewDelegate>
@end

@implementation DYYYAboutDialogView

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    return [self initWithTitle:title message:message joinGroupURL:nil];
}

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message joinGroupURL:(nullable NSString *)joinGroupURL {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        self.joinGroupURL = joinGroupURL;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];

        // 判断当前深色/浅色模式
        BOOL isDarkMode = [DYYYUtils isDarkMode];

        // 创建模糊效果视图 - 根据模式调整效果样式
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight]];
        self.blurView.frame = self.bounds;
        self.blurView.alpha = isDarkMode ? 0.3 : 0.2;
        [self addSubview:self.blurView];

        // 计算文本高度，动态调整弹窗高度
        UIFont *messageFont = [UIFont systemFontOfSize:15];
        CGSize constraintSize = CGSizeMake(260, CGFLOAT_MAX);
        NSAttributedString *attributedMessage = [[NSAttributedString alloc] initWithString:message attributes:@{NSFontAttributeName : messageFont}];
        CGRect textRect = [attributedMessage boundingRectWithSize:constraintSize options:NSStringDrawingUsesLineFragmentOrigin context:nil];

        CGFloat textHeight = textRect.size.height;
        CGFloat maxTextHeight = 320;
        CGFloat titleHeight = 44;
        CGFloat buttonHeight = 58;
        CGFloat buttonPadding = 28;
        // 1.0.4：关于弹窗多一行“加入QQ群”按钮，弹窗加高 54。
        CGFloat joinRowHeight = joinGroupURL.length > 0 ? 54 : 0;
        CGFloat actualTextHeight = MIN(textHeight, maxTextHeight);
        CGFloat contentHeight = titleHeight + actualTextHeight + buttonHeight + buttonPadding + joinRowHeight;
        BOOL needsScrolling = textHeight > maxTextHeight;

        // 创建内容视图 - 根据模式选择背景色
        self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, contentHeight)];
        self.contentView.center = CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2);
        self.contentView.backgroundColor = isDarkMode ? [UIColor colorWithRed:30 / 255.0 green:30 / 255.0 blue:30 / 255.0 alpha:1.0] : [UIColor whiteColor];
        self.contentView.layer.cornerRadius = [DYYYUtils dYYYSettingsCardCornerRadius];
        self.contentView.layer.masksToBounds = YES;
        self.contentView.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [self addSubview:self.contentView];

        // 标题 - 根据模式调整文本颜色
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 260, 24)];
        self.titleLabel.text = title;
        self.titleLabel.textColor =
            isDarkMode ? [UIColor colorWithRed:230 / 255.0 green:230 / 255.0 blue:235 / 255.0 alpha:1.0] : [UIColor colorWithRed:45 / 255.0 green:47 / 255.0 blue:56 / 255.0 alpha:1.0];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        [self.contentView addSubview:self.titleLabel];

        // 消息内容 - 适配深色模式
        self.messageTextView = [[UITextView alloc] initWithFrame:CGRectMake(20, 54, 260, (contentHeight - joinRowHeight - buttonHeight - 54))];
        self.messageTextView.backgroundColor = self.contentView.backgroundColor;
        self.messageTextView.font = messageFont;
        self.messageTextView.editable = NO;
        self.messageTextView.scrollEnabled = needsScrolling;
        self.messageTextView.showsVerticalScrollIndicator = needsScrolling;
        self.messageTextView.dataDetectorTypes = UIDataDetectorTypeLink;
        self.messageTextView.selectable = YES;
        self.messageTextView.delegate = self;

        // 创建段落样式并设置居中对齐
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.alignment = NSTextAlignmentCenter;
        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:message];
        [attributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, message.length)];
        [attributedString addAttribute:NSFontAttributeName
                                 value:messageFont  // 使用自定义的 messageFont
                                 range:NSMakeRange(0, message.length)];

        // 根据模式设置整体文本颜色
        UIColor *messageTextColor =
            isDarkMode ? [UIColor colorWithRed:180 / 255.0 green:180 / 255.0 blue:185 / 255.0 alpha:1.0] : [UIColor colorWithRed:124 / 255.0 green:124 / 255.0 blue:130 / 255.0 alpha:1.0];
        [attributedString addAttribute:NSForegroundColorAttributeName value:messageTextColor range:NSMakeRange(0, message.length)];

        // 保持链接设置
        NSRange telegramRange = [message rangeOfString:@"Telegram @vita_app"];
        if (telegramRange.location != NSNotFound) {
            [attributedString addAttribute:NSLinkAttributeName value:@"https://t.me/vita_app" range:telegramRange];
        }

        NSRange githubRange = [message rangeOfString:@"仓库地址 Wtrwx/DYYY"];
        if (githubRange.location != NSNotFound) {
            [attributedString addAttribute:NSLinkAttributeName value:@"https://github.com/Wtrwx/DYYY" range:githubRange];
        }

        NSRange huamiGithubRange = [message rangeOfString:@"开源地址 huami1314/DYYY"];
        if (huamiGithubRange.location != NSNotFound) {
            [attributedString addAttribute:NSLinkAttributeName value:@"https://github.com/huami1314/DYYY" range:huamiGithubRange];
        }
        NSRange huamiTGGroup = [message rangeOfString:@"Telegram @huamidev"];
        if (huamiTGGroup.location != NSNotFound) {
            [attributedString addAttribute:NSLinkAttributeName value:@"https://t.me/huamidev" range:huamiTGGroup];
        }
        // 1.0.4：群号做成能点的链接，点一下复制群号（不是真的网址，拦截后复制到剪贴板）。
        NSRange groupNumberRange = [message rangeOfString:@"1130823454"];
        if (groupNumberRange.location != NSNotFound) {
            [attributedString addAttribute:NSLinkAttributeName value:@"ghl://copy-group-number" range:groupNumberRange];
        }
        self.messageTextView.attributedText = attributedString;

        // 设置链接颜色（1.0.4 统一视觉：链接用龙头金，不再用上游绿）
        self.messageTextView.linkTextAttributes = @{
            NSForegroundColorAttributeName : [DYYYUtils dYYYGoldAccentColor],
            NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)
        };

        [self.contentView addSubview:self.messageTextView];

        // 添加内容和按钮之间的分割线，调整位置和颜色（有加群按钮时分割线在按钮上方）
        UIView *contentButtonSeparator = [[UIView alloc] initWithFrame:CGRectMake(0, contentHeight - buttonHeight - joinRowHeight, 300, 0.5)];
        contentButtonSeparator.backgroundColor =
            isDarkMode ? [UIColor colorWithRed:60 / 255.0 green:60 / 255.0 blue:60 / 255.0 alpha:1.0] : [UIColor colorWithRed:230 / 255.0 green:230 / 255.0 blue:230 / 255.0 alpha:1.0];
        [self.contentView addSubview:contentButtonSeparator];

        // 1.0.4：加入QQ群按钮（只在关于弹窗显示），点一下打开加群链接。
        if (joinGroupURL.length > 0) {
            self.joinGroupButton = [UIButton buttonWithType:UIButtonTypeSystem];
            self.joinGroupButton.frame = CGRectMake(20, contentHeight - buttonHeight - joinRowHeight + 7, 260, 40);
            self.joinGroupButton.backgroundColor = [[DYYYUtils dYYYGoldAccentColor] colorWithAlphaComponent:0.15];
            self.joinGroupButton.layer.cornerRadius = 10;
            [self.joinGroupButton setTitle:@"加入QQ群" forState:UIControlStateNormal];
            self.joinGroupButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
            [self.joinGroupButton setTitleColor:[DYYYUtils dYYYGoldAccentColor] forState:UIControlStateNormal];
            [self.joinGroupButton addTarget:self action:@selector(joinGroupTapped) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:self.joinGroupButton];
        }

        // 确认按钮 - 根据模式调整颜色（1.0.4 统一视觉：确定用龙头金）
        self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.confirmButton.frame = CGRectMake(0, contentHeight - buttonHeight + 0.5, 300, 53);
        self.confirmButton.backgroundColor = [UIColor clearColor];
        [self.confirmButton setTitle:@"确定" forState:UIControlStateNormal];
        UIColor *confirmButtonColor = [DYYYUtils dYYYGoldAccentColor];
        [self.confirmButton setTitleColor:confirmButtonColor forState:UIControlStateNormal];
        [self.confirmButton addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.confirmButton];
    }
    return self;
}

- (void)show {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }
    if (!window) {
        return;
    }
    [window addSubview:self];

    [UIView animateWithDuration:0.12
                     animations:^{
                       self.contentView.alpha = 1.0;
                       self.contentView.transform = CGAffineTransformIdentity;
                     }];
}

- (void)dismiss {
    [UIView animateWithDuration:0.1
        animations:^{
          self.contentView.alpha = 0;
          self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
          self.blurView.alpha = 0;
        }
        completion:^(BOOL finished) {
          [self removeFromSuperview];
        }];
}

- (void)confirmTapped {
    if (self.onConfirm) {
        self.onConfirm();
    }
    [self dismiss];
}

// 1.0.4：点“加入QQ群”打开加群链接（系统浏览器/QQ 处理），然后关弹窗。
- (void)joinGroupTapped {
    if (self.joinGroupURL.length > 0) {
        NSURL *url = [NSURL URLWithString:self.joinGroupURL];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
    [self dismiss];
}

#pragma mark - UITextViewDelegate

// 1.0.4：点群号复制到剪贴板（ghl:// 是内部标记，不是真网址，不跳转）。
- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction {
    if ([URL.scheme isEqualToString:@"ghl"] && [URL.host isEqualToString:@"copy-group-number"]) {
        NSString *groupNumber = [textView.text substringWithRange:characterRange];
        if (groupNumber.length > 0) {
            [[UIPasteboard generalPasteboard] setString:groupNumber];
            [DYYYUtils showToast:@"群号已复制"];
        }
        return NO;
    }
    return YES;
}

@end
