// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import ZMTransport;
@import ZMCDataModel;

#import "ObjectTranscoderTests.h"
#import "ZMConnectionTranscoder+Internal.h"
#import "ZMContextChangeTracker.h"
#import "ZMUpstreamModifiedObjectSync.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import "ZMSimpleListRequestPaginator.h"
#import "ZMDownstreamObjectSync.h"

@interface ZMConnectionTranscoderTest : ObjectTranscoderTests

@property (nonatomic) ZMConnectionTranscoder *sut;
@property (nonatomic) ZMConnection *connection;
@property (nonatomic) ZMUser *user;

- (NSMutableDictionary *)connectionPayloadForConversationID:(NSUUID *)conversationID fromID:(NSUUID *)fromID toID:(NSUUID *)toID status:(NSString *)status;

@end



@implementation ZMConnectionTranscoderTest

- (void)setUp
{
    [super setUp];
    self.sut = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)createUserAndConnection;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        self.user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.user.remoteIdentifier = [NSUUID createUUID];
        
        self.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        self.connection.to = self.user;
    }];
}

- (NSMutableDictionary *)connectionPayloadForConversationID:(NSUUID *)conversationID fromID:(NSUUID *)fromID toID:(NSUUID *)toID status:(NSString *)status;
{
    return [@{@"status": status,
             @"conversation": conversationID.transportString,
             @"to": toID.transportString,
             @"from": fromID.transportString,
             @"last_update": [NSDate dateWithTimeIntervalSince1970:120000].transportString,
             @"message": @"Hello!"
             } mutableCopy];
}

- (void)testThatItProcessesPaginatedRequestsBeforeUpstream;
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 4u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMSimpleListRequestPaginator.class]);
    XCTAssertTrue([generators[1] isKindOfClass:ZMDownstreamObjectSync.class]);
    XCTAssertTrue([generators[2] isKindOfClass:ZMUpstreamInsertedObjectSync.class]);
    XCTAssertTrue([generators.lastObject isKindOfClass:ZMUpstreamModifiedObjectSync.class]);
}


- (void)testThatItDoesNotProcessDownstreamRequestsDuringSlowSync;
{
    // given
    [self.sut setNeedsSlowSync];
    XCTAssertFalse(self.sut.isSlowSyncDone);

    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 3u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMSimpleListRequestPaginator.class]);
    XCTAssertTrue([generators[1] isKindOfClass:ZMUpstreamInsertedObjectSync.class]);
    XCTAssertTrue([generators.lastObject isKindOfClass:ZMUpstreamModifiedObjectSync.class]);
}


- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 3u);
    NSArray *classes = [trackers mapWithBlock:^id(id<NSObject> obj) {
        return obj.class;
    }];
    NSArray *expected = @[ZMDownstreamObjectSync.class, ZMUpstreamInsertedObjectSync.class, ZMUpstreamModifiedObjectSync.class];
    XCTAssertEqualObjects(classes, expected);
}

- (void)testThatIsSlowSyncDoneIsTrueAtCreation
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatWhenSlowSyncIsNotDoneRequestIsGenerated
{
    // given
    [self.sut setNeedsSlowSync];
    XCTAssertFalse([self.sut isSlowSyncDone]);
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    NSString *expectedPath = [NSString stringWithFormat:@"/connections?size=%u",(unsigned int)ZMConnectionTranscoderPageSize];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodGET);
}

- (void)testThatASuccessfulResponseWithHasMore_NO_SetsIsSlowSyncDone
{
    // given
    NSDictionary *payload = [self validPayloadWithHasMore:NO];
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil]];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self.sut isSlowSyncDone]);
}

- (void)testThatASuccessfulResponseWithHasMore_YES_DoesNotSetIsSlowSyncDone
{
    // given
    NSDictionary *payload = [self validPayloadWithHasMore:YES];
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil]];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertFalse([self.sut isSlowSyncDone]);
}

- (void)testThatAfterASuccessfulSlowSyncNoRequestIsGenerated
{
    // given
    NSDictionary *payload = [self validPayloadWithHasMore:NO];
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // We need to complete the request to switch hard sync to done
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
    XCTAssertTrue([self.sut isSlowSyncDone]);
}

