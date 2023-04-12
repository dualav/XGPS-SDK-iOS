//
//  Puck+XGPS160.m
//  SkyPro for XGPS160
//
//  Created by jk on 20181804.
//  Copyright © 2018 namsung. All rights reserved.
//
#import "Puck.h"
#import "Puck+XGPS160.h"
#import "TripLog.h"


@implementation Puck (XGPS160)

extern volatile int           rsp160_cmd;
extern volatile uint8_t       rsp160_buf[256];
extern volatile uint32_t      rsp160_len;


extern uint8_t         cfgGpsSettings;
extern uint8_t         cfgLogInterval;
extern uint16_t        cfgLogBlock;
extern uint16_t        cfgLogOffset;


static EASession* pSession;

uint8_t*        pFwReadPtr = NULL;


uint16_t getU16M( uint8_t* buf );
uint32_t getU24M( uint8_t* buf );
uint16_t getU16L( uint8_t* buf );
uint32_t getU32M( uint8_t* buf );


bool update160command( uint8_t cmd, uint8_t* arg, uint16_t argLen )
{
    NSOutputStream*        streamOutput;
    
    static uint8_t    buf[256];
    uint32_t            size = 0;
    uint32_t            i;
    uint8_t            cs;
    uint32_t            timeout;
    
    buf[0] = 0x88;
    buf[1] = 0xEE;
    buf[2] = argLen + 1;
    buf[3] = (uint8_t) cmd;
    
    if( argLen > 0 )
    {
        if( arg == NULL || argLen > 240 ) {
            return false;
        }
        for( i=0; i<argLen; i++ )
            buf[4 + i] = arg[i];
    }
    
    size = 4 + argLen;
    
    cs = 0;
    for( i=0; i<size; i++ ) {
        cs += buf[i];
    }
    
    buf[size] = cs;
    size++;
    
    streamOutput = [pSession outputStream];
    
    if( !streamOutput || ![streamOutput hasSpaceAvailable] ) {
        NSLog(@"streamOutput not available");
        return false;
    }
    
    rsp160_cmd = 0;
    
    [streamOutput write: buf maxLength:size];
    
    timeout = 10;
    
    while( rsp160_cmd == 0 && timeout )
    {
        if( timeout == 3 || timeout == 6 ) {
            [streamOutput write: buf maxLength:size];
        }
        [NSThread sleepForTimeInterval:(0.2)];
        timeout--;
    }
    
    if( timeout == 0 ) {
        NSLog(@"command %02x timeout", cmd);
        return FALSE;
    }
    return TRUE;
}

-(void) handle160fwDataRsp :(uint8_t*)Pkt :(uint8_t)PktLen
{
    rsp160_len = PktLen - 2;
    NSLog(@"cmd160_fwData ptr=%p", pFwReadPtr);
    if( PktLen > 2 ) {
        if( pFwReadPtr != NULL ) {
            memcpy( pFwReadPtr, &Pkt[5], rsp160_len );
            //    print("r %x ", pFwReadPtr);
        }
    }
    rsp160_cmd = Pkt[0];
}

// TO DO: Need to check MODEL before applying hardcoded FW version number

//#include "../../xgps160fw1.3.5.h"
//#include "../../xgps160fw1.4.1.h"

#define latestMajor 1
#define latestMinor 4
#define latestBuild 1

- (bool) fwupdateNeeded
{
    NSArray *versionNumbers = [self.firmwareRev componentsSeparatedByString:@"."];
    int majorVersion = [[versionNumbers objectAtIndex:0] intValue];
    int minorVersion = [[versionNumbers objectAtIndex:1] intValue];
    int buildVersion = [[versionNumbers objectAtIndex:2] intValue];
    
    int curVer;
    int latestVer;
    
    curVer = majorVersion;
    curVer *= 1000;
    curVer += minorVersion;
    curVer *= 1000;
    curVer += buildVersion;
    
    latestVer = latestMajor;
    latestVer *= 1000;
    latestVer += latestMinor;
    latestVer *= 1000;
    latestVer += latestBuild;
    
    return ( curVer < latestVer );
}



bool    bFwThread = FALSE;
uint32_t    nFwSize = 0;
uint8_t*    pFwData = NULL;
uint32_t    nFwPages;
uint32_t    nFwBlocks;
uint32_t    nowUpdateBlock;

