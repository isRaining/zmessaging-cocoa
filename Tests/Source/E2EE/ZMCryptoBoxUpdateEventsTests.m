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


#import "MessagingTest.h"

@import Cryptobox;
@import zmessaging;
@import ZMCMockTransport;

#import <zmessaging/zmessaging-Swift.h>


@interface ZMCryptoBoxUpdateEventsTests : MessagingTest

@end

@implementation ZMCryptoBoxUpdateEventsTests

- (void)testThatItCanDecryptOTRMessageAddEvent
{
    // given
    NSUUID *notificationID = [NSUUID createUUID];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    UserClient *selfClient = [self createSelfClient];
    
    // create encrypted message
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:self.name nonce:[NSUUID createUUID].transportString];
    NSError *error;
    CBSession *session = [selfClient.keysStore.box sessionWithId:selfClient.remoteIdentifier fromPreKey:[selfClient.keysStore lastPreKeyAndReturnError:&error] error:&error];
    NSData *encryptedData = [session encrypt:message.data error:&error];
    
    NSDictionary *payload = @{
                              @"recipient": selfClient.remoteIdentifier,
                              @"sender": selfClient.remoteIdentifier,
                              @"text": [encryptedData base64String]
                              };
    NSDictionary *streamPayload = [self eventStreamPayloadWithSender:selfUser internalPayload:payload type:@"conversation.otr-message-add"];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:streamPayload uuid:notificationID];
    
    // when
    ZMUpdateEvent *decryptedEvent = [selfClient.keysStore.box decryptUpdateEventAndAddClient:event managedObjectContext:self.syncMOC];
    
    // then
    XCTAssertNotNil(decryptedEvent.payload.asDictionary[@"data"]);
    XCTAssertEqualObjects(decryptedEvent.payload.asDictionary[@"data"][@"sender"], selfClient.remoteIdentifier);
    XCTAssertEqualObjects(decryptedEvent.payload.asDictionary[@"data"][@"recipient"], selfClient.remoteIdentifier);
    ZMClientMessage *decryptedMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:decryptedEvent inManagedObjectContext:self.syncMOC prefetchResult:nil];
    XCTAssertEqualObjects(decryptedMessage.nonce.transportString, message.messageId);
    XCTAssertEqualObjects(decryptedMessage.textMessageData.messageText, message.text.content);
    XCTAssertEqualObjects(decryptedEvent.uuid, notificationID);
}

- (void)testThatItCanDecryptOTRAssetAddEvent
{
    // given
    NSUUID *notificationID = [NSUUID createUUID];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    UserClient *selfClient = [self createSelfClient];
    
    //create encrypted message
    NSData *imageData = [self verySmallJPEGData];
    CGSize imageSize = [ZMImagePreprocessor sizeOfPrerotatedImageWithData:imageData];
    ZMIImageProperties *properties = [ZMIImageProperties imagePropertiesWithSize:imageSize length:imageData.length mimeType:@"image/jpeg"];
    ZMImageAssetEncryptionKeys *keys = [[ZMImageAssetEncryptionKeys alloc] initWithOtrKey:[NSData randomEncryptionKey]
                                                                                   sha256:[imageData zmSHA256Digest]
                                                                                      ];
    NSUUID *messageNonce = [NSUUID createUUID];
    
    ZMGenericMessage *message = [ZMGenericMessage messageWithMediumImageProperties:properties
                                                          processedImageProperties:properties
                                                                    encryptionKeys:keys
                                                                             nonce:messageNonce.transportString
                                                                            format:ZMImageFormatMedium];
    
    NSError *error;
    CBSession *session = [selfClient.keysStore.box sessionWithId:selfClient.remoteIdentifier fromPreKey:[selfClient.keysStore lastPreKeyAndReturnError:&error] error:&error];
    NSData *encryptedData = [session encrypt:message.data error:&error];
    
    NSDictionary *payload = @{
                              @"recipient": selfClient.remoteIdentifier,
                              @"sender": selfClient.remoteIdentifier,
                              @"id": [NSUUID createUUID].transportString,
                              @"key": encryptedData.base64String
                              };
    
    NSDictionary *streamPayload = [self eventStreamPayloadWithSender:selfUser internalPayload:payload type:@"conversation.otr-asset-add"];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:streamPayload uuid:notificationID];
    
    // when
    ZMUpdateEvent *decryptedEvent = [selfClient.keysStore.box decryptUpdateEventAndAddClient:event managedObjectContext:self.syncMOC];
    
    // then
    XCTAssertNotNil(decryptedEvent.payload.asDictionary[@"data"]);
    ZMAssetClientMessage *decryptedMessage = [ZMAssetClientMessage createOrUpdateMessageFromUpdateEvent:decryptedEvent inManagedObjectContext:self.syncMOC prefetchResult:nil];
    XCTAssertEqualObjects(decryptedMessage.nonce.transportString, message.messageId);
    XCTAssertEqualObjects(decryptedMessage.imageAssetStorage.mediumGenericMessage, message);
    XCTAssertEqualObjects(decryptedEvent.uuid, notificationID);
}

