/*
 * 碰一碰重定向 · 主设置面板
 *
 * 目标多开包的选择直接【内联】在本页（不做子控制器）——
 * Preferences 的 detail 类名解析在越狱环境下不可靠，容易推出空白页。
 */
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <dlfcn.h>
#import "../APXPrefs.h"

#define OFFICIAL_BID @"com.alipay.iphoneclient"

@interface LSApplicationProxy : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSString *)applicationIdentifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (void)enumerateApplicationsOfType:(NSUInteger)type block:(void (^)(id proxy))block;
- (NSArray *)allInstalledApplications;
- (NSArray *)allApplications;
@end

@interface APXRootListController : PSListController
@end

@implementation APXRootListController

#pragma mark - 配置读写

static id APXPref(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)APX_DOMAIN);
    return v ? CFBridgingRelease(v) : nil;
}

static void APXSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)APX_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)APX_DOMAIN);
    notify_post(APX_NOTIFY_NAME);          /* 热更新 */
}

#pragma mark - 多开包检测

static Class APXWSClass(void) {
    Class c = NSClassFromString(@"LSApplicationWorkspace");
    if (c) return c;
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
        "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
        "/System/Library/PrivateFrameworks/CoreServices.framework/CoreServices",
        "/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices",
    };
    for (int i = 0; i < 4; i++) {
        if (!dlopen(paths[i], RTLD_NOW)) continue;
        c = NSClassFromString(@"LSApplicationWorkspace");
        if (c) return c;
    }
    return nil;
}

/* 返回多开包数组；diag 回传诊断文字 */
static NSArray *APXDetectClones(NSString **diag) {
    NSMutableArray *out = [NSMutableArray array];
    NSString *how = @"无";
    NSUInteger scanned = 0;

    Class wsCls = APXWSClass();
    id ws = wsCls ? [wsCls defaultWorkspace] : nil;

    NSMutableArray *all = [NSMutableArray array];
    if (ws) {
        if ([ws respondsToSelector:NSSelectorFromString(@"enumerateApplicationsOfType:block:")]) {
            void (^collect)(id) = ^(id p) { if (p) [all addObject:p]; };
            [ws enumerateApplicationsOfType:0 block:collect];
            [ws enumerateApplicationsOfType:1 block:collect];
            how = @"enumerateApplicationsOfType";
        }
        if (all.count == 0 && [ws respondsToSelector:NSSelectorFromString(@"allInstalledApplications")]) {
            NSArray *a = [ws allInstalledApplications];
            if (a.count) { [all addObjectsFromArray:a]; how = @"allInstalledApplications"; }
        }
        if (all.count == 0 && [ws respondsToSelector:NSSelectorFromString(@"allApplications")]) {
            NSArray *a = [ws allApplications];
            if (a.count) { [all addObjectsFromArray:a]; how = @"allApplications"; }
        }
    }
    scanned = all.count;

    for (id p in all) {
        NSString *b = nil;
        @try { b = [p bundleIdentifier]; } @catch (__unused NSException *e) {}
        if (![b isKindOfClass:[NSString class]]) {
            @try { b = [p applicationIdentifier]; } @catch (__unused NSException *e) {}
        }
        if (![b isKindOfClass:[NSString class]]) continue;
        if ([b isEqualToString:OFFICIAL_BID] || ![b hasPrefix:OFFICIAL_BID]) continue;
        NSString *n = nil;
        @try { n = [p localizedName]; } @catch (__unused NSException *e) {}
        [out addObject:@{@"bid": b, @"name": ([n isKindOfClass:[NSString class]] && n.length) ? n : b}];
    }

    /* 兜底：用 tweak 在支付宝进程内写入的清单 */
    if (out.count == 0) {
        id saved = APXPref(APX_KEY_CLONES);
        if ([saved isKindOfClass:[NSArray class]]) {
            for (NSDictionary *c in saved) {
                if ([c isKindOfClass:[NSDictionary class]] && [c[@"bid"] length]) [out addObject:c];
            }
            if (out.count) how = [how stringByAppendingString:@"+配置清单"];
        }
    }

    if (diag) {
        *diag = [NSString stringWithFormat:@"检测方式 %@ ｜ 扫描 %lu 个 App ｜ 命中 %lu 个多开包",
                 how, (unsigned long)scanned, (unsigned long)out.count];
    }
    return out;
}