uint8_t*    pFwReadBuf = NULL;


#define FW_ADDR_OFFSET    0
#define FW_MAX_SIZE        0x18000        // 0x18000 = 96KB

#define FW_BLOCKSIZE    4096        // the block size is inherent property of the flash memory device
#define    FW_PAGESIZE        128

#define FW_PAGESPERBLOCK    (FW_BLOCKSIZE / FW_PAGESIZE)




bool erase_block( uint32_t blockNum )
{
    uint32_t    addr;
    uint8_t    buf[256];
    
    
    addr = blockNum * FW_BLOCKSIZE + FW_ADDR_OFFSET;
    addr >>= 4;
    
    buf[0] = (uint8_t) (addr >> 8);    // addr H
    buf[1] = (uint8_t) (addr & 0xFF);    // addr L
    
    if( !update160command( cmd160_fwErase, buf, 2 ) ) {
        NSLog(@"erase block %d / %d fail", blockNum + 1, nFwBlocks);
        return FALSE;
    }
    //print(".");
    
    return TRUE;
}

bool send_block( uint32_t blockNum, uint32_t dataSize )
{
    uint8_t*    blockBuf;
    
    uint32_t    dataLeft;
    uint32_t    page;
    uint32_t    bufLen;
    uint32_t    addr;
    uint8_t    buf[256];
    
    blockBuf = pFwData + (blockNum * FW_BLOCKSIZE);
    
    dataLeft = dataSize;
    
    NSLog(@"send block %d/%d ", blockNum + 1, nFwBlocks );
    
    // blockNum 이 현재 블럭 , nFwBlocks 이 총갯수
    nowUpdateBlock = blockNum + 1;
    
    for( page=0; page < FW_PAGESPERBLOCK; page++ )
    {
        //print("send page %d / %d ", page + 1 + blockNum * FW_PAGESPERBLOCK, nFwPages);
        
        if( dataLeft > FW_PAGESIZE )
            bufLen = FW_PAGESIZE;
        else
            bufLen = dataLeft;
        
        
        addr = blockNum * FW_BLOCKSIZE + FW_ADDR_OFFSET + page * FW_PAGESIZE;
        addr >>= 4;
        
        buf[0] = (uint8_t) (addr >> 8);    // addr H
        buf[1] = (uint8_t) (addr & 0xFF);    // addr L
        buf[2] = bufLen;    // size
        memcpy( &buf[3], blockBuf + (FW_PAGESIZE * page), bufLen );
        
        
        if( !update160command( cmd160_fwData, buf, bufLen + 3 ) ) {
            NSLog(@"send block fail");
            return FALSE;
        }
        
        dataLeft -= bufLen;
        if( dataLeft == 0 )
            break;
    }
    
    return TRUE;
}


bool recv_block( uint32_t blockNum, uint32_t dataSize )
{
    uint32_t    dataLeft;
    
    uint32_t    page;
    uint32_t    bufLen;
    uint32_t    addr;
    uint8_t    buf[32];
    uint32_t    mmcnt;
    
    
    dataLeft = dataSize;
    
    //print( "recv block %d/%d ", blockNum + 1, nFwBlocks);
    
    for( page=0; page < FW_PAGESPERBLOCK ; page++ )
    {
        //print("recv page %d / %d ", page + 1 + blockNum * FW_PAGESPERBLOCK, nFwPages);
        if (userCancel)
            return FALSE;

        if( dataLeft > FW_PAGESIZE )
            bufLen = FW_PAGESIZE;
        else
            bufLen = dataLeft;
        
        addr = blockNum * FW_BLOCKSIZE + FW_ADDR_OFFSET + page * FW_PAGESIZE;
        addr >>= 4;
        
        buf[0] = (uint8_t) (addr >> 8);    // addr H
        buf[1] = (uint8_t) (addr & 0xFF);    // addr L
        buf[2] = bufLen;    // size
        
        pFwReadPtr = &pFwReadBuf[(blockNum * FW_BLOCKSIZE) + (page * FW_PAGESIZE)];
        
        if( !update160command( cmd160_fwDataR, buf, 3 ) ) {
            NSLog(@"fwDataR fail");
            return FALSE;
        }
        
        //    Sleep(10);
        
        if( rsp160_cmd == cmd160_fwData && rsp160_len > 5 && rsp160_len < 144 ) {
        }
        else {
            NSLog(@"<rsp = %d, %d>", rsp160_cmd, rsp160_len);
        }
        
        dataLeft -= bufLen;
        
        if( dataLeft == 0 )
            break;
    }
    
    // 3. Compare
    
    mmcnt = 0;
    for( addr = 0; addr < dataSize; addr++ ) {
        if( pFwData[blockNum * FW_BLOCKSIZE + addr] != pFwReadBuf[blockNum * FW_BLOCKSIZE + addr] ) {
            NSLog(@"verify %04x %02x %02x", addr,
                  pFwData[blockNum * FW_BLOCKSIZE + addr],
                  pFwReadBuf[blockNum * FW_BLOCKSIZE + addr]);
            mmcnt++;
            break;
        }
    }
    
    if( mmcnt > 0 ) {
        // Fail
        //print("block(%d) write failed %d\r\n", addr, mmcnt);
        NSLog(@"<verify fail %d bytes>", mmcnt);
        return FALSE;
    }
    
    NSLog(@"recv_block ok");
    return TRUE;
}




