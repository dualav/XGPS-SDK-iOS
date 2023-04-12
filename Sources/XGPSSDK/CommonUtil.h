//
//  CommonUtil.h
//  SWallet
//
//  Created by SeokJae Lee on 12. 8. 9..
//  Copyright (c) 2012년 __MyCompanyName__. All rights reserved.
//


#import <Foundation/Foundation.h>

@interface CommonUtil : NSObject

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
