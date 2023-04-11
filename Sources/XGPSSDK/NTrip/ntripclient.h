//
//  ntripclient.h
//  SkyPro for XGPS160
//
//  Created by hjlee on 2018. 4. 17..
//  Copyright © 2018년 namsung. All rights reserved.
//

#ifndef ntripclient_h
#define ntripclient_h

extern int stop;
extern int sigstop;
extern int isUsingNtrip;
extern char ggaSentence[200];

void ntripMountPoints (void *self, char *buffer, int buffLen);
void ntripDataWrite (void *object, char *buffer, int buffLen, int error);
int ntripTest(void *object, char *server, char *port, char *user, char *pw, char *mount, int mode);
#endif /* ntripclient_h */