int updateRunning = 0;
bool updateFail = false;
bool userCancel = false;

- (void) procFwUpdate:(void (^)(float percent))progressBlock
{
    uint32_t    blk;
    
    uint8_t    buf[256];
    uint32_t    addr;
    
    uint16_t    cs = 0;
    uint32_t    retry;
    BOOL    bFail = FALSE;
    uint32_t    mmcnt;
    
    uint32_t    sizeLeft;
    uint32_t    sizeWrite;
    uint16_t    failCount = 0;
    
    NSLog(@"procFwUpdate");
    
    if( nFwSize == 0 ) {
        NSLog(@"firmware size is zero");
        return;
    }
    
    updateRunning = TRUE;
    updateFail = false;// 20210401 jk -- app shows failure on success on next retry

    pFwReadBuf = (uint8_t*) malloc( nFwSize + FW_BLOCKSIZE );
    if( pFwReadBuf == NULL ) {
        NSLog(@"malloc() for read buffer failed");
        bFwThread = FALSE;
        return;
    }
    
    memset( pFwReadBuf, 0, nFwSize );
    
    nFwBlocks = (nFwSize + FW_BLOCKSIZE - 1) / FW_BLOCKSIZE;
    
    nFwPages = (nFwSize + FW_PAGESIZE - 1) / FW_PAGESIZE;
    
    sizeLeft = nFwSize;
    
    if (progressBlock != nil) {
        progressBlock(0);
    }
    
    if( !update160command( cmd160_streamStop, NULL, 0 ) ) {
        NSLog(@"fwPause error");
    }

    do {
        
        // For each blocks (XGPS170 1KB block)
        //
        NSLog(@"erasing");
        for( blk=0; blk < nFwBlocks && _session; blk++ )
        {
            bFail = userCancel;
            retry = 5;
            do {
                if( erase_block( blk ) ) {
                    failCount = 0;
                    break;
                }
                else
                    failCount++;
            } while( --retry && _session );
        }
        
        if( bFail || !_session || failCount > 5) {
            bFail = TRUE;
            updateFail = YES;
            break;
        }
        
        if( blk == nFwBlocks ) {
            NSLog(@"erase ok");
        }
        else {
            continue;
        }
        
        for( blk=0; blk < nFwBlocks; blk++ )
        {
            bFail = userCancel;
            if( sizeLeft >= FW_BLOCKSIZE )
                sizeWrite = FW_BLOCKSIZE;
            else
                sizeWrite = sizeLeft;
            
            retry = 10;
            do {
                // 1. Send firmware data
                if( _session && send_block( blk, sizeWrite ) ) {
                    failCount = 0;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        // % 로 구한다
                        float percent = (float)nowUpdateBlock /(float)nFwBlocks;
                        
                        NSLog(@"%d%% nowBlock : %d   totalBlock: %d", (int)(percent * 100), nowUpdateBlock,nFwBlocks);
                        
                        if (progressBlock != nil) {
                            progressBlock(percent);
                        }
                    });
                    
                    // 2. Read back firmware data
                    // 3. Compare
                    if( recv_block( blk, sizeWrite ) ) {
                        failCount = 0;
                        bFail = FALSE;
                        break;
                    }
                    else {
                        failCount++;
                        NSLog(@"failCount: %d", failCount);
                    }
                }
                else {
                    failCount++;
                }
                
                if( !_session || failCount > 5 || userCancel) {
                    bFail = TRUE;
                    break;
                }
                
                erase_block( blk );
                
                retry--;
            } while( retry > 0 );
            
            if( !_session || bFail ) {
                bFail = TRUE;
                updateFail = YES;
                break;
            }
            
            sizeLeft -= sizeWrite;
        }
        
        if( bFail ) {
            updateFail = YES;
            break;
        }
        
        //update160command(0x33,NULL,0);
        
        mmcnt = 0;
        cs = 0;
        for( addr = 0; addr < nFwSize; addr++ ) {
            cs += pFwData[addr];
            if( pFwData[addr] != pFwReadBuf[addr] ) {
                NSLog(@"verify err: %04x %02x %02x", addr, pFwData[addr], pFwReadBuf[addr]);
                mmcnt++;
            }
        }
        
        if( mmcnt > 0 ) {
            // Fail
            NSLog(@"verify failed %d", mmcnt);
            if( mmcnt < 10 ) {
                for( addr = 0; addr < nFwSize; addr++ ) {
                    if( pFwData[addr] != pFwReadBuf[addr] ) {
                        NSLog(@"err: %04x %02x %02x", addr, pFwData[addr], pFwReadBuf[addr]);
                    }
                }
            }
            NSLog(@"Update aborted %d %d", addr, nFwSize);
            bFail = TRUE;
            break;
        }
        
        NSLog(@"Checksum passed for %d bytes. cs=%04x", nFwSize, cs);
        
        
        // 4. Issue update command
        
        // send the address the firmware should be placed.
        addr = FW_ADDR_OFFSET;
        addr >>= 4;
        
        buf[0] = (uint8_t) (addr >> 8);    // addr H
        buf[1] = (uint8_t) (addr & 0xFF);    // addr L
        buf[2] = (uint8_t) (nFwSize >> 16);
        buf[3] = (uint8_t) (nFwSize >> 8);
        buf[4] = (uint8_t) (nFwSize & 0xFF);
        buf[5] = (uint8_t) (cs >> 8);
        buf[6] = (uint8_t) (cs & 0xff);
        buf[7] = 0;
        
        if( update160command(cmd160_fwUpdate, buf, 8) ) {
            NSLog(@"Update confirm received %02x", rsp160_cmd);
        }
        
        if( rsp160_cmd == cmd160_fwRsp && rsp160_buf[0] == cmd160_fwUpdate )
        {
            NSLog(@"returned cs=%02x%02x", rsp160_buf[2], rsp160_buf[3]);
            
            if(    rsp160_buf[1] == 0x11 )
            {
                NSLog(@"Issuing cpu reset command");
                
                // Reset the MCU
                buf[0] = 0xAB;    // addr H
                buf[1] = 0XCD;    // addr L
                
                if( !update160command( cmd160_fwUpdate, buf, 7 ) ) {
                    NSLog(@"reset command failed. Please reset the unit manually");
                }
                
                bFail = FALSE;
                
                break; // added by bjahn
                
            }
            else if( rsp160_buf[1] == 0xEE ) {
                NSLog(@"Update verify checksum failure");
            }
            else {
                NSLog(@"Update verify unknown failure <%02x>", rsp160_buf[1]);
            }
        }
        
    } while(0);
    
    free( pFwReadBuf );
    
    if( bFail ) {
        NSLog(@"Firmware Update failed");
        bFwThread = FALSE;
        if (progressBlock != nil) {
            progressBlock(-1);
        }
        return;
    }
    
    NSLog(@"Updated firmware was sent. XGPS160 will be reset with new firmware.");
    
    updateRunning = FALSE;
    return;
}

