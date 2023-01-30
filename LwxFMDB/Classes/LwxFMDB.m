//
//  LwxFMDB.m
//  LwxFMDBDemo
//
//  Created by Lwx on 16/10/24.
//  Copyright © 2016年 Lwx. All rights reserved.
//

#import "LwxFMDB.h"
#import <FMDB/FMDB.h>
#import <objc/runtime.h>

#define SQLITE_NAME @"lwxSqlite.sqlite"

@interface LwxFMDB()

@property (nonatomic, assign) BOOL isOpen;//yes = 已打开
@property (nonatomic, strong) FMDatabase *lwxDB;

@end

static LwxFMDB *LlwxFMDB;
static NSOperationQueue *_queue;

@implementation LwxFMDB(tool)

//合并key return @"xxx,xxx,xxx..."
- (NSString *)mergeKey:(NSArray *)array{
    NSString *str = [array componentsJoinedByString:@","];
    return str;
}

//合并value return @"?,?,?..."
- (NSString *)mergeVlaue:(NSArray *)array{
    NSMutableArray *arr = [[NSMutableArray alloc]init];
    for (int i = 0; i < array.count; i++){
        [arr addObject:@"?"];
    }
    
    NSString *str = [arr componentsJoinedByString:@","];
    return str;
}

- (BOOL)checkSQLIsOpen{
    if (self.isOpen){
        return YES;
    }
    NSLog(@"数据库未打开，操作前请先打开数据库！");
    return NO;
}

- (BOOL)isTableHave:(id)tableClass{
    NSString *existsSql = [NSString stringWithFormat:@"select count(name) as countNum from sqlite_master where type = 'table' and name = '%@'",NSStringFromClass([tableClass class])];
    FMResultSet *rs = [self.lwxDB executeQuery:existsSql];
    if ([rs next]) {
        NSInteger count = [rs intForColumn:@"countNum"];
        if (count != 0) {
            NSLog(@"存在");
            [rs close];
            return YES;
        }
    }
    [rs close];
    return NO;
}

+ (BOOL)isCustomProperty:(NSString *)propertyName{
    if ([propertyName isEqualToString:@"hash"] ||
        [propertyName isEqualToString:@"superclass"] ||
        [propertyName isEqualToString:@"description"] ||
        [propertyName isEqualToString:@"debugDescription"]) {
        return NO;
    }
    return YES;
}

//关闭数据库
- (BOOL)closeDB{
    BOOL close = [self.lwxDB close];
    if(close){
        self.isOpen = NO;
        NSLog(@"数据库关闭成功");
    }else{
        self.isOpen = YES;
        NSLog(@"数据库关闭失败");
    }
    return close;
}

+ (void)cleanFMDB{
    if (LlwxFMDB) {
        [LlwxFMDB closeDB];
    }
    LlwxFMDB = nil;
}

@end

@implementation LwxFMDB

+ (instancetype)intance{
    @synchronized (LlwxFMDB) {
        if(LlwxFMDB == nil){
            LlwxFMDB = [[LwxFMDB alloc] initWithKey:nil];
        }
    }
    return LlwxFMDB;
}

+ (void)initIntance:(NSString *)key{
    @synchronized (LlwxFMDB) {
        if (_queue == nil) {
            _queue = [[NSOperationQueue alloc]init];
            _queue.maxConcurrentOperationCount = 1;
            _queue.name = @"lwx_Sql_Queue";
        }else{
            [_queue cancelAllOperations];
        }
        if (LlwxFMDB) {
            [LwxFMDB cleanFMDB];
        }
        LlwxFMDB = [[LwxFMDB alloc] initWithKey:key];
    }
}

- (instancetype)initWithKey:(NSString *)key{
    self = [super init];
    if (self){
        NSString *filename;
        if (key) {
            filename = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite",key]];
        }else{
            filename = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:SQLITE_NAME];
        }
        self.lwxDB = [FMDatabase databaseWithPath:filename];
        self.isOpen = NO;
    }
    return self;
}

// 打开数据库，如果不存在则创建并且打开
- (void)openDB:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        BOOL open = [strongSelf.lwxDB open];
        if(open){
            strongSelf.isOpen = YES;
            NSLog(@"数据库打开成功");
        }else{
            strongSelf.isOpen = NO;
            NSLog(@"数据库打开失败");
        }
        if (asyncBlock) {
            asyncBlock(open);
        }
    }];
}