- (void)testThatItInsertsAUnableToDecryptMessageIfItCanNotEstablishASession
{
    // given
    NSUUID *notificationID = [NSUUID createUUID];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    UserClient *selfClient = [self createSelfClient];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = [NSUUID UUID];
    conversation.conversationType = ZMConversationTypeGroup;
    
    //create encrypted message
    NSUUID *messageNonce = [NSUUID createUUID];
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"text" nonce:messageNonce.transportString];
    
    NSDictionary *payload = @{
                              @"recipient": selfClient.remoteIdentifier,
                              @"sender": [NSUUID UUID].transportString,
                              @"id": [NSUUID createUUID].transportString,
                              @"key": message.data.base64String // wrong message content
                              };
    
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:@{
                                                                        @"time": [[NSDate new] transportString],
                                                                        @"data": payload,
                                                                        @"conversation": conversation.remoteIdentifier.transportString,
                                                                        @"from": selfUser.remoteIdentifier.transportString,
                                                                        @"type": @"conversation.otr-asset-add"
                                                                        } uuid:notificationID];
    
    // when
    __block ZMUpdateEvent *decryptedEvent;
    [self performIgnoringZMLogError:^{
        decryptedEvent = [selfClient.keysStore.box decryptUpdateEventAndAddClient:event managedObjectContext:self.syncMOC];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(decryptedEvent);
    ZMSystemMessage *lastMessages = conversation.messages.lastObject;
    XCTAssertTrue([lastMessages isKindOfClass:[ZMSystemMessage class]]);
    XCTAssertEqual(lastMessages.systemMessageType, ZMSystemMessageTypeDecryptionFailed);
}

- (void)testThatItCanDecryptOTRMessageAddEventWithExternalData
{
    // given
    NSUUID *notificationID = NSUUID.createUUID;
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    UserClient *selfClient = self.createSelfClient;
    
    // create symmetrically encrypted text message and encrypt external message holding the keys using cryptobox
    NSError *error = nil;
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithText:self.name nonce:NSUUID.createUUID.transportString];
    ZMExternalEncryptedDataWithKeys *dataWithKeys = [ZMGenericMessage encryptedDataWithKeysFromMessage:textMessage];
    
    ZMGenericMessage *externalMessage = [ZMGenericMessage genericMessageWithKeyWithChecksum:dataWithKeys.keys messageID:NSUUID.createUUID.transportString];
    CBSession *session = [selfClient.keysStore.box sessionWithId:selfClient.remoteIdentifier fromPreKey:[selfClient.keysStore lastPreKeyAndReturnError:&error] error:&error];
    NSData *encryptedData = [session encrypt:externalMessage.data error:&error];
    XCTAssertNil(error);
    
    // create encrypted update event
    NSDictionary *payload = @{
                              @"recipient": selfClient.remoteIdentifier,
                              @"sender": selfClient.remoteIdentifier,
                              @"text": encryptedData.base64String,
                              @"data": dataWithKeys.data.base64String
                              };
    
    
    NSDictionary *streamPayload = [self eventStreamPayloadWithSender:selfUser internalPayload:payload type:@"conversation.otr-message-add"];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:streamPayload uuid:notificationID];
    
    // when
    ZMUpdateEvent *decryptedEvent = [selfClient.keysStore.box decryptUpdateEventAndAddClient:event managedObjectContext:self.syncMOC];
    
    // then
    NSDictionary *eventPayload = decryptedEvent.payload.asDictionary;
    NSData *externalData = eventPayload[@"external"];
    NSData *text = eventPayload[@"data"];
    
    XCTAssertTrue(decryptedEvent.isEncrypted);
    XCTAssertTrue(decryptedEvent.wasDecrypted);
    XCTAssertNotNil(externalData);
    XCTAssertNotNil(text);
    
    // when
    ZMClientMessage *decryptedMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:decryptedEvent
                                                                       inManagedObjectContext:self.syncMOC
                                                                               prefetchResult:nil];
    
    // then
    XCTAssertFalse(decryptedMessage.genericMessage.hasExternal);
    XCTAssertEqualObjects(decryptedMessage.nonce.transportString, textMessage.messageId);
    XCTAssertEqualObjects(decryptedMessage.textMessageData.messageText, textMessage.text.content);
    XCTAssertEqualObjects(decryptedEvent.uuid, notificationID);
}

#pragma mark - Helper

- (NSDictionary *)eventStreamPayloadWithSender:(ZMUser *)sender internalPayload:(NSDictionary *)payload type:(NSString *)type
{
    return @{
        @"time": NSDate.date.transportString,
        @"data": payload,
        @"conversation": NSUUID.createUUID.transportString,
        @"from": sender.remoteIdentifier.transportString,
        @"type": type
        };
}

@end

