//
//  LwxFMDB.h
//  LwxFMDBDemo
//
//  Created by Lwx on 16/10/24.
//  Copyright © 2016年 Lwx. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
 *   ！---- 使用前必读 ----！
 *
 * 1.介绍: 基于FMDB的一个数据存储工具，对FMDB进行了封装。
 *
 * 2.操作: 所有操作都需要通过单例来进行。
 *        操作之前先调用openDB（打开数据库）,操作结束调用close(关闭数据库)。
 *
 * 3.注意  数据库中所有表名根据传进来的类名进行存储，取值的时候也是通过对应的类来进行取值。
 *        每个表中所对应的列名，是根据表名所对应类中的属性名来设定的。所以请在创建表之前把对应类中的属性定义好，防止出现错误。
 *        如果需要在表中添加新列 请删除原来的表，在对应的类中添加属性，重新创建！防止出现错误。
 *        仅支持 NSNumber,NSString,NSDate 类型的存取
 *        建议属性在赋值的时候如果某个属性为nil 请赋值为nil。（如NSNumber，在未赋值的情况下会默认为0。防止出现意外错误）
 *
 * 4.所有查询结果回调均不在主线程。    如果需要操作主线程，请在回调中自行加入主线程代码
 *
 *
 */
@interface LwxFMDB : NSObject

//获取单例
+ (instancetype)intance;

//根据key创建数据库
+ (void)initIntance:(NSString *)key;

// 打开数据库，如果不存在则创建并且打开
- (void)openDB:(void(^)(BOOL success))asyncBlock;

//关闭数据库
- (void)closeDB:(void(^)(BOOL success))asyncBlock;

// 创建表
- (void)createATable:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock;

// 删除表
- (void)delegateTable:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock;

// 插入数据
- (void)insertData:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock;

// 删除某条数据 key value
- (void)delegateTableData:(id)tableClass asyncBlock:(void(^)(BOOL success))asyncBlock;


/// 修改某条数据
/// @param dataClass 条件
/// @param modifyDataClass 修改的数据
/// @param asyncBlock 回调
- (void)changeData:(id)dataClass modifyDataClass:(id)modifyDataClass asyncBlock:(void(^)(BOOL success))asyncBlock;

//查询表内所有数据，如果未查到返回NSArray不为nil（可被条件查找代替） 
- (void)queryTable:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock;

//条件查找 tableClass属性全为nil时返回表中所有数据，如果未查到返回NSArray不为nil
- (void)findOfConditions:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock;

//条件查找 tableClass属性全为nil时返回表中所有数据，如果未查到返回NSArray不为nil
- (void)findOfLikeConditions:(id)tableClass asyncBlock:(void(^)(NSArray *array))asyncBlock;

@end