//关闭数据库
- (void)closeDB:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        BOOL close = [strongSelf.lwxDB close];
        if(close){
            strongSelf.isOpen = NO;
            NSLog(@"数据库关闭成功");
        }else{
            strongSelf.isOpen = YES;
            NSLog(@"数据库关闭失败");
        }
        if (asyncBlock) {
            asyncBlock(close);
        }
    }];
}

// 创建表
- (void)createATable:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf checkSQLIsOpen]){return;}
        if ([strongSelf isTableHave:tableClass]) {return;}
        NSMutableArray *array = [[NSMutableArray alloc]init];
        Class cycleClass = [tableClass class];
        do {
            unsigned int count;
            objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
            for (unsigned int i=0; i<count; i++){
                const char *propertyName = property_getName(propertyList[i]);
                NSString *propertyNameStr = [NSString stringWithFormat:@"%@ varchar",[NSString stringWithUTF8String:propertyName]];
                [array addObject:propertyNameStr];
            }
            cycleClass = class_getSuperclass(cycleClass);
        } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
        
        if (array.count == 0){
            NSLog(@"%@没有属性,创建失败",NSStringFromClass([tableClass class]));
            return;
        }
        NSString * create = [NSString stringWithFormat:@"create table if not exists %@(id integer primary key autoincrement,%@)",NSStringFromClass([tableClass class]),[strongSelf mergeKey:array]];
        BOOL success = [strongSelf.lwxDB executeUpdate:create];
        if (asyncBlock) {
            asyncBlock(success);
        }
    }];
}

// 删除表
- (void)delegateTable:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf checkSQLIsOpen]){return;}
        NSString *zeroTable = [NSString stringWithFormat:@"update sqlite_sequence SET seq = 0 where name ='%@'",NSStringFromClass([tableClass class])];
        NSString *clean = [NSString stringWithFormat:@"delete from %@",NSStringFromClass([tableClass class])];
        [strongSelf.lwxDB executeUpdate:zeroTable] ? NSLog(@"自增id清0成功"):NSLog(@"自增id清0失败");
        [strongSelf.lwxDB executeUpdate:clean] ? NSLog(@"清空表成功"):NSLog(@"清空表失败");
        
        NSString *delete = [NSString stringWithFormat:@"DROP TABLE %@",NSStringFromClass([tableClass class])];
        BOOL success = [strongSelf.lwxDB executeUpdate:delete];
        if (asyncBlock) {
            asyncBlock(success);
        }
    }];
}

