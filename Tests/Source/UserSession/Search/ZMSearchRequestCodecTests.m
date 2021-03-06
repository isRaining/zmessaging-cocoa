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

#import "IntegrationTestBase.h"
#import "ZMSearchRequestCodec.h"
#import "ZMSearchResult+Internal.h"

@interface ZMSearchRequestCodecTests : IntegrationTestBase
@property (nonatomic) NSArray *remoteIDStrings;
@end

@implementation ZMSearchRequestCodecTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (NSDictionary *)payLoadForRemoteIDs
{
    NSMutableArray *remoteIDs = [NSMutableArray array];
    for (NSString *idString in self.remoteIDStrings) {
        [remoteIDs addObject:@{@"id": idString}];
    }
    
    return @{@"took": @12,
             @"found": @0,
             @"documents": remoteIDs,
             @"returned": @9
             };
}

- (NSArray *)remoteIDStrings
{
    return @[@"7731f46f-4439-472b-aadf-f595f93ac144",
             @"5ee13682-aa9e-4714-a098-79b68a434923",
             @"98d4ce3c-ebdb-4996-b4c5-bfdf5e0d444a",
             @"b3cb4d5c-0610-43c4-ba44-c9b95e779360",
             @"ffd8f54e-5241-4ba6-84e5-480fd23a16f9",
             @"c57d62fd-c7e3-4f5a-8eb8-1efda42b9c62",
             @"63df9097-b68a-4bfc-a2e9-d5c37eb9bb1d",
             @"136f09b6-4a8e-40e8-9446-597dc2fdb0eb"];
}

- (NSArray *)remoteIDs
{
    NSMutableArray *remoteIDs = [NSMutableArray array];
    for (NSString *idString in self.remoteIDStrings) {
        [remoteIDs addObject:[[NSUUID alloc] initWithUUIDString:idString]];
    }
    return remoteIDs;
}

- (NSDictionary *)payloadForUsers:(NSArray *)users
{
    NSMutableArray *userDicts = [NSMutableArray array];
    for (MockUser *user in users) {
        NSString *transportString = user.identifier ?: NSUUID.createUUID.transportString;
        NSString *name = user.name ?: @"User";
        NSDictionary *userPayload = @{@"id" : transportString,
                                      @"name": name,
                                      @"accent_id": @4};
        [userDicts addObject:userPayload];
    }
    
    return @{@"documents": userDicts};
    
}

- (void)testThatItUsesTheCorrectPathForTopPeople
{
    // when
    ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForTopConversationsWithFetchLimit:9];
    
    // then
    XCTAssertEqualObjects(request.path, @"/search/top?size=9");
}

- (void)testThatItUsesTheCorrectPathForSuggestedPeople
{
    // when
    ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForSuggestedPeopleWithFetchLimit:9];
    
    // then
    XCTAssertEqualObjects(request.path, @"/search/suggestions?size=9");
}

- (void)testThatItUsesTheCorrectPathForNormalSearch
{
    // given
    NSString *queryString = @"search me";
    
    // when
    ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForQueryString:queryString levels:1 fetchLimit:9];
    
    // then
    XCTAssertEqualObjects(request.path, @"/search/contacts?q=search%20me&l=1&size=9");
}

- (void)testThatItReturnsRemoteIdentifiers
{
    // given
    NSDictionary *payload = [self payLoadForRemoteIDs];
    NSInteger HTTPstatus = 200;
    NSError *error = nil;

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:HTTPstatus transportSessionError:error];
    
    // when
    NSOrderedSet *remoteIDs = [ZMSearchRequestCodec remoteIdentifiersForSuggestedPeopleSearchResponse:response];
    
    // then
    NSArray *expectedRemoteIDs = [self remoteIDs];
    XCTAssertEqualObjects([[remoteIDs valueForKey:@"userIdentifier"] array], expectedRemoteIDs);
}

- (void)testThatItReturnsNilForAnHTTPStatusOtherThan200
{
    // given
    NSDictionary *payload = [self payLoadForRemoteIDs];
    NSInteger HTTPstatus = 400;
    NSError *error = nil;
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:HTTPstatus transportSessionError:error];
    
    // when
    NSOrderedSet *remoteIDs = [ZMSearchRequestCodec remoteIdentifiersForSuggestedPeopleSearchResponse:response];
    
    // then
    XCTAssertNil(remoteIDs);
}

- (void)testThatItReturnsNilWhenItHasATansportSessionError
{
    // given
    NSDictionary *payload = [self payLoadForRemoteIDs];
    NSInteger HTTPstatus = 200;
    NSError *error = [NSError errorWithDomain:@"ZMTransportSession" code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:HTTPstatus transportSessionError:error];
    
    // when
    NSOrderedSet *remoteIDs = [ZMSearchRequestCodec remoteIdentifiersForSuggestedPeopleSearchResponse:response];
    
    // then
    XCTAssertNil(remoteIDs);
}

- (void)testThatItAddsConnectedUsersToSearchResults_UsersInContact
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    NSDictionary *payload = [self payloadForUsers:@[self.user1]];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    ZMSearchResult *result = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:nil userSession:self.userSession];
    
    // then
    XCTAssertEqual(result.usersInContacts.count, 1u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);

    ZMUser *connectedUser = [self userForMockUser:self.user1];
    ZMSearchUser *searchUser = result.usersInContacts.firstObject;
    XCTAssertEqualObjects(searchUser.user, connectedUser);
}

- (void)testThatItAddsNonConnectedUsersToSearchResults_UsersInDirectory
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    NSString *name = @"User";
    
    NSDictionary *payload = @{@"documents": @[@{@"id" : NSUUID.createUUID.transportString,
                                                @"name": name,
                                                @"accent_id": @4}]};
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    ZMSearchResult *result = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:nil userSession:self.userSession];
    
    // then
    XCTAssertEqual(result.usersInDirectory.count, 1u);
    XCTAssertEqual(result.usersInContacts.count, 0u);

    ZMSearchUser *searchUser = result.usersInDirectory.firstObject;
    XCTAssertEqualObjects(searchUser.name, name);
}

- (void)testThatItDoesNotReturnTheSelfUserAsASearchResult
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    NSDictionary *payload = [self payloadForUsers:@[self.selfUser]];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    ZMSearchResult *result = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:nil userSession:self.userSession];
    
    // then
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.usersInContacts.count, 0u);
}

- (void)testThatItDoesNotReturnIgnoredUsersAsASearchResult
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    NSArray *ignoredIDs = @[[NSUUID uuidWithTransportString:self.user1.identifier]];
    NSDictionary *payload = [self payloadForUsers:@[self.user1]];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
    
    // when
    ZMSearchResult *result = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:ignoredIDs userSession:self.userSession];
    
    // then
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.usersInContacts.count, 0u);
}



@end
