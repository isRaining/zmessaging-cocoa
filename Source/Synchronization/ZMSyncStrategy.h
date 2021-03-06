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



@import Foundation;

#import "ZMObjectSyncStrategy.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMUpdateEventsBuffer.h"
#import "ZMBackgroundFetch.h"

@class ZMTransportRequest;
@class ZMPushChannelConnection;
@class ZMAuthenticationStatus;
@protocol ZMTransportData;
@protocol AVSMediaManager;
@class ZMOnDemandFlowManager;
@protocol ZMSyncStateDelegate;
@class ZMTransportSession;
@protocol ZMBackgroundable;
@class ZMBadge;
@class ZMLocalNotificationDispatcher;
@class ZMUserProfileUpdateStatus;
@class ProxiedRequestsStatus;
@class ZMClientRegistrationStatus;
@class ClientUpdateStatus;
@class BackgroundAPNSPingBackStatus;
@class ZMAccountStatus;

@interface ZMSyncStrategy : NSObject <ZMObjectStrategyDirectory, ZMUpdateEventConsumer>

- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                     userProfileUpdateStatus:(ZMUserProfileUpdateStatus *)userProfileStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                          clientUpdateStatus:(ClientUpdateStatus *)clientUpdateStatus
                          proxiedRequestStatus:(ProxiedRequestsStatus *)proxiedRequestStatus
                               accountStatus:(ZMAccountStatus *)accountStatus
                backgroundAPNSPingBackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingBackStatus
                                mediaManager:(id<AVSMediaManager>)mediaManager
                         onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                     syncMOC:(NSManagedObjectContext *)syncMOC
                                       uiMOC:(NSManagedObjectContext *)uiMOC
                           syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                       backgroundableSession:(id<ZMBackgroundable>)backgroundableSession
                localNotificationsDispatcher:(ZMLocalNotificationDispatcher *)localNotificationsDispatcher
                    taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                                       badge:(ZMBadge *)badge;

- (void)didInterruptUpdateEventsStream;
- (void)didEstablishUpdateEventsStream;

- (ZMTransportRequest *)nextRequest;
- (void)dataDidChange;

/// Process events that are recevied through the notification stream or the websocket
- (void)processUpdateEvents:(NSArray <ZMUpdateEvent *>*)events ignoreBuffer:(BOOL)ignoreBuffer;

/// Process events that were downloaded as part of the clinet history
- (void)processDownloadedEvents:(NSArray <ZMUpdateEvent *>*)events;

- (BOOL)processSaveWithInsertedObjects:(NSSet *)insertedObjects updateObjects:(NSSet *)updatedObjects;
- (void)tearDown;

@property (nonatomic, readonly) BOOL slowSyncInProgress;
@property (nonatomic, readonly) NSManagedObjectContext *syncMOC;

- (void)startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;

/// Calls completionHandler when the change has gone through all transcoders
- (void)startBackgroundTaskWithCompletionHandler:(ZMBackgroundTaskHandler)handler;

- (void)transportSessionAccessTokenDidSucceedWithToken:(NSString *)token ofType:(NSString *)type;

@end