// 插入数据
- (void)insertData:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf checkSQLIsOpen]){return;}
        
        NSMutableArray *keyArr = [[NSMutableArray alloc]init];
        NSMutableArray *vlaueArr = [[NSMutableArray alloc]init];
        
        
        Class cycleClass = [tableClass class];
        do {
            unsigned int count;
            objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
            for (unsigned int i=0; i<count; i++){
                const char *propertyName = property_getName(propertyList[i]);
                NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                if ([[tableClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                    if (![[tableClass valueForKey:propertyNameStr] isEqualToString: @""]){
                        [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                        [keyArr addObject:propertyNameStr];
                    }
                }else if([tableClass valueForKey:propertyNameStr]){
                    [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                    [keyArr addObject:propertyNameStr];
                }
            }
            cycleClass = class_getSuperclass(cycleClass);
        } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
        
        if (keyArr.count == 0 || vlaueArr.count == 0 || keyArr.count != vlaueArr.count){
            NSLog(@"%@没有属性/所有属性为全都复制,添加失败",NSStringFromClass([tableClass class]));
            return;
        }
        
        NSString *insertSQL = [NSString stringWithFormat:@"insert into %@(%@) values(%@)",NSStringFromClass([tableClass class]),[strongSelf mergeKey:keyArr],[strongSelf mergeVlaue:vlaueArr]];
        BOOL success = [strongSelf.lwxDB executeUpdate:insertSQL withArgumentsInArray:vlaueArr];
        if (asyncBlock) {
            asyncBlock(success);
        }
    }];
}

// 删除某条数据 key value
- (void)delegateTableData:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf checkSQLIsOpen]){return;}
        
        NSString *delegateStr = [[NSString alloc]init];
        NSMutableArray *keyArr = [[NSMutableArray alloc]init];
        NSMutableArray *vlaueArr = [[NSMutableArray alloc]init];
        
        Class cycleClass = [tableClass class];
        do {
            unsigned int count;
            objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
            for (unsigned int i=0; i<count; i++){
                const char *propertyName = property_getName(propertyList[i]);
                NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                
                if ([[tableClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                    if (![[tableClass valueForKey:propertyNameStr] isEqualToString: @""]){
                        [keyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                        [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                    }
                }else if([tableClass valueForKey:propertyNameStr]){
                    [keyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                    [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                }
            }
            cycleClass = class_getSuperclass(cycleClass);
        } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
        
        if (keyArr.count == 0 || vlaueArr.count == 0){
            NSLog(@"%@没有属性/属性值，删除数据失败",NSStringFromClass([tableClass class]));
            return;
        }
        
        delegateStr = [NSString stringWithFormat:@"delete from %@ where%@",NSStringFromClass([tableClass class]),[keyArr componentsJoinedByString:@" and"]];
        BOOL success =  [strongSelf.lwxDB executeUpdate:delegateStr withArgumentsInArray:vlaueArr];
        if (asyncBlock) {
            asyncBlock(success);
        }
    }];
}

//修改某条数据
- (void)changeData:(id)dataClass modifyDataClass:(id)modifyDataClass asyncBlock:(void(^)(BOOL success))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf checkSQLIsOpen]){return;}
        
        NSString *sqlStr = [[NSString alloc]init];
        NSString *changeDataStr = [[NSString alloc]init];
        NSString *conditionsDataStr = [[NSString alloc]init];
        
        NSMutableArray *conditionsArr = [[NSMutableArray alloc]init];
        NSMutableArray *changeDataKeyArr = [[NSMutableArray alloc]init];
        NSMutableArray *changeDataVlaueArr = [[NSMutableArray alloc]init];
        
        Class cycleClass = [modifyDataClass class];
        do {
            //条件
            unsigned int count;
            objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
            for (unsigned int i=0; i<count; i++){
                const char *propertyName = property_getName(propertyList[i]);
                NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                
                if ([[modifyDataClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                    if (![[modifyDataClass valueForKey:propertyNameStr] isEqualToString: @""]){
                        [conditionsArr addObject:[NSString stringWithFormat:@" %@ = '%@'",propertyNameStr,[modifyDataClass valueForKey:propertyNameStr]]];
                    }
                }else if([modifyDataClass valueForKey:propertyNameStr]){
                    if ([[modifyDataClass valueForKey:propertyNameStr] isKindOfClass:[NSData class]]){
                        [conditionsArr addObject:[NSString stringWithFormat:@" %@ = '%@'",propertyNameStr,[modifyDataClass valueForKey:propertyNameStr]]];
                    }else{
                        [conditionsArr addObject:[NSString stringWithFormat:@" %@ = %@",propertyNameStr,[modifyDataClass valueForKey:propertyNameStr]]];
                    }
                }
            }
            cycleClass = class_getSuperclass(cycleClass);
        } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
        
        
        cycleClass = [dataClass class];
        do {
            //修改
            unsigned int changeDataCount;
            objc_property_t *changeDataPropertyList = class_copyPropertyList(cycleClass, &changeDataCount);
            for (unsigned int i=0; i<changeDataCount; i++){
                const char *propertyName = property_getName(changeDataPropertyList[i]);
                NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                
                if ([[dataClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                    if (![[dataClass valueForKey:propertyNameStr] isEqualToString: @""]){
                        [changeDataKeyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                        [changeDataVlaueArr addObject:[dataClass valueForKey:propertyNameStr]];
                    }
                }else if([dataClass valueForKey:propertyNameStr]){
                    [changeDataKeyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                    [changeDataVlaueArr addObject:[dataClass valueForKey:propertyNameStr]];
                }
            }
            cycleClass = class_getSuperclass(cycleClass);
        } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
        
        
        if (conditionsArr.count == 0 || changeDataKeyArr.count == 0 || changeDataVlaueArr.count == 0){
            NSLog(@"%@没有属性/属性值，修改某条失败",NSStringFromClass([modifyDataClass class]));
            return;
        }
        
        changeDataStr = [conditionsArr componentsJoinedByString:@","];
        conditionsDataStr = [changeDataKeyArr componentsJoinedByString:@" and"];
        sqlStr = [NSString stringWithFormat:@"update %@ set%@ where%@ ",NSStringFromClass([modifyDataClass class]),changeDataStr,conditionsDataStr];
        BOOL success =   [strongSelf.lwxDB executeUpdate:sqlStr withArgumentsInArray:changeDataVlaueArr];
        if (asyncBlock) {
            asyncBlock(success);
        }
    }];
}

//查询表内所有数据
- (void)queryTable:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![self checkSQLIsOpen]){
            if (asyncBlock) {
                asyncBlock(nil);
            }
        }else{
            NSMutableArray *classPropertyArray = [[NSMutableArray alloc]init];
            NSMutableArray *classProNameArray = [[NSMutableArray alloc]init];
            NSMutableArray *returnArr = [[NSMutableArray alloc]init];
            
            Class cycleClass = [tableClass class];
            do {
                unsigned int count;
                objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
                for (unsigned int i=0; i<count; i++){
                    const char *propertyName = property_getName(propertyList[i]);
                    NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                    if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                    NSString *getPropertyNameString = [NSString stringWithCString:property_getAttributes(propertyList[i]) encoding:NSUTF8StringEncoding];
                    [classPropertyArray addObject:propertyNameStr];
                    [classProNameArray addObject:getPropertyNameString];
                }
                cycleClass = class_getSuperclass(cycleClass);
            } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
            
            FMResultSet* set = [strongSelf.lwxDB executeQuery:[NSString stringWithFormat:@"select * from %@",NSStringFromClass([tableClass class])]];
            while ([set next]){
                Class newTableClass = NSClassFromString(NSStringFromClass([tableClass class]));
                id newClass = [[newTableClass alloc]init];
                
                for (int i = 0; i < classPropertyArray.count; i++){
                    if ([classProNameArray[i] rangeOfString:@"NSString"].location != NSNotFound){
                        [newClass setValue:[set stringForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSDate"].location != NSNotFound){
                        [newClass setValue:[set dateForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSNumber"].location != NSNotFound){
                        [newClass setValue:@([set intForColumn:classPropertyArray[i]]) forKey:classPropertyArray[i]];
                    }
                }
                [returnArr addObject:newClass];
            }
            if (asyncBlock) {
                asyncBlock(returnArr);
            }
        }
    }];
}

//条件查找
- (void)findOfConditions:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![self checkSQLIsOpen]){
            if (asyncBlock) {
                asyncBlock(nil);
            }
        }else{
            NSMutableArray *classPropertyArray = [[NSMutableArray alloc]init];
            NSMutableArray *classProNameArray = [[NSMutableArray alloc]init];
            NSMutableArray *returnArr = [[NSMutableArray alloc]init];
            NSMutableArray *keyArr = [[NSMutableArray alloc]init];
            NSMutableArray *vlaueArr = [[NSMutableArray alloc]init];
            
            NSString *sqlStr = [[NSString alloc]init];
            
            Class cycleClass = [tableClass class];
            do {
                unsigned int count;
                objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
                for (unsigned int i=0; i<count; i++){
                    const char *propertyName = property_getName(propertyList[i]);
                    NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                    if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                    NSString *getPropertyNameString = [NSString stringWithCString:property_getAttributes(propertyList[i]) encoding:NSUTF8StringEncoding];
                    [classPropertyArray addObject:propertyNameStr];
                    [classProNameArray addObject:getPropertyNameString];
                    
                    if ([[tableClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                        if (![[tableClass valueForKey:propertyNameStr] isEqualToString: @""]){
                            [keyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                            [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                        }
                    }else if([tableClass valueForKey:propertyNameStr]){
                        [keyArr addObject:[NSString stringWithFormat:@" %@ = ?",propertyNameStr]];
                        [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                    }
                }
                cycleClass = class_getSuperclass(cycleClass);
            } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
            
            if (keyArr.count == 0 || vlaueArr.count == 0){
                sqlStr = [NSString stringWithFormat:@"select * from %@",NSStringFromClass([tableClass class])];
            }else{
                sqlStr = [NSString stringWithFormat:@"select * from %@ where%@",NSStringFromClass([tableClass class]),[keyArr componentsJoinedByString:@" and"]];
            }
            
            FMResultSet* set = [strongSelf.lwxDB executeQuery:sqlStr withArgumentsInArray:vlaueArr];
            while ([set next]){
                Class newTableClass = NSClassFromString(NSStringFromClass([tableClass class]));
                id newClass = [[newTableClass alloc]init];
                
                for (int i = 0; i < classPropertyArray.count; i++){
                    if ([classProNameArray[i] rangeOfString:@"NSString"].location != NSNotFound){
                        [newClass setValue:[set stringForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSDate"].location != NSNotFound){
                        [newClass setValue:[set dateForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSNumber"].location != NSNotFound){
                        [newClass setValue:@([set intForColumn:classPropertyArray[i]]) forKey:classPropertyArray[i]];
                    }
                }
                [returnArr addObject:newClass];
            }
            if (asyncBlock) {
                asyncBlock(returnArr);
            }
        }
    }];
}

- (void)findOfLikeConditions:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock{
    __weak typeof(self) weakSelf = self;
    [_queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![self checkSQLIsOpen]){
            if (asyncBlock) {
                asyncBlock(nil);
            }
        }else{
            NSMutableArray *classPropertyArray = [[NSMutableArray alloc]init];
            NSMutableArray *classProNameArray = [[NSMutableArray alloc]init];
            NSMutableArray *returnArr = [[NSMutableArray alloc]init];
            NSMutableArray *keyArr = [[NSMutableArray alloc]init];
            NSMutableArray *vlaueArr = [[NSMutableArray alloc]init];
            
            NSString *sqlStr = [[NSString alloc]init];
            
            Class cycleClass = [tableClass class];
            do {
                unsigned int count;
                objc_property_t *propertyList = class_copyPropertyList(cycleClass, &count);
                for (unsigned int i=0; i<count; i++){
                    const char *propertyName = property_getName(propertyList[i]);
                    NSString *propertyNameStr = [NSString stringWithFormat:@"%@",[NSString stringWithUTF8String:propertyName]];
                    if (![LwxFMDB isCustomProperty:propertyNameStr]) continue;
                    NSString *getPropertyNameString = [NSString stringWithCString:property_getAttributes(propertyList[i]) encoding:NSUTF8StringEncoding];
                    [classPropertyArray addObject:propertyNameStr];
                    [classProNameArray addObject:getPropertyNameString];
                    if ([[tableClass valueForKey:propertyNameStr] isKindOfClass:[NSString class]]){
                        if (![[tableClass valueForKey:propertyNameStr] isEqualToString: @""]){
                            [keyArr addObject:[NSString stringWithFormat:@" %@ LIKE '%%%@%%'",propertyNameStr, [tableClass valueForKey:propertyNameStr]]];
                            [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                        }
                    }else if([tableClass valueForKey:propertyNameStr]){
                        [keyArr addObject:[NSString stringWithFormat:@" %@ LIKE '%%%@%%'",propertyNameStr, [tableClass valueForKey:propertyNameStr]]];
                        [vlaueArr addObject:[tableClass valueForKey:propertyNameStr]];
                    }
                }
                cycleClass = class_getSuperclass(cycleClass);
            } while (![NSStringFromClass(cycleClass) isEqualToString:NSStringFromClass([NSObject class])] && cycleClass != nil);
            
            if (keyArr.count == 0 || vlaueArr.count == 0){
                sqlStr = [NSString stringWithFormat:@"select * from %@",NSStringFromClass([tableClass class])];
            }else{
                sqlStr = [NSString stringWithFormat:@"select * from %@ where%@",NSStringFromClass([tableClass class]),[keyArr componentsJoinedByString:@" or"]];
            }
            
            FMResultSet* set = [strongSelf.lwxDB executeQuery:sqlStr withArgumentsInArray:vlaueArr];
            while ([set next]){
                Class newTableClass = NSClassFromString(NSStringFromClass([tableClass class]));
                id newClass = [[newTableClass alloc]init];
                
                for (int i = 0; i < classPropertyArray.count; i++){
                    if ([classProNameArray[i] rangeOfString:@"NSString"].location != NSNotFound){
                        [newClass setValue:[set stringForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSDate"].location != NSNotFound){
                        [newClass setValue:[set dateForColumn:classPropertyArray[i]] forKey:classPropertyArray[i]];
                    }else if ([classProNameArray[i] rangeOfString:@"NSNumber"].location != NSNotFound){
                        [newClass setValue:@([set intForColumn:classPropertyArray[i]]) forKey:classPropertyArray[i]];
                    }
                }
                [returnArr addObject:newClass];
            }
            if (asyncBlock) {
                asyncBlock(returnArr);
            }
        }
    }];
}


@end


