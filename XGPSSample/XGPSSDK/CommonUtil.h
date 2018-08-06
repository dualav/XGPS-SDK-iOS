//
//  CommonUtil.h
//  SWallet
//
//  Created by SeokJae Lee on 12. 8. 9..
//  Copyright (c) 2012년 __MyCompanyName__. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CommonUtil : NSObject



/*
 * OK 버튼만 있는 알림 창
 */
+ (void) ShowAlertWithOk:(NSString *)title message:(NSString *)message delegate:(id)delegate;

/*
 * Cancel 버튼만 있는 알림 창
 */
+ (void) ShowAlertWithCancel:(NSString *)title message:(NSString *)message delegate:(id)delegate;

/*
 * OK-CANCEL 버튼 있는 알림 창
 */
+ (void) ShowAlertWithOkCancel:(NSString *)title message:(NSString *)message delegate:(id)delegate tag:(NSInteger)tag;
+ (void) ShowAlertWithOkCancel:(UIAlertViewStyle)style title:(NSString *)title
                       message:(NSString *)message delegate:(id)delegate tag:(NSInteger)tag;

/*
 * YES 버튼만 있는 알림 창
 */
+ (void) ShowAlertWithYes:(NSString *)title message:(NSString *)message delegate:(id)delegate tag:(NSInteger)tag;

/*
 * YES-NO 버튼 있는 알림 창
 */
+ (void) ShowAlertWithYesNo:(NSString *)title message:(NSString *)message delegate:(id)delegate tag:(NSInteger)tag;

/*
 * 사용자 정의 알림 창
 */
+ (void) ShowAlert:(NSString *)title message:(NSString *)message delegate:(id)delegate tag:(NSInteger)tag
 cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSString *)otherButtonTitles, ...;

+ (void) ShowAlertWithBtnOne:(NSString *)title message:(NSString *)message delegate:(id)delegate b1Str:(NSString *)b1Str tag:(int)tag;

+ (void) ShowAlertWithBtnTwo:(NSString *)title message:(NSString *)message delegate:(id)delegate b1Str:(NSString *)b1Str b2Str:(NSString *)b2Str tag:(int)tag;

#pragma mark - 버튼 이미지 및 텍스트 색 설정
#pragma mark - 이미지 가져오는 함수

+ (UIImage *) getImageWithName:(NSString *)name;
+ (UIImage *) getImageWithFile:(NSString *)path;


#pragma mark - 파일 관련 래퍼 함수
/*
 *  도큐먼트 폴더 반환
 */
+ (NSString *) getDocumentDirectory;


//
+ (NSString *) getDocumentDirectoryCardName;

/*
 * 리소스에 있는 파일 경로
 */
+ (NSString *) filePathFromResource:(NSString *)name ext:(NSString *)ext;


/*
 * 폴더 존재하는지 검사. 없으면 생성
 */
+ (BOOL) checkDirectoryPathExist:(NSString *)checkPath;

/*
 * 경로에 파일이 존재하는지
 */
+ (BOOL) checkFilePathExist:(NSString *)checkPath;

/*
 * 유니크한 파일 이름 생성. 시간으로.
 */
+ (NSString *) getUniqueFileName:(NSString *)name;

/*
 * 파일 이동
 */
+ (BOOL) MoveFile:(NSString *)src toPath:(NSString *)dest;

/*
 * 파일 삭제
 */
+ (BOOL) DeleteFileAtPath:(NSString *)filePath isdir:(BOOL)isdir;


/*
 * 폴더에 파일 리스트 체크
 */
+ (NSArray*) fileListCheck;

@end
