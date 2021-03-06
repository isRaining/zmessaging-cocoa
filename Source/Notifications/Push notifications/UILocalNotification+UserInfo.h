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


@import UIKit;
@class ZMConversation;
@class ZMUpdateEvent;


@interface UILocalNotification (UserInfo)

@property (readonly, copy, nullable) NSUUID *zm_conversationRemoteID;
@property (readonly, copy, nullable) NSUUID *zm_messageNonce;
@property (readonly, copy, nullable) NSUUID *zm_senderUUID;
@property (readonly, copy, nullable) NSDate *zm_eventTime;

- (nullable ZMConversation *)conversationInManagedObjectContext:(nonnull NSManagedObjectContext *)MOC;
- (nullable ZMMessage *)messageInConversation:(nonnull ZMConversation *)conversation inManagedObjectContext:(nonnull NSManagedObjectContext *)MOC;

- (void)setupUserInfo:(nullable ZMConversation *)conversation forEvent:(nullable ZMUpdateEvent *)event;

@end
