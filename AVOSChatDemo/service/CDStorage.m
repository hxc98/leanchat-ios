//
//  CDStorage.m
//  LeanChat
//
//  Created by lzw on 15/1/29.
//  Copyright (c) 2015年 AVOS. All rights reserved.
//

#import "CDStorage.h"
#import "CDUtils.h"

#define MSG_TABLE_SQL @"CREATE TABLE IF NOT EXISTS `msgs` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `msg_id` VARCHAR(63) UNIQUE NOT NULL,`convid` VARCHAR(63) NOT NULL,`object` BLOB NOT NULL,`time` VARCHAR(63) NOT NULL)"
#define ROOMS_TABLE_SQL @"CREATE TABLE IF NOT EXISTS `rooms` (`id` INTEGER PRIMARY KEY AUTOINCREMENT,`convid` VARCHAR(63) UNIQUE NOT NULL,`unread_count` INTEGER DEFAULT 0)"

#define FIELD_ID @"id"
#define FIELD_CONVID @"convid"
#define FIELD_OBJECT @"object"
#define FIELD_TIME @"time"
#define FIELD_MSG_ID @"msg_id"

#define FIELD_UNREAD_COUNT @"unread_count"

static CDStorage* _storage;

@interface CDStorage(){
    
}

@property FMDatabaseQueue* dbQueue;

@end

@implementation CDStorage

+(instancetype)sharedInstance{
    if(_storage==nil){
        _storage=[[CDStorage alloc] init];
    }
    return _storage;
}

-(void)close{
    _storage=nil;
}

- (NSString *)dbPathWithUserId:(NSString*)userId {
    NSString *libPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [libPath stringByAppendingPathComponent:[NSString stringWithFormat:@"chat_%@",userId]];
}

-(void)setupWithUserId:(NSString*)userId{
    _dbQueue=[FMDatabaseQueue databaseQueueWithPath:[self dbPathWithUserId:userId]];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:MSG_TABLE_SQL];
        [db executeUpdate:ROOMS_TABLE_SQL];
    }];
}

-(FMDatabaseQueue*)getDBQueue{
    return _dbQueue;
}

#pragma mark - msgs table

-(NSArray*)getMsgsWithConvid:(NSString*)convid maxTime:(int64_t)time limit:(int)limit{
    __block NSArray* msgs=nil;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSString* timeStr=[CDUtils strOfInt64:time];
        FMResultSet* rs=[db executeQuery:@"select * from msgs where convid=? and time<? order by time desc limit ?" withArgumentsInArray:@[convid,timeStr,@(limit)]];
        msgs=[CDUtils reverseArray:[self getMsgsByResultSet:rs]];
    }];
    return msgs;
}

-(AVIMTypedMessage*)getMsgByMsgId:(NSString*)msgId{
    __block AVIMTypedMessage* msg=nil;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* rs=[db executeQuery:@"SELECT * FROM msgs where msg_id=?" withArgumentsInArray:@[msgId]];
        if([rs next]){
            msg=[self getMsgByResultSet:rs];
        }
        [rs close];
    }];
    return msg;
}

-(BOOL)updateMsg:(AVIMTypedMessage*)msg byMsgId:(NSString*)msgId{
    __block BOOL result;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:msg];
        result=[db executeUpdate:@"UPDATE msgs SET object=? WHERE msg_id=?" withArgumentsInArray:@[data,msgId]];
    }];
    return result;
}

-(BOOL)updateFailedMsg:(AVIMTypedMessage*)msg byTmpId:(NSString*)tmpId{
    __block BOOL result;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:msg];
        result=[db executeUpdate:@"UPDATE msgs SET object=?,time=?,msg_id=? WHERE msg_id=?"
                   withArgumentsInArray:@[data,[CDUtils strOfInt64:msg.sendTimestamp],msg.messageId,tmpId]];
    }];
    return result;
}

-(BOOL)updateStatus:(AVIMMessageStatus)status byMsgId:(NSString*)msgId{
    AVIMTypedMessage* msg=[self getMsgByMsgId:msgId];
    if(msg){
        msg.status=status;
        return [self updateMsg:msg byMsgId:msgId];
    }else{
        return NO;
    }
}

-(NSMutableArray*)getMsgsByResultSet:(FMResultSet*)rs{
    NSMutableArray *result = [NSMutableArray array];
    while ([rs next]) {
        AVIMTypedMessage* msg=[self getMsgByResultSet:rs];
        if(msg!=nil){
            [result addObject:msg];
        }
    }
    [rs close];
    return result;
}

-(AVIMTypedMessage* )getMsgByResultSet:(FMResultSet*)rs{
    NSData* data=[rs objectForColumnName:FIELD_OBJECT];
    if([data isKindOfClass:[NSData class]] && data.length>0){
        AVIMTypedMessage* msg;
        @try {
            msg=[NSKeyedUnarchiver unarchiveObjectWithData:data];
        }
        @catch (NSException *exception) {
            [CDUtils alert:exception.description];
        }
        return msg;
    }else{
        return nil;
    }
}

-(int64_t)insertMsg:(AVIMTypedMessage*)msg{
    __block int64_t rowId;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:msg];
        [db executeUpdate:@"INSERT INTO msgs (msg_id,convid,object,time) VALUES(?,?,?,?)"
                 withArgumentsInArray:@[msg.messageId,msg.conversationId,data,[CDUtils strOfInt64:msg.sendTimestamp]]];
        rowId=[db lastInsertRowId];
    }];	
    return rowId;
}

-(void)deleteMsgsByConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM msgs where convid=?" withArgumentsInArray:@[convid]];
    }];
}

#pragma mark - rooms table

-(CDRoom*)getRoomByResultSet:(FMResultSet*)rs{
    CDRoom* room=[[CDRoom alloc] init];
    room.convid=[rs stringForColumn:FIELD_CONVID];
    room.unreadCount=[rs intForColumn:FIELD_UNREAD_COUNT];
    room.lastMsg=[self getMsgByResultSet:rs];
    return room;
}

-(NSArray*)getRooms{
    NSMutableArray* rooms=[NSMutableArray array];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* rs=[db executeQuery:@"SELECT * FROM rooms LEFT JOIN (SELECT msgs.object,MAX(time) as time ,msgs.convid as msg_convid FROM msgs GROUP BY msgs.convid) ON rooms.convid=msg_convid ORDER BY time DESC"];
        while ([rs next]) {
            [rooms addObject:[self getRoomByResultSet:rs]];
        }
        [rs close];
    }];
    return rooms;
}

-(void)insertRoomWithConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"INSERT INTO rooms (convid) VALUES(?) " withArgumentsInArray:@[convid]];
    }];
}

-(void)deleteRoomByConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM rooms WHERE convid=?" withArgumentsInArray:@[convid]];
    }];
}

-(void)incrementUnreadWithConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"UPDATE rooms SET unread_count=unread_count+1 WHERE convid=?" withArgumentsInArray:@[convid]];
    }];
}

-(void)clearUnreadWithConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"UPDATE rooms SET unread_count=0 WHERE convid=?" withArgumentsInArray:@[convid]];
    }];
}

@end