- (void)testThatATemporaryFailedRequestDoesNotSetIsSlowSyncDone
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPstatus:500 transportSessionError:nil]];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertFalse([self.sut isSlowSyncDone]);
}


- (void)testThatWeCanSendAnotherRequestAfterARequestTemporarilyFailed
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPstatus:500 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request2);
}

- (void)testThatWhileSlowSyncIsInProgressNoRequestIsGenerated
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest]; // this should mark hard sync as in progress
    
    // when
    request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
    XCTAssertFalse([self.sut isSlowSyncDone]);
}


- (void)testThatAfterASlowSyncIsDoneANewSlowSyncCanBeStarted
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    NSDictionary *payload = [self validPayloadWithHasMore:NO];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.sut setNeedsSlowSync];

    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];

    // then
    XCTAssertNotNil(request2);
}


- (void)testThatWeCanGetANewRequestAfterAFailedSlowSyncRequest
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];

    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPstatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];

    // then
    XCTAssertNotNil(request2);
}


- (void)testThatTheHardSyncIsMarkedAsDoneAfterAFailedSlowSyncRequest
{
    // given
    [self.sut setNeedsSlowSync];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPstatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatConnectionsAreParsedFromASuccessfulResponse
{
    // given
    [self.sut setNeedsSlowSync];
    NSDictionary *payload = [self validPayloadWithHasMore:NO];


    NSMutableDictionary *connectionByToField = [@{} mutableCopy];
    for(NSDictionary *connection in [payload optionalArrayForKey:@"connections"]) {
        NSString *to = connection[@"to"];
        connectionByToField[ [to UUID] ] = connection;
    }
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil]];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self.sut isSlowSyncDone]);

    [self.syncMOC performBlockAndWait:^{
        __block NSUInteger index = 0;
        [ZMConnection enumerateObjectsInContext:self.syncMOC withBlock:^(ZMManagedObject *mo, BOOL *stop ZM_UNUSED) {
            ZMConnection *connection = (ZMConnection *) mo;
            [self checkThatConnection:connection matchesPayload:connectionByToField[connection.to.remoteIdentifier] failure:NewFailureRecorder()];
            XCTAssertTrue(connection.existsOnBackend,
                          @"Needs to be set. Otherwise we think this has been inserted locally.");
            ++index;
        }];
        
        XCTAssertEqual(2u, index);
    }];
    
}

- (void)testThatItProcessEventOfTypeZMUpdateEventConnectionUpdate
{
    NSDictionary *samplePayload = [self connectionPayloadForConversationID:NSUUID.createUUID fromID:NSUUID.createUUID toID:NSUUID.createUUID status:@"accepted"];
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSDictionary *payload = @{
                                  @"type" : @"user.connection",
                                  @"connection" : samplePayload
                                  };
        ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventUserConnection)] type];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        __block ZMConnection *connection = nil;
        [ZMConnection enumerateObjectsInContext:self.syncMOC withBlock:^(ZMManagedObject *obj, BOOL *stop) {
            XCTAssertNil(connection, @"Already found one");
            connection = (ZMConnection *) obj;
            NOT_USED(stop);
        }];
        
        XCTAssertNotNil(connection);
        [self checkThatConnection:connection matchesPayload:samplePayload failure:NewFailureRecorder()];
        XCTAssertTrue(connection.existsOnBackend,
                      @"Needs to be set. Otherwise we think this has been inserted locally.");
    }];
}