- (bool) fwupdateCancel
{
    // return true if the operation can be stopped, after stopping it
    userCancel = true;
    return false;
}

// 업뎃 종료시
- (bool)FwUpdateFinished
{
    NSLog(@"FwUpdateFinished");
    
    // 0.6에서 저장한건지 판단
    if ([self.firmwareRev isEqualToString:@"1.0.4"] ||
        [self.firmwareRev isEqualToString:@"1.0.6"])
    {
        [[NSUserDefaults standardUserDefaults] setValue:@"yes" forKey:@"overwriteOldSetting"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"1.0.4   1.0.6  에서 펌웨어 업뎃 되엇음");
    }
    
    updateRunning = 0;
    
    // 업데이트가 끝나면 연결 대기 상태로..
    // 업데이트가 성공했을때만 성공 알림창으로... 아니라면 실패 알림 창으로
    if (updateFail) {
        return false;
    }
    else {
        return true;
    }
    
}

- (BOOL) fwupdateStart:(NSMutableData*)firmwareData fileSize:(int)fwsize progress:(void (^)(float percent))progressBlock
{
    uint8_t *fwcode =  (uint8_t*) [firmwareData bytes];
    NSLog(@"fwupdateStart size=%d", fwsize);
    userCancel = FALSE;

    pSession = _session;
    
    if( !_session ) {
        NSLog(@"Session not open");
        return FALSE;
    }
    
    if( updateRunning ) {
        NSLog(@"Firmware Update already running");
        return FALSE;
    }
    
    if( fwcode == nil || fwsize == 0 ) {
        return FALSE;
    }
    else {
        nFwSize = fwsize;
        pFwData = fwcode;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        [self procFwUpdate:progressBlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self FwUpdateFinished];
        });
    });
    
    return TRUE;
}







