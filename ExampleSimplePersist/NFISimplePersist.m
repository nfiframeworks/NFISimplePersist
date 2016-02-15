//
//  NFISimplePersist.m
//  ExampleSimplePersist
//
//  Created by José Carlos on 15/2/16.
//  Copyright © 2016 José Carlos. All rights reserved.
//

#import "NFISimplePersistObject.h"
#import "NFISimplePersist.h"
#import <sqlite3.h>

NSString * const kDBName = @"NFISimplePersist.db";
NSString * const kCreatePersistTable = @"CREATE TABLE persistedObjects (key TEXT PRIMARY KEY, object BLOB, class TEXT NOT NULL) ";
NSString * const kTableExist = @"SELECT name FROM sqlite_master WHERE type='table' AND name='persistedObjects'";
NSString * const kInsert = @"INSERT INTO persistedObjects VALUES(?, ?, ?);";
NSString * const kCountFields = @"SELECT COUNT(*) FROM persistedObjects";

NSString * const kLoadFirst = @"SELECT * FROM persistedObjects LIMIT 1";
NSString * const kLoadAll = @"SELECT * FROM persistedObjects";
NSString * const kLoadWithKey = @"SELECT * FROM persistedObjects WHERE key like '%@'";

NSString * const kDeleteFirst = @"DELETE FROM persistedObjects WHERE key = (SELECT key FROM persistedObjects LIMIT 1)";

NSString * const kClass = @"class";
NSString * const kObject = @"object";
NSString * const kKey = @"key";

@interface NFISimplePersist ()

@property (nonatomic) sqlite3 *database;
@property (nonatomic, copy) NSString *databasePath;

@end

@implementation NFISimplePersist

#pragma mark - Private Methods.
#pragma mark -
#pragma mark - DB methods.
/**
 *  Load the DB
 */
- (void)loadDB {
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = [dirPaths objectAtIndex:0];
    _databasePath = [[NSString alloc] initWithString: [docsDir stringByAppendingPathComponent: kDBName]];
    NSFileManager *filemgr = [NSFileManager defaultManager];
    if ([filemgr fileExistsAtPath: _databasePath ] == NO) {
        const char *dbpath = [_databasePath UTF8String];
        if (sqlite3_open(dbpath, &_database) == SQLITE_OK) {
            char *errMsg;
            if (sqlite3_exec(_database, [kCreatePersistTable UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
                NSAssert1(0, @"Failed to create table '%s'", sqlite3_errmsg(_database));
            }
            sqlite3_close(_database);
        } else {
             NSLog(@"Failed to open/create database");
        }
    }
}

- (id)objectFromDictionary:(NSDictionary *)dictionary {
    if (dictionary) {
        Class objectClass = NSClassFromString(dictionary[kClass]);
        id object = nil;
        if ([[objectClass alloc] respondsToSelector:@selector(initWithDictionary:)]) {
            object = [[objectClass alloc] initWithDictionary:dictionary[kObject]];
            return object;
        } else {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"To persist this object, you must implement NFISimplePersistObject protocol and add all required methods."]
                                         userInfo:nil];
        }
    }
    return nil;
}

#pragma mark - Public Methods.
#pragma mark -
#pragma mark - Instance.

/** Unique shared instance for NFISimplePersist.
 */
+ (instancetype)standarSimplePersist {
    static NFISimplePersist *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[NFISimplePersist alloc] init];
        [_sharedInstance loadDB];
    });
    return _sharedInstance;

}

#pragma mark - Persist method

/**
 *  Persist the object in the data base
 */
