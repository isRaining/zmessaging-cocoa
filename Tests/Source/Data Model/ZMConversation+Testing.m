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


@import ZMCDataModel;
@import ZMCMockTransport;
@import ZMTesting;

@implementation ZMConversation (Testing)

- (void)assertMatchesConversation:(MockConversation *)conversation failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    if (conversation == nil) {
        [failureRecorder recordFailure:@"ZMConversation is <nil>"];
        return;
    }

    if (!(self.userDefinedName == conversation.name || [self.userDefinedName isEqualToString:conversation.name])) {
        [failureRecorder recordFailure:@"Name doesn't match '%@' != '%@'",
         self.userDefinedName, conversation.name];
    }
    if (!([self.creator.remoteIdentifier isEqual:[conversation.creator.identifier UUID]])) {
        [failureRecorder recordFailure:@"Creator doesn't match '%@' != '%@'",
                       self.creator.remoteIdentifier.transportString, conversation.creator.identifier];
    }

    NSMutableSet *activeUsersUUID = [NSMutableSet set];
    for(ZMUser *user in self.otherActiveParticipants) {
        [activeUsersUUID addObject:user.remoteIdentifier];
    }
    NSMutableSet *mockActiveUsersUUID = [NSMutableSet set];
    for (MockUser *mockUser in conversation.activeUsers) {
        [mockActiveUsersUUID addObject:[mockUser.identifier UUID]];
    }
    [mockActiveUsersUUID removeObject:conversation.selfIdentifier.UUID];
    if (![activeUsersUUID isEqual:mockActiveUsersUUID]) {
        [failureRecorder recordFailure:@"Active users don't match {%@} != {%@}",
         [[activeUsersUUID.allObjects valueForKey:@"transportString"] componentsJoinedByString:@", "],
         [[mockActiveUsersUUID.allObjects valueForKey:@"transportString"] componentsJoinedByString:@", "]];
    }

    NSMutableSet *inactiveUsersUUID = [NSMutableSet set];
    for(ZMUser *user in self.otherInactiveParticipants) {
        [inactiveUsersUUID addObject:user.remoteIdentifier];
    }
    NSMutableSet *mockInactiveUsersUUID = [NSMutableSet set];
    for (MockUser *mockUser in conversation.inactiveUsers) {
        [mockInactiveUsersUUID addObject:[mockUser.identifier UUID]];
    }
    [mockInactiveUsersUUID removeObject:conversation.selfIdentifier.UUID];
    if (![inactiveUsersUUID isEqual:mockInactiveUsersUUID]) {
        [failureRecorder recordFailure:@"Inactive users don't match {%@} != {%@}",
         [[inactiveUsersUUID.allObjects valueForKey:@"transportString"] componentsJoinedByString:@", "],
         [[mockInactiveUsersUUID.allObjects valueForKey:@"transportString"] componentsJoinedByString:@", "]];
    }

    if (!((self.lastModifiedDate == conversation.lastEventTime
          || fabs([self.lastModifiedDate timeIntervalSinceDate:conversation.lastEventTime]) < 1))) {
        [failureRecorder recordFailure:@"Last modified date doesn't match '%@' != '%@'",
         self.lastModifiedDate, conversation.lastEventTime];
    }

    if (!((self.lastEventID == nil && conversation.lastEvent == nil)
          || [self.lastEventID isEqualToEventID:[ZMEventID eventIDWithString:conversation.lastEvent]])) {
        [failureRecorder recordFailure:@"Last event ID doesn't match '%@' != '%@'",
         self.lastEventID, conversation.lastEvent];
    }

    if (!((self.lastReadEventID == nil && conversation.lastRead == nil)
          || [self.lastReadEventID isEqualToEventID:[ZMEventID eventIDWithString:conversation.lastRead]])) {
        [failureRecorder recordFailure:@"Last read event ID doesn't match '%@' != '%@'",
         self.lastReadEventID, conversation.lastRead];
    }

    if (!((self.clearedEventID == nil && conversation.clearedEventID == nil)
          || [self.clearedEventID isEqualToEventID:[ZMEventID eventIDWithString:conversation.clearedEventID]])) {
        [failureRecorder recordFailure:@"Cleared event ID doesn't match '%@' != '%@'",
         self.clearedEventID, conversation.clearedEventID];
    }

    if (![self.remoteIdentifier isEqual:[conversation.identifier UUID]]) {
        [failureRecorder recordFailure:@"Remote ID doesn't match '%@' != '%@'",
         self.remoteIdentifier.transportString, conversation.identifier];
    }

    // matching events
    NSMutableArray *mockTextMessages = [NSMutableArray array];
    for(MockEvent *event in conversation.events)
    {
        if([event.type isEqual:@"conversation.message-add"]) {
            [mockTextMessages addObject:[ZMEventID eventIDWithString:event.identifier]];
        }
    }
    [mockTextMessages sortUsingComparator:^NSComparisonResult(ZMEventID *event1, ZMEventID* event2) {
        return [event1 compare:event2];
    }];

    NSMutableArray *originalTextMessages = [NSMutableArray array];
    for(ZMMessage *message in self.messages) {
        if([message isKindOfClass:ZMTextMessage.class]) {
            [originalTextMessages addObject:message.eventID];
        }
    }
    [originalTextMessages sortUsingComparator:^NSComparisonResult(ZMEventID *event1, ZMEventID* event2) {
        return [event1 compare:event2];
    }];

    if (![mockTextMessages isEqualToArray:originalTextMessages]) {
        [failureRecorder recordFailure:@"Text messages don't match '%@' != '%@'",
         mockTextMessages, originalTextMessages];
    }
}
- (void)setUnreadCount:(NSUInteger)count;
{
    self.lastServerTimeStamp = [NSDate date];
    self.lastReadServerTimeStamp = self.lastServerTimeStamp;
    
    for (NSUInteger idx = 0; idx < count; idx++) {
        ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:self.managedObjectContext];
        message.serverTimestamp = [self.lastServerTimeStamp dateByAddingTimeInterval:5];
        [self resortMessagesWithUpdatedMessage:message];
        self.lastServerTimeStamp = message.serverTimestamp;
    }
}

- (void)addUnreadMissedCall
{
    ZMSystemMessage *systemMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.managedObjectContext];
    systemMessage.systemMessageType = ZMSystemMessageTypeMissedCall;
    systemMessage.serverTimestamp = self.lastReadServerTimeStamp ?
    [self.lastReadServerTimeStamp dateByAddingTimeInterval:1000] :
    [NSDate dateWithTimeIntervalSince1970:1231234];
    [self updateUnreadMessagesWithMessage:systemMessage];
}

- (void)setHasActiveCall:(BOOL)hasActiveCall
{
    self.callDeviceIsActive = hasActiveCall;
}

- (void)setHasExpiredMessage:(BOOL)hasUnreadUnsentMessage
{
    self.hasUnreadUnsentMessage = hasUnreadUnsentMessage;
}

@end