-(void) handle160getSettingsRsp :(uint8_t*)Pkt :(uint8_t)PktLen
{
    cfgGpsSettings = Pkt[2];
    cfgLogInterval = Pkt[3];
    self.logInterval = Pkt[3];

    cfgLogBlock = getU16L( &Pkt[4] );
    cfgLogOffset = getU16L( &Pkt[6] );

    if( cfgGpsSettings & 0x40 ) {
        NSLog(@"Datalog Enabled");
        self.loggingEnabled = YES;
    }
    else {
        NSLog(@"Datalog Disabled");
        self.loggingEnabled = NO;
    }

    if( cfgGpsSettings & 0x80 ) {
        NSLog(@"Datalog OverWrite");
        self.logOverWriteEnabled = YES;
    }
    else {
        NSLog(@"Datalog no OverWrite");
        self.logOverWriteEnabled = NO;
    }

    if( cfgGpsSettings & 0x10 ){
        NSLog(@"Short NMEA");
        self.useShortNMEA = YES;
    }
    else{
        NSLog(@"Standard NMEA");
        self.useShortNMEA = NO;
    }
    
    self.gpsRefreshRate = 10;   // XGPS160 has fixed 10Hz refresh rate
}



char* dateStr( uint16_t ddd )
{
    static char str[20];
    int tmp;
    int yy, mm, dd;
    
    tmp = ddd;
    yy = 2012 + tmp/372;
    mm = 1 + (tmp % 372) / 31;
    dd = 1 + tmp % 31;
    
    sprintf( str, "%04d/%02d/%02d", yy, mm, dd);
    
    return str;
}

char* todStr( uint32_t tod )
{
    static char str[20];
    int    hr, mn, ss;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    
    sprintf( str, "%02d:%02d:%02d", hr, mn, ss);
    
    return str;
}