- (void)testThatItDoesNotCrashWithUpdateEventWithInvalidUserData
{
    // given
    NSDictionary *payload = @{
                              @"type" : @"user.connection",
                              @"connection" : @"baz"
                              };
    
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventUserConnection)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItDoesNotProcessUpdateEventWrongType
{
    NSDictionary *samplePayload = [self connectionPayloadForConversationID:NSUUID.createUUID fromID:NSUUID.createUUID toID:NSUUID.createUUID status:@"accepted"];
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSDictionary *payload = @{
                                  @"type" : @"fooz",
                                  @"connection" : samplePayload
                                  };
        ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventUnknown)] type];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        __block ZMConnection *connection = nil;
        [ZMConnection enumerateObjectsInContext:self.syncMOC withBlock:^(ZMManagedObject *obj, BOOL *stop) {
            connection = (ZMConnection *) obj;
            NOT_USED(stop);
        }];
        XCTAssertNil(connection);
    }];
}

- (void)testThatUsersAreMarkedAsIncompleteWhenTheyBecomeConnected
{
    // given
    NSDictionary *samplePayload = [self connectionPayloadForConversationID:NSUUID.createUUID fromID:NSUUID.createUUID toID:NSUUID.createUUID status:@"accepted"];
    [self.syncMOC performGroupedBlockAndWait:^{
        NSMutableDictionary *initData =  [samplePayload mutableCopy];
        initData[@"status"] = @"pending";
        
        [ZMConnection connectionFromTransportData:initData managedObjectContext:self.syncMOC];
        ZMUser *user = [ZMUser userWithRemoteID:[initData[@"to"] UUID] createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user);
        user.needsToBeUpdatedFromBackend = NO;
        
        NSDictionary *payload = @{
                                  @"type" : @"user.connection",
                                  @"connection" : samplePayload
                                  };
        ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventUserConnection)] type];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(user.needsToBeUpdatedFromBackend);
    }];
}


- (NSDictionary *)validPayloadWithHasMore:(BOOL)hasMore
{
    NSDictionary *payload =     // expected JSON response
    @{@"connections": @[
              [self connectionPayloadForConversationID:[NSUUID createUUID] fromID:[NSUUID createUUID] toID:[NSUUID createUUID] status:@"accepted"],
              [self connectionPayloadForConversationID:[NSUUID createUUID] fromID:[NSUUID createUUID] toID:[NSUUID createUUID] status:@"accepted"],
              ],
      @"has_more": @(hasMore)
      };
    return payload;
}


- (void)checkThatConnection:(ZMConnection *)connection matchesPayload:(NSDictionary *)payload failure:(ZMTFailureRecorder *)failure
{
    FHAssertEqualObjects(failure,connection.lastUpdateDateInGMT, [NSDate dateWithTransportString:payload[@"last_update"]]);
    FHAssertEqual(failure,connection.status, [ZMConnection statusFromString:payload[@"status"]]);
    NSUUID *to = [payload[@"to"] UUID];
    FHAssertEqualObjects(failure,connection.to.remoteIdentifier, to);
}

@end



@implementation ZMConnectionTranscoderTest (Upstream)

- (void)testThatInsertedObjectsMatchInsertPredicate;
{
    NSPredicate *predicate = [ZMConnection predicateForObjectsThatNeedToBeInsertedUpstream];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    
    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = NO;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = nil;
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = NO;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = YES;
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusSent;
    connection.message = nil;
    connection.existsOnBackend = NO;
    XCTAssertTrue([predicate evaluateWithObject:connection]);
    

    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusSent;
    connection.message = @"Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";
    connection.existsOnBackend = NO;
    XCTAssertTrue([predicate evaluateWithObject:connection]);
}

