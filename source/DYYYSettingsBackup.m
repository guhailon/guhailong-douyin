// DYYYSettingsBackup — 设置导入 / 导出 / 恢复默认（1.0.4）
#import "DYYYSettingsBackup.h"
#import "DYYYConstants.h"
#import "GHLFeatures.h"

static NSString *const kGHLBackupFileName = @"SeaDragon Douyin 配置.plist";
static NSString *const kGHLBackupVersionKey = @"version";
static NSString *const kGHLBackupSettingsKey = @"settings";

@implementation DYYYSettingsBackup

+ (NSString *)backupFilePath {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [documentsPath stringByAppendingPathComponent:@"DYYY"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:kGHLBackupFileName];
}

+ (nullable NSURL *)exportSettingsForKeys:(NSArray<NSString *> *)keys error:(NSError **)error {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        if (![key isKindOfClass:[NSString class]] || key.length == 0) continue;
        id value = [defaults objectForKey:key];
        // 只写 plist 能存的类型（开关/字符串/数字/数组/字典等），别的跳过。
        if (!value) continue;
        if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSArray class]] &&
            ![value isKindOfClass:[NSDictionary class]] && ![value isKindOfClass:[NSData class]] && ![value isKindOfClass:[NSDate class]]) {
            continue;
        }
        settings[key] = value;
    }
    NSDictionary *root = @{kGHLBackupVersionKey : DYYY_VERSION, kGHLBackupSettingsKey : settings};
    NSString *path = [self backupFilePath];
    BOOL ok = [root writeToFile:path atomically:YES];
    if (!ok) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYYYSettingsBackup"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey : @"写配置文件失败"}];
        }
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

+ (NSInteger)importSettingsFromURL:(NSURL *)url allowedKeys:(NSSet<NSString *> *)allowedKeys error:(NSError **)error {
    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"DYYYSettingsBackup" code:-2 userInfo:@{NSLocalizedDescriptionKey : @"没有选中文件"}];
        return 0;
    }
    // 文件选择器给的是安全作用域 URL，读完要关掉。
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYYYSettingsBackup"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey : @"文件不对，不是配置文件"}];
        }
        return 0;
    }
    // 容错：导出的文件是 @{version, settings}；如果有人直接给扁平字典，也认。
    NSDictionary *settings = root[kGHLBackupSettingsKey];
    if (![settings isKindOfClass:[NSDictionary class]]) settings = root;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger imported = 0;
    for (NSString *key in settings) {
        if (![key isKindOfClass:[NSString class]]) continue;
        // 只认我们自己的 key（调用方传的 settingSections 全集），不认识的忽略，
        // 绝不写抖音自己的设置。
        if (![allowedKeys containsObject:key]) continue;
        id value = settings[key];
        if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSArray class]] &&
            ![value isKindOfClass:[NSDictionary class]] && ![value isKindOfClass:[NSData class]] && ![value isKindOfClass:[NSDate class]]) {
            continue;
        }
        [defaults setObject:value forKey:key];
        imported++;
    }
    if (imported == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYYYSettingsBackup"
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey : @"文件里没有能导入的设置"}];
        }
        return 0;
    }
    return imported;
}

+ (void)resetSettingsForKeys:(NSArray<NSString *> *)keys additionalKeys:(NSArray<NSString *> *)additionalKeys {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in keys) {
        if ([key isKindOfClass:[NSString class]] && key.length > 0) [defaults removeObjectForKey:key];
    }
    for (NSString *key in additionalKeys) {
        if ([key isKindOfClass:[NSString class]] && key.length > 0) [defaults removeObjectForKey:key];
    }
    // 自选龙头、自定义背景也恢复默认（删文件，下次打开回退内置/白色）。
    GHLClearCustomLogo();
    GHLClearCustomBackground();
}

@end
