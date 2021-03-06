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


import XCTest
import ZMCLinkPreview
@testable import zmessaging

final class MockLinkDetector: LinkPreviewDetectorType {
    
    var nextResult = [LinkPreview]()
    var downloadLinkPreviewsCallCount = 0
    
    func downloadLinkPreviews(inText text: String, completion: [LinkPreview] -> Void) {
        downloadLinkPreviewsCallCount += 1
        completion(nextResult)
    }
    
}

class LinkPreviewPreprocessorTests: MessagingTest {

    var sut: LinkPreviewPreprocessor!
    var mockDetector: MockLinkDetector!
    
    override func setUp() {
        super.setUp()
        mockDetector = MockLinkDetector()
        sut = LinkPreviewPreprocessor(managedObjectContext: syncMOC, linkPreviewDetector: mockDetector)
    }
    
    func testThatItOnlyProcessesMessagesWithLinkPreviewState_WaitingToBeProcessed() {
        [ZMLinkPreviewState.Done, .Downloaded, .Processed, .Uploaded, .WaitingToBeProcessed].forEach {
            assertThatItProcessesMessageWithLinkPreviewState($0, shouldProcess: $0 == .WaitingToBeProcessed)
        }
    }
    
    func testThatItStoresTheOriginalImageDataInTheCacheAndSetsTheStateToDownloadedWhenItReceivesAPreviewWithImage() {
        // given 
        let URL = "http://www.example.com"
        let preview = LinkPreview(originalURLString: "example.com", permamentURLString: URL, offset: 0)
        preview.imageData = [.secureRandomDataOfLength(256)]
        preview.imageURLs = [NSURL(string: "http://www.example.com/image")!]
        mockDetector.nextResult = [preview]
        let message = createMessage()
        
        // when
        sut.objectsDidChange([message])
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(mockDetector.downloadLinkPreviewsCallCount, 1)
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.Downloaded)
        let data = syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .Original, encrypted: false)
        XCTAssertEqual(data, preview.imageData.first!)
        guard let genericMessage = message.genericMessage else { return XCTFail("No generic message") }
        XCTAssertFalse(genericMessage.text.linkPreview.isEmpty)
    }
    
    func testThatItSetsTheStateToUploadedWhenItReceivesAPreviewWithoutImage() {
        // given
        let URL = "http://www.example.com"
        mockDetector.nextResult = [LinkPreview(originalURLString: "example.com", permamentURLString: URL, offset: 0)]
        let message = createMessage()
        
        // when
        sut.objectsDidChange([message])
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(mockDetector.downloadLinkPreviewsCallCount, 1)
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.Uploaded)
        let data = syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .Original, encrypted: false)
        XCTAssertNil(data)
        guard let genericMessage = message.genericMessage else { return XCTFail("No generic message") }
        XCTAssertFalse(genericMessage.text.linkPreview.isEmpty)
    }
    
    func testThatItSetsTheStateToDoneIfNoPreviewsAreReturned() {
        // given
        let message = createMessage()
        
        // when
        sut.objectsDidChange([message])
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(mockDetector.downloadLinkPreviewsCallCount, 1)
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.Done)
    }
    
    func testThatItSetsTheStateToDoneIfTheMessageDoesNotHaceTextMessageData() {
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation.remoteIdentifier = .createUUID()
        let message = conversation.appendKnock() as! ZMClientMessage
        
        // when
        sut.objectsDidChange([message])
        
        // then
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.Done)
    }
    
    // MARK: - Helper
    
    func createMessage(state: ZMLinkPreviewState = .WaitingToBeProcessed) -> ZMClientMessage {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation.remoteIdentifier = .createUUID()
        let message = conversation.appendMessageWithText(name!) as! ZMClientMessage
        message.linkPreviewState = state
        return message
    }
    
    func assertThatItProcessesMessageWithLinkPreviewState(state: ZMLinkPreviewState, shouldProcess: Bool = false, line: UInt = #line) {
        // given
        let message = createMessage(state)
        
        // when
        sut.objectsDidChange([message])
        
        // then
        XCTAssertEqual(mockDetector.downloadLinkPreviewsCallCount, shouldProcess ? 1 : 0, line: line, "Failure processing state \(state.rawValue)")
    }
}
