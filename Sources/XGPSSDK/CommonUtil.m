//
//  CommonUtil.m
//  SWallet
//
//  Created by SeokJae Lee on 12. 8. 9..
//  Copyright (c) 2012년 __MyCompanyName__. All rights reserved.
//

#import "CommonUtil.h"
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if_dl.h>
#include <netdb.h>
#include <net/if.h>
#include <errno.h>
#include <net/if_dl.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@implementation CommonUtil

#pragma mark - 파일 관련 래퍼 함수

+ (NSArray*) fileListCheck{
    
    NSString *filePath = [CommonUtil getDocumentDirectory];
    NSArray * fileList = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:filePath error:nil];
    NSLog(@"파일리스트 %@",fileList);
    
    return fileList;
}

+ (NSString *) getDocumentDirectory
{
	NSArray *arrayPaths	= NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	
	return [arrayPaths objectAtIndex:0];
}

+ (NSString *) getDocumentDirectoryCardName
{
    return @"";
}

+ (NSString *) filePathFromResource:(NSString *)name ext:(NSString *)ext
{
    return [[NSBundle mainBundle] pathForResource:name ofType:ext];
}

+ (BOOL) checkDirectoryPathExist:(NSString *)checkPath
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL isDir	= YES;
	if([fileManager fileExistsAtPath:checkPath isDirectory:&isDir] && isDir) return TRUE;
    
	NSError *error = nil;
	return [fileManager createDirectoryAtPath:checkPath withIntermediateDirectories:YES attributes:nil error:&error];
}

+ (BOOL) checkFilePathExist:(NSString *)checkPath
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	return [fileManager fileExistsAtPath:checkPath];
}

+ (NSString *) getUniqueFileName:(NSString *)name
{
	time_t systemTime;
	time(&systemTime);
	struct tm *localTime = localtime(&systemTime);
	
	return [NSString stringWithFormat:@"%04d%02d%02d%02d%02d%02d_%@",
            localTime->tm_year + 1900, localTime->tm_mon + 1, localTime->tm_mday,
            localTime->tm_hour, localTime->tm_min, localTime->tm_sec, name];
}

+ (BOOL) MoveFile:(NSString *)src toPath:(NSString *)dest
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:src]) return NO;
    if ([fileManager fileExistsAtPath:dest]) [fileManager removeItemAtPath:dest error:&error];
    
    return [fileManager moveItemAtPath:src toPath:dest error:&error];
}

+ (BOOL) DeleteFileAtPath:(NSString *)filePath isdir:(BOOL)isdir
{
	if (filePath == nil) return NO;
	
	if (isdir)
	{
		if (![CommonUtil checkDirectoryPathExist:filePath]) return NO;
	}
	else
	{
		if(![CommonUtil checkFilePathExist:filePath]) return NO;
	}
    
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	NSError *error = nil;
	if ([fileManager removeItemAtPath:filePath error:&error]) return YES;
    
	return NO;
}

@end