#pragma mark - 界面

- (NSArray *)specifiers {
    NSMutableArray *s = [NSMutableArray array];

    /* ── 总开关 ── */
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"总开关"];
    [g setProperty:@"关闭后贴碰一碰完全由官方支付宝处理 —— 想用官方账号付款时关掉即可，"
                  "不需要卸载插件或在 Choicy 里屏蔽。"
             forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self switchRow:@"启用碰一碰重定向" key:APX_KEY_ENABLED dflt:YES]];

    /* ── 跳转方式 ── */
    g = [PSSpecifier groupSpecifierWithName:@"跳转方式"];
    [g setProperty:@"开启后每次贴纸都会先弹窗，让你当场选择跳转或用官方支付。"
             forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self switchRow:@"跳转前询问" key:APX_KEY_ASK dflt:NO]];

    /* ── 目标多开包（内联单选）── */
    NSArray *clones = APXDetectClones(NULL);
    NSString *cur = APXPref(APX_KEY_TARGET) ?: @"";

    NSString *effName = @"（无）";
    for (NSDictionary *c in clones) {
        if ([c[@"bid"] isEqualToString:(cur.length ? cur : (clones.count ? clones[0][@"bid"] : @""))]) {
            effName = c[@"name"]; break;
        }
    }

    g = [PSSpecifier groupSpecifierWithName:@"目标多开支付宝"];
    [g setProperty:[NSString stringWithFormat:@"当前目标：%@%@",
                    effName,
                    (cur.length ? @"" : @"（未手选，默认第一个）")]
             forKey:@"footerText"];
    [s addObject:g];

    /* 只列真实的多开包；未指定时勾在第一个（即实际生效的那个） */
    NSString *effective = cur.length ? cur : (clones.count ? clones[0][@"bid"] : @"");
    for (NSUInteger i = 0; i < clones.count; i++) {
        NSDictionary *c = clones[i];
        BOOL on = [c[@"bid"] isEqualToString:effective];
        NSString *title = c[@"name"];
        if (!cur.length && i == 0) title = [title stringByAppendingString:@"（默认）"];
        if (on) title = [@"✓ " stringByAppendingString:title];   /* 勾写进标题，绝对可见 */
        [s addObject:[self radioRow:title bid:c[@"bid"] on:on]];
    }
    if (clones.count == 0) {
        PSSpecifier *none = [PSSpecifier preferenceSpecifierNamed:@"（未检测到多开支付宝）"
                                                           target:nil set:nil get:nil detail:nil
                                                             cell:PSStaticTextCell edit:nil];
        [s addObject:none];
    }

    _specifiers = s;
    return _specifiers;
}

- (PSSpecifier *)switchRow:(NSString *)name key:(NSString *)key dflt:(BOOL)dflt {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPref:forSpecifier:)
                                                        get:@selector(getPref:)
                                                     detail:nil
                                                       cell:PSSwitchCell edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(dflt) forKey:@"default"];
    return sp;
}

- (PSSpecifier *)radioRow:(NSString *)name bid:(NSString *)bid on:(BOOL)on {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self set:nil get:nil detail:nil
                                                       cell:PSLinkCell edit:nil];
    [sp setProperty:bid forKey:@"apxBID"];      /* 标记：这是可点的一行 */
    [sp setProperty:@(YES) forKey:@"enabled"];
    [sp setProperty:@(on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone)
             forKey:@"accessoryType"];
    return sp;
}

- (id)getPref:(PSSpecifier *)sp {
    NSString *key = [sp propertyForKey:@"key"];
    id v = APXPref(key);
    return v ?: [sp propertyForKey:@"default"];
}

- (void)setPref:(id)value forSpecifier:(PSSpecifier *)sp {
    APXSetPref([sp propertyForKey:@"key"], value);
}

/*
 * 点按分发。
 * 代码构建的 PSSpecifier 不会把 @"action" 字符串自动转成 SEL，
 * 必须自己覆写这个方法手动分发（这也是社区通行做法）。
 */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *bid = [spec propertyForKey:@"apxBID"];

    if (bid) {
        APXSetPref(APX_KEY_TARGET, bid);
        _specifiers = nil;          /* 重建，刷新勾选 */
        [self reloadSpecifiers];
    } else {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