-(void) handle160LogList :(uint8_t*)Pkt :(uint8_t)PktLen
{
    uint16_t    listIdx = getU16M( &Pkt[3] );
    uint16_t    listTotal = getU16M( &Pkt[5] );
    loglistitem_t    li;

    NSLog(@"listIdx= %d / %d", listIdx, listTotal);

    if( listIdx == listTotal || PktLen < (sizeof(loglistitem_t) + 4) ) {
        
        NSSortDescriptor *publishedSorter = [[NSSortDescriptor alloc] initWithKey:TITLETEXT
                                                                        ascending:YES
                                                                         selector:@selector(localizedCaseInsensitiveCompare:)];
        [self.logListData sortUsingDescriptors:[NSArray arrayWithObject:publishedSorter]];
        /////////////////////////////////////////////////////////////////////////////////////////
        
        if (self.tripLogDelegate != nil)
            [self.tripLogDelegate logListComplete];
        
        NSLog(@"로그리스트 응답 처리 완료");
    }
    else {
        memcpy( (void*) &li, &Pkt[7], sizeof(loglistitem_t) );
        
        NSMutableDictionary * logDic = [[NSMutableDictionary alloc]init];
        
        [logDic setObject: [NSString stringWithFormat:@"%c", li.sig] forKey:@"sig"];
        [logDic setObject: [NSString stringWithFormat:@"%d", li.interval] forKey:@"interval"];
        [logDic setObject: [NSString stringWithFormat:@"%s", dateStr(li.startDate)] forKey:@"startDate"];
        [logDic setObject: [NSString stringWithFormat:@"%s", todStr(li.startTod)] forKey:@"startTod"];
        [logDic setObject: [NSString stringWithFormat:@"%d", li.startBlock] forKey:@"startBlock"];
//        [logDic setObject: [NSString stringWithFormat:@"%d", li.countEntry] forKey:@"countEntry"];
        [logDic setObject: [NSString stringWithFormat:@"%d", (li.countBlock * EntriesPerBlock)] forKey:@"countEntry"];
        [logDic setObject: [NSString stringWithFormat:@"%d", li.countBlock] forKey:@"countBlock"];
        [logDic setObject: [NSString stringWithFormat:@"%s  %s",dateStr(li.startDate),todStr(li.startTod)] forKey: TITLETEXT];
        
        if ([[NSString stringWithFormat:@"%s",dateStr(li.startDate)] rangeOfString:@"2188"].location == NSNotFound)
        {
            [self.logListData addObject:logDic];
        }
        logDic = nil;
    }
}
-(void) handle160LogBlock :(uint8_t*)Pkt :(uint8_t)PktLen
{
    uint32_t    addr = getU24M( &Pkt[3] );
    uint8_t    dataSize = Pkt[6];
    
    //NSLog(@"addr: %d,  dataSize: %d", addr, dataSize);
    
    logReadBulkCount += (dataSize / sizeof(logentry_t));
    
    if( addr == 0 && dataSize == 0 ) {
        // End-of-data 로그벌크 다받음
        if (self.tripLogDelegate != nil) {
            [self.tripLogDelegate logBulkProgress:logBulkRecodeCnt];
        }
        
        logReadBulkCount |= 0x1000000;
        
        [self decodeLogBulk];
        
        // 초기화
        logReadBulkCount = 0;
        logBulkRecodeCnt = 0;
        memset(logRecords, 0, 185 * 510);
    }
    else
    {
        int     i;
        uint8_t*   p = &Pkt[7];
        
        for( i=0; i<5; i++ ) {
            memcpy( &logRecords[logBulkRecodeCnt + i], p, sizeof(logentry_t) );
            p += sizeof(logentry_t);
        }
        
        logBulkRecodeCnt += 5;
        if (self.tripLogDelegate != nil) {
            [self.tripLogDelegate logBulkProgress:logBulkRecodeCnt];
        }
    }

}

-(void) handle160LogDelRsp : (uint8_t*)Pkt : (uint8_t)PktLen
{
    if (self.isFWUpdateWorking) {
        self.isFWUpdateWorking = NO;
        NSLog(@"로그 전체 삭제 완료");
    }
    else{
        [self.logListData removeAllObjects];
//        [self sendCommandToDevice:cmd160_logList :0 :NULL :0];        // logList 는 수동으로 요청!!!
        NSLog(@"개별 로그 삭제 완료");
    }
}

static double getLatLon24bit( uint8_t* buf )
{
#define kLatLonBitResolution       2.1457672e-5
    
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    d = ((double)r) * kLatLonBitResolution;
    
    if( r & 0x800000 ) {    // is South / West ?
        d = -d;
    }
    
    return d;
}

static unsigned int getUInt24bit( uint8_t* buf )
{
    unsigned int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    return r;
}

static double getLatLon32bit( uint8_t* buf )
{
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    r <<= 8;
    r |= buf[3];
    
    d = ((double)r) * 0.000001;
    
    return d;
}