- (void)testThatUpdatedObjectsMatchUpdatePredicate;
{
    NSPredicate *predicate = [ZMConnection predicateForObjectsThatNeedToBeUpdatedUpstream];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    
    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet set]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    ///
    
    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusInvalid;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = NO;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = nil;
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);

    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusPending;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusSent;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertFalse([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusBlocked;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertTrue([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusIgnored;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertTrue([predicate evaluateWithObject:connection]);
    
    connection.to = user;
    user.remoteIdentifier = [NSUUID createUUID];
    connection.status = ZMConnectionStatusAccepted;
    connection.existsOnBackend = YES;
    [connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
    XCTAssertTrue([predicate evaluateWithObject:connection]);
}

- (void)testThatItGeneratesAnUpdateRequestForAcceptedConnections
{
    [self checkThatItGeneratesAnUpdateRequestForStatus:ZMConnectionStatusAccepted payloadString:@"accepted"];
}

- (void)testThatItGeneratesAnUpdateRequestForBlockedConnections
{
    [self checkThatItGeneratesAnUpdateRequestForStatus:ZMConnectionStatusBlocked payloadString:@"blocked"];
}

- (void)testThatItGeneratesAnUpdateRequestForIgnoredConnections
{
    [self checkThatItGeneratesAnUpdateRequestForStatus:ZMConnectionStatusIgnored payloadString:@"ignored"];
}

- (void)markUserAndConversationAsUpdatedForConnection:(ZMConnection *)connection;
{
    ZMUser *user = connection.to;
    if (user != nil) {
        user.needsToBeUpdatedFromBackend = NO;
    }
    
    ZMConversation *conversation = connection.conversation;
    if (conversation != nil) {
        conversation.needsToBeUpdatedFromBackend = NO;
    }
}

- (void)checkThatItGeneratesAnUpdateRequestForStatus:(ZMConnectionStatus)newStatus payloadString:(NSString *)expectedPayloadString;
{
    // given
    __block NSUUID *userID;
    [self createUserAndConnection];
    [self.syncMOC performGroupedBlockAndWait:^{
        userID = self.user.remoteIdentifier;
        self.connection.status = newStatus;
        self.connection.existsOnBackend = YES;
        [self.connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
        [self markUserAndConversationAsUpdatedForConnection:self.connection];
        
        XCTAssert([self.syncMOC saveOrRollback]);
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:self.connection]];
        }
    }];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
        // then
        XCTAssertNotNil(request);
        NSString *expectedPath = [NSString pathWithComponents:@[@"/connections", userID.transportString]];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        NSDictionary *expectedPayload = @{@"status": expectedPayloadString};
        XCTAssertEqualObjects(request.payload, expectedPayload);
    }];
}

- (void)testThatItParsesTheServerResponseWhenUpdatingAConnection;
{
    // given
    __block NSUUID *userID;
    [self createUserAndConnection];
    [self.syncMOC performGroupedBlockAndWait:^{
        userID = self.user.remoteIdentifier;
        self.connection.status = ZMConnectionStatusAccepted;
        self.connection.existsOnBackend = YES;
        [self.connection setLocallyModifiedKeys:[NSSet setWithObject:@"status"]];
        [self markUserAndConversationAsUpdatedForConnection:self.connection];
        
        XCTAssert([self.syncMOC saveOrRollback]);
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:self.connection]];
        }
    }];
    
    NSUUID *conversationID = [NSUUID createUUID];
    NSDate *update = [NSDate dateWithTimeIntervalSinceNow:-3];
    NSString *newMessage = @"Ut enim ad minima veniam.";
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        NSMutableDictionary *payload = [self connectionPayloadForConversationID:conversationID fromID:selfUser.remoteIdentifier toID:self.user.remoteIdentifier status:@"accepted"];
        payload[@"message"] = newMessage;
        payload[@"last_update"] = update.transportString;
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:payload HTTPstatus:200 transportSessionError:nil headers:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(self.connection.status, ZMConnectionStatusAccepted);
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(self.connection.conversation);
        XCTAssertEqual(self.connection.conversation, conversation);
        XCTAssertEqual(self.connection.to, self.user);
        XCTAssertEqualWithAccuracy(self.connection.lastUpdateDateInGMT.timeIntervalSinceReferenceDate, update.timeIntervalSinceReferenceDate, 0.1);
        XCTAssertEqualObjects(self.connection.message, newMessage);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNil(request, @"Done updating");
    }];
}

