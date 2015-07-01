//
//  AppDelegate.m
//  NKFaceFeatureTest
//
//  Created by nanoka____ on 2015/06/22.
//  Copyright (c) 2015年 nanoka____. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

/*========================================================
 ; AppDelegate
 ========================================================*/
@implementation AppDelegate

/*--------------------------------------------------------
 ; dealloc : 解放
 ;      in :
 ;     out :
 --------------------------------------------------------*/
-(void)dealloc
{
    self.window = nil;
}

/*--------------------------------------------------------
 ; didFinishLaunchingWithOptions : アプリ起動時に呼び出される
 ;                            in : UIApplication * application
 ;                               : NSDictionary *launchOptions
 ;                           out : BOOL YES
 --------------------------------------------------------*/
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    //Windowの作成
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    //ViewControllerの作成
    ViewController *oViewController = [[ViewController alloc] init];
    //NavigationControllerを作成
    UINavigationController *oNavigationController = [[UINavigationController alloc] initWithRootViewController:oViewController];
    oViewController = nil;
    //Navigationbarを非表示にする
    [oNavigationController setNavigationBarHidden:YES];
    //WindowにViewControllerをセット
    self.window.rootViewController = oNavigationController;
    oNavigationController = nil;
    //Windowの表示
    [self.window makeKeyAndVisible];
    return YES;
}


@end