-(void) decodeLogBulk
{
    logentry_t*        le;
    uint32_t            tod;
    uint32_t            tod10th;
    uint32_t            spd;
    uint16_t          dateS;
    double            fLat=0;
    double            fLon=0;
    double          fAlt=0;
    uint8_t         heading = 0;
    
    [self.logBulkDic removeAllObjects];
    
    // 스트링은 self.logDataBulk 에 잇다
    // logentry_t 길이만큼 le에 읽어오기 시작해 줄마다 끝까지 읽는다
    // 그리고 파싱하기 시작한다
    
    for (int i=0; i<logBulkRecodeCnt; i++) {
        le = &logRecords[i];
        
        if( le->type == 0 )// type=0 Original XGPS160 24-bit lat/lon
        {
            dataentry_t*    d = &le->data;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon24bit( d->lat );
            fLon = getLatLon24bit( d->lon );
            fAlt = getUInt24bit( d->alt ) * 5.0 / 3.2808399;// 5feet unit -> meters
            
            spd = getU16M( d->spd );
            heading = d->heading;
            
            dateS = le->data.date;
        }
        else if( le->type == 2 )// type=2 New 32-bit lat/lon
        {
            data2entry_t*    d = &le->data2;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon32bit( d->lat );
            fLon = getLatLon32bit( d->lon );
            fAlt = ((double)getUInt24bit( d->alt )) / 100.0;// cm(centi-meter) unit -> meters
            
            spd = getU16M( d->spd );
            heading = d->heading;
            
            dateS = le->data2.date;
            
        }
        else {
            break;
        }
        
        if (fLat != 0.0 && fLon != 0.0 && dateS != 0xFFFF )
        {
            NSMutableDictionary * bulkDic = [[NSMutableDictionary alloc]init];
            
            //NSLog(@"date %s", dateStr(dateS));
            
            [bulkDic setObject:[NSString stringWithFormat:@"%s",dateStr(dateS)] forKey:@"date"];
            // hjlee 2017.10.19 change to save as NSNumber instead NSString
            [bulkDic setObject:[NSNumber numberWithDouble:fLat] forKey:@"lat"];
            [bulkDic setObject:[NSNumber numberWithDouble:fLon] forKey:@"long"];
            [bulkDic setObject:[NSNumber numberWithDouble:fAlt] forKey:@"alt"];
            [bulkDic setObject:[NSString stringWithFormat:@"%s.%d",todStr(tod), tod10th] forKey:@"utc"];
            [bulkDic setObject:[NSNumber numberWithInteger:tod] forKey:@"tod"];
            [bulkDic setObject:[NSString stringWithFormat:@"%d",spd] forKey:@"spd"];
            [bulkDic setObject:[NSNumber numberWithInteger:heading] forKey:@"heading"];
            [bulkDic setObject:[NSString stringWithFormat:@"%s  %s",dateStr(le->data.date) ,todStr(tod)] forKey:TITLETEXT];
            
            [self.logBulkDic addObject:bulkDic];
        }
    }
    
    // 로그 상세페이지 리로드
    if (self.tripLogDelegate != nil) {
        [self.tripLogDelegate logBulkComplete:nil];
    }
    
    //    [delegate.viewController.tripsVC.tripsDetailVC bulkDataComplete];
}




-(void) cancelLoading:(int)whatCancel{
    /*
     1 로그 리스트에서 캔슬
     2 로그 상세에서 캔슬
     */
    
    if (whatCancel == 2) {
        [self.logBulkDic removeAllObjects];
        logReadBulkCount = 0;
        logBulkRecodeCnt = 0;
    }
    else{
        [self.logListData removeAllObjects];
    }
}


-(void) deleteAllLog
{
    uint8_t    buf[64]; // 0 ,  510  전부삭제 0번주소부터 510개
    uint16_t    blk = 0;
    uint16_t    numBlks = 510;
    
    buf[0] = (uint8_t) (blk >> 8);
    buf[1] = (uint8_t) (blk);
    buf[2] = (uint8_t) (numBlks >> 8);
    buf[3] = (uint8_t) (numBlks);
    
    [self sendCommandToDevice:cmd160_logDelBlock :0 :buf :4];
}



@end