- (void)testThatItSendsNewConnectionsToTheBackend;
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    selfUser.remoteIdentifier = [NSUUID createUUID];
    selfUser.name = @"Neal Stephenson";
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"John";
    user.remoteIdentifier = [NSUUID createUUID];
    NSUUID *userID = user.remoteIdentifier;
    XCTAssert([self.uiMOC saveOrRollback]);
    NSString *messageText = @"Aenean non sapien massa.";
    
    // when
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    [self markUserAndConversationAsUpdatedForConnection:connection];
    connection.message = messageText;
    XCTAssert([self.uiMOC saveOrRollback]);
    NSManagedObjectID *moid = connection.objectID;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:moid];
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConnection]];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        
        NSString *expectedPath = [NSString pathWithComponents:@[@"/connections"]];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPOST);
        NSDictionary *expectedPayload = @{@"user": userID.transportString,
                                          @"name": @"Neal Stephenson",
                                          @"message": messageText};
        AssertEqualDictionaries((id) request.payload, expectedPayload);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSetsExistsOnBackendWhenItReceivesTheServer201ResponseForAnInsert;
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    selfUser.remoteIdentifier = [NSUUID createUUID];
    selfUser.name = @"Neal Stephenson";
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"John";
    user.remoteIdentifier = [NSUUID createUUID];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSString *messageText = @"Aenean non sapien massa.";
    
    // when
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.message = messageText;
    [self markUserAndConversationAsUpdatedForConnection:connection];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSManagedObjectID *moid = connection.objectID;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:moid];
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConnection]];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        
        NSMutableDictionary *payload = [self connectionPayloadForConversationID:[NSUUID createUUID] fromID:selfUser.remoteIdentifier toID:user.remoteIdentifier status:@"accepted"];

        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:payload HTTPstatus:201 transportSessionError:nil headers:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:moid];
        XCTAssertTrue(syncConnection.existsOnBackend);
        XCTAssertTrue(syncConnection.needsToBeUpdatedFromBackend);
    }];
}

- (void)testThatItUpdatesAConnectionWithTheResponseOfAnUpdateRequest;
{
    // given
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        XCTAssert([self.uiMOC saveOrRollback]);
        
        ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
        connection.message = @"Foo";

        [self markUserAndConversationAsUpdatedForConnection:connection];
        XCTAssert([self.uiMOC saveOrRollback]);
        
        NSMutableDictionary *payload = [self connectionPayloadForConversationID:[NSUUID createUUID] fromID:selfUser.remoteIdentifier toID:user.remoteIdentifier status:@"accepted"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // when
        [(id<ZMUpstreamTranscoder>) self.sut updateInsertedObject:connection request:request response:response];
    
        // then
        XCTAssertEqualObjects(connection.message, payload[@"message"]);
        XCTAssertEqualObjects(connection.lastUpdateDate.transportString, payload[@"last_update"]);
        XCTAssertEqualObjects(connection.conversation.remoteIdentifier.transportString, payload[@"conversation"]);
        XCTAssertTrue(connection.conversation.needsToBeUpdatedFromBackend);
        
    }];
}


- (void)testThatItSetsExistsOnBackendWhenItReceivesTheServer200ResponseForAnInsert;
{
    // 200 means -> The connection (already) exists. We need to refetch it.
    
    // given
    NSUUID *selfUserID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        selfUser.name = @"Neal Stephenson";
        selfUser.remoteIdentifier = selfUserID;
    }];
    
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"John";
    user.remoteIdentifier = [NSUUID createUUID];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSString *messageText = @"Aenean non sapien massa.";
    
    // when
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.message = messageText;
    [self markUserAndConversationAsUpdatedForConnection:connection];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSManagedObjectID *moid = connection.objectID;
    
    NSUUID *connectionID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:moid];
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConnection]];
        }
        syncConnection.conversation.remoteIdentifier = connectionID;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        
        NSMutableDictionary *payload = [self connectionPayloadForConversationID:connectionID fromID:selfUserID toID:user.remoteIdentifier status:@"accepted"];
        payload[@"message"] = messageText;
        
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:payload HTTPstatus:200 transportSessionError:nil headers:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:moid];
        XCTAssertTrue(syncConnection.existsOnBackend);
        XCTAssertTrue(syncConnection.needsToBeUpdatedFromBackend);
    }];
}