- (void)saveObject:(id)object withKey:(NSString *)key {
    if (sqlite3_open([_databasePath UTF8String], &_database) == SQLITE_OK) {
        if ([object respondsToSelector:@selector(saveAsDictionary)]) {
            NSDictionary *dictToSave = [[NSDictionary alloc] initWithObjects:@[NSStringFromClass([object class]), [object saveAsDictionary], key]
                                                                     forKeys:@[kClass, kObject, kKey]];
            NSString *class = dictToSave[kClass];
            NSDictionary *object = dictToSave[kObject];
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
            
            sqlite3_stmt *updateStmt = nil;
            if(sqlite3_prepare_v2(_database, [kInsert UTF8String], -1, &updateStmt, NULL) != SQLITE_OK)  {
                NSAssert1(0, @"Error while creating update statement. '%s'", sqlite3_errmsg(_database));
            } else {
                sqlite3_bind_text(updateStmt, 1, [key UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_blob(updateStmt, 2, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                sqlite3_bind_text(updateStmt, 3, [class UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_step(updateStmt);
            }
            sqlite3_reset(updateStmt);
            sqlite3_finalize(updateStmt);
        } else {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"To schedule request of this object, you must implement GMService protocol and add all required methods."]
                                         userInfo:nil];
        }
    }
    sqlite3_close(_database);
}

#pragma mark - Load methods

/**
 *  Load all objects in table
 */
- (NSArray *)loadAllObjects {
    NSMutableArray *objects = [[NSMutableArray alloc] init];
    sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(_database, [kLoadAll UTF8String], -1, &statement, nil)
        == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            char *keyDB = (char *) sqlite3_column_text(statement, 0);
            const void *ptr = sqlite3_column_blob(statement, 1);
            int size = sqlite3_column_bytes(statement, 1);
            char *classDB = (char *) sqlite3_column_text(statement, 2);
            
            NSString *class = [[NSString alloc] initWithUTF8String:classDB];
            NSString *key = [[NSString alloc] initWithUTF8String:keyDB];
            NSData *data = [[NSData alloc] initWithBytes:ptr length:size];
            
            NSMutableDictionary *object = [[NSMutableDictionary alloc] init];
            
            NSDictionary *dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            [object setObject:dictionary forKey:kObject];
            [object setObject:key forKey:kKey];
            [object setObject:class forKey:kClass];
            
            [objects addObject:[self objectFromDictionary:object]];
        }
        sqlite3_finalize(statement);
    } else {
        NSAssert1(0, @"Error while creating database. '%s'", sqlite3_errmsg(_database));
    }
    return objects;
}

/**
 *  Load the first object in the database. Return nil if the table is empty
 */
- (id)loadFirstObject {
    sqlite3_stmt *statement;
    if (sqlite3_open([_databasePath UTF8String], &_database) == SQLITE_OK) {
        if (sqlite3_prepare_v2(_database, [kLoadFirst UTF8String], -1, &statement, nil) == SQLITE_OK) {
            while (sqlite3_step(statement) == SQLITE_ROW) {
                char *keyDB = (char *) sqlite3_column_text(statement, 0);
                const void *ptr = sqlite3_column_blob(statement, 1);
                int size = sqlite3_column_bytes(statement, 1);
                char *classDB = (char *) sqlite3_column_text(statement, 2);
                
                NSString *class = [[NSString alloc] initWithUTF8String:classDB];
                NSString *key = [[NSString alloc] initWithUTF8String:keyDB];
                NSData *data = [[NSData alloc] initWithBytes:ptr length:size];
                
                NSMutableDictionary *object = [[NSMutableDictionary alloc] init];
                
                NSDictionary *dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                [object setObject:dictionary forKey:kObject];
                [object setObject:key forKey:kKey];
                [object setObject:class forKey:kClass];
                
                return [self objectFromDictionary:object];
            }
            sqlite3_finalize(statement);
        } else {
            NSAssert1(0, @"Error while creating database. '%s'", sqlite3_errmsg(_database));
        }
    }
    return nil;
}

/**
 *  Load the object with the given key in the database. Return nil if the table is empty
 */
- (id)loadObjectWithKey:(NSString *)key {
    sqlite3_stmt *statement;
    if (sqlite3_prepare_v2(_database, [[NSString stringWithFormat:kLoadWithKey,key] UTF8String], -1, &statement, nil)
        == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            char *keyDB = (char *) sqlite3_column_text(statement, 0);
            const void *ptr = sqlite3_column_blob(statement, 1);
            int size = sqlite3_column_bytes(statement, 1);
            char *classDB = (char *) sqlite3_column_text(statement, 2);
            
            NSString *class = [[NSString alloc] initWithUTF8String:classDB];
            NSString *key = [[NSString alloc] initWithUTF8String:keyDB];
            NSData *data = [[NSData alloc] initWithBytes:ptr length:size];
            
            NSMutableDictionary *object = [[NSMutableDictionary alloc] init];
            
            NSDictionary *dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            [object setObject:dictionary forKey:kObject];
            [object setObject:key forKey:kKey];
            [object setObject:class forKey:kClass];
            
            return [self objectFromDictionary:object];
        }
        sqlite3_finalize(statement);
    }
    return nil;
}


#pragma mark - Remove methods
/**
 *  Remove first object in the table. Return a BOOL with the result
 */
- (BOOL)removeFirstObject {
    return NO;
}

/**
 *  Remove object with the given key in the table. Return a BOOL with the result
 */
- (BOOL)removeObjectWithKey:(NSString *)key {
    return NO;
}

/**
 *  Return YES if the table is empty
 */
- (BOOL)isEmpty {
    return NO;
}

@end