- (void)testThatItMarksTheConversationAsNeedToBeUpdatedAfterItUpdatesAConnection
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        ZMUser *user = [ZMUser selfUserInContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.conversationType = ZMConversationTypeConnection;
        connection.conversation = conversation;
        connection.to = user;
        
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // when
        NSDictionary *payload = [self connectionPayloadForConversationID:conversation.remoteIdentifier fromID:selfUser.remoteIdentifier toID:user.remoteIdentifier status:@"accepted"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:connection requestUserInfo:nil response:response keysToParse:[NSSet setWithArray:conversation.keysTrackedForLocalModifications]];
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
    }];
}

- (void)testThatItDeletesAConversationWhenTheBackEndRefusesTheConnection
{
    NSUUID *selfUserID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        selfUser.name = @"Neal Stephenson";
        selfUser.remoteIdentifier = selfUserID;
    }];
    
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"John";
    user.remoteIdentifier = [NSUUID createUUID];
    
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.message = @"hmm";
    [self markUserAndConversationAsUpdatedForConnection:connection];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSManagedObjectID *connectionMoid = connection.objectID;
    NSManagedObjectID *conversationMoid = connection.conversation.objectID;
    
    NSUUID *connectionID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *syncConnection = (id) [self.syncMOC objectWithID:connectionMoid];
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConnection]];
        }
        syncConnection.conversation.remoteIdentifier = connectionID;
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        NSDictionary *payload = @{@"label": @"connection-limit"};
        
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:payload HTTPstatus:403 transportSessionError:nil headers:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertNil([self.syncMOC existingObjectWithID:connectionMoid error:nil]);
        XCTAssertNil([self.syncMOC existingObjectWithID:conversationMoid error:nil]);
    }];
}


- (void)testThatWhenItReceivesAConnectionFromTheServerThatHasAlsoBeenCreatedLocallyItReplacesIt;
{
    // If we connect to a "search user" and at the same time receive a connection request from that
    // user (ie. before we've sent out request) ...
    // We should replace the local connection object with the server's and set the status to accepted.
    
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    selfUser.remoteIdentifier = [NSUUID createUUID];
    selfUser.name = @"Neal Stephenson";
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"John";
    user.remoteIdentifier = [NSUUID createUUID];
    NSUUID *userID = user.remoteIdentifier;
    ZMConnection *uiConnection = [ZMConnection insertNewSentConnectionToUser:user];
    XCTAssert([self.uiMOC saveOrRollback]); // <<---- SAVE HERE
    NSString *messageText = @"Aenean non sapien massa.";
    uiConnection.message = messageText;
    uiConnection.lastUpdateDate = [NSDate dateWithTimeIntervalSinceNow:-1];
    
    NSUUID *remoteConversationID = [NSUUID createUUID];
    NSUUID *selfUserID = selfUser.remoteIdentifier;
    NSString *newMessage = @"Super cool.";
    
    // when
    
    NSDate *update = [NSDate date];
    [self.syncMOC performGroupedBlockAndWait:^{
        NSMutableDictionary *payload = [self connectionPayloadForConversationID:remoteConversationID fromID:selfUserID toID:userID status:@"pending"];
        payload[@"message"] = newMessage;
        payload[@"last_update"] = [NSDate date];
  
        ZMConnection *syncConnection = [ZMConnection connectionFromTransportData:payload managedObjectContext:self.syncMOC];
        XCTAssertNotNil(syncConnection);
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.uiMOC reset];
    
    NSArray *connections = [self.uiMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]];
    XCTAssertEqual(connections.count, 1u);
    uiConnection = connections[0];

    NSArray *conversations = [self.uiMOC executeFetchRequestOrAssert:[ZMConversation sortedFetchRequest]];
    XCTAssertEqual(conversations.count, 1u);
    ZMConversation *conversation = conversations[0];
    
    NSArray *users = [self.uiMOC executeFetchRequestOrAssert:[ZMUser sortedFetchRequest]];
    XCTAssertEqual(users.count, 2u, @"self + other");
    user = [users firstObjectMatchingWithBlock:^BOOL(id obj) {
        return (obj != [ZMUser selfUserInContext:self.uiMOC]);
    }];
    
    (void) user;
    (void) conversation;
    XCTAssertEqualObjects(uiConnection.message, newMessage);
    XCTAssertEqual(uiConnection.status, ZMConnectionStatusAccepted);
    XCTAssertTrue([uiConnection hasLocalModificationsForKey:@"status"], @"We need to push this to the backend.");
    XCTAssertEqual(uiConnection.conversation, conversation);
    XCTAssertEqual(uiConnection.to, user);
    XCTAssertEqualWithAccuracy(uiConnection.lastUpdateDateInGMT.timeIntervalSinceReferenceDate, update.timeIntervalSinceReferenceDate, 0.1);
}

- (void)testThatItDoesNotSetConversationNeedsToBeUpdatedFromBackendWhenConnectionIsPending
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = NSUUID.createUUID;
    
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = NSUUID.createUUID;

    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.status = ZMConnectionStatusInvalid;
    connection.conversation.remoteIdentifier = NSUUID.createUUID;
    
    NSDictionary *payload = [self connectionPayloadForConversationID:connection.conversation.remoteIdentifier
                                                              fromID:selfUser.remoteIdentifier
                                                                toID:user.remoteIdentifier
                                                              status:@"pending"];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    [self.sut updateUpdatedObject:connection requestUserInfo:nil response:response keysToParse:[NSSet set]];
    
    // then
    XCTAssertFalse(connection.conversation.needsToBeUpdatedFromBackend);
}

- (void)testThatItSetConversationNeedsToBeUpdatedFromBackendWhenConnectionIsAccepted
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = NSUUID.createUUID;
    
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = NSUUID.createUUID;
    
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.status = ZMConnectionStatusInvalid;
    connection.conversation.remoteIdentifier = NSUUID.createUUID;
    
    NSDictionary *payload = [self connectionPayloadForConversationID:connection.conversation.remoteIdentifier
                                                              fromID:selfUser.remoteIdentifier
                                                                toID:user.remoteIdentifier
                                                              status:@"accepted"];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    [self.sut updateUpdatedObject:connection requestUserInfo:nil response:response keysToParse:[NSSet set]];
    
    // then
    XCTAssertTrue(connection.conversation.needsToBeUpdatedFromBackend);
}

@end

@implementation ZMConnectionTranscoderTest (Downstream)


- (void)testThatItUpdatesAConnectionFromDownstreamPayload;
{
    // given
    NSUUID *convRemoteID = NSUUID.createUUID;
    NSUUID *userRemoteID = NSUUID.createUUID;
    NSDate *lastUpdateDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417000000];
    NSDictionary *payload = @{@"status": @"pending",
                              @"conversation": convRemoteID.transportString,
                              @"to": userRemoteID.transportString,
                              @"from": @"f23aea6d-b7c6-4cfc-8df4-61905f5b71dc",
                              @"last_update": lastUpdateDate.transportString,
                              @"message": @"Hi Sabine, Let's connect. tiago test account web"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation.conversationType = ZMConversationTypeOneOnOne;
        connection.conversation.remoteIdentifier = convRemoteID;
        connection.status = ZMConnectionStatusAccepted;
        connection.to = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.to.remoteIdentifier = userRemoteID;
        connection.needsToBeUpdatedFromBackend = YES;
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // when
        
        id<ZMDownstreamTranscoder> t = (id) self.sut;
        [t updateObject:connection withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertEqual(connection.status, ZMConnectionStatusPending);
        XCTAssertEqual(connection.conversation.conversationType, ZMConversationTypeConnection);
        XCTAssertEqualObjects(connection.lastUpdateDate, lastUpdateDate);
    }];
}



-(void)testThatItDoesNotFetchEventsForConversationWithoutRemoteIdentifier
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                       withParticipants:@[user1, user2]];
        
        // when
        ZMTransportRequest *request;
        do {
            request = [self.sut.requestGenerators nextRequest];
            if (request == nil) {
                break;
            }
            XCTAssertEqual([request.path rangeOfString:@"events"].location, (NSUInteger) NSNotFound);
        } while (YES);
    }];
}

@end
