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


import Foundation

public enum ClientUpdatePhase {
    case Done
    case FetchingClients
    case DeletingClients
}


let ClientUpdateErrorDomain = "ClientManagement"

@objc
public enum ClientUpdateError : NSInteger {
    case None
    case SelfClientIsInvalid
    case InvalidCredentials
    case DeviceIsOffline
    case ClientToDeleteNotFound
    
    func errorForType() -> NSError {
        return NSError(domain: ClientUpdateErrorDomain, code: self.rawValue, userInfo: nil)
    }
}

@objc
public class ClientUpdateStatus: NSObject {
    
    var syncManagedObjectContext: NSManagedObjectContext

    private var isFetchingClients = false
    private var isWaitingToDeleteClients = false
    private var needsToVerifySelfClient = false
    private var needsToVerifySelfClientOnAuthenticationDidSucceed = false

    private var tornDown = false
    
    private var authenticationToken : ZMAuthenticationObserverToken?
    private var internalCredentials : ZMEmailCredentials?
    public var credentials : ZMEmailCredentials? {
        return internalCredentials
    }

    public init(syncManagedObjectContext: NSManagedObjectContext) {
        self.syncManagedObjectContext = syncManagedObjectContext
        super.init()
        self.authenticationToken = ZMUserSessionAuthenticationNotification.addObserverWithBlock { [weak self] note in
            if note.type == .AuthenticationNotificationAuthenticationDidSuceeded {
                self?.authenticationDidSucceed()
            }
        }
        self.needsToVerifySelfClientOnAuthenticationDidSucceed = !ZMClientRegistrationStatus.needsToRegisterClientInContext(self.syncManagedObjectContext)
        
        // check if we are already trying to delete the client
        if let selfUser = ZMUser.selfUserInContext(syncManagedObjectContext).selfClient() where selfUser.markedToDelete {
            // This recovers from the bug where we think we should delete the self cient.
            // See: https://wearezeta.atlassian.net/browse/ZIOS-6646
            // This code can be removed and possibly moved to a hotfix once all paths that lead to the bug
            // have been discovered
            selfUser.markedToDelete = false
            selfUser.resetLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMarkedToDeleteKey))
        }
    }
    
    public func tearDown() {
        ZMUserSessionAuthenticationNotification.removeObserver(self.authenticationToken)
        authenticationToken = nil
        tornDown = true
    }
    
    deinit {
        assert(tornDown)
    }
    
    func authenticationDidSucceed() {
        needsToFetchClients(andVerifySelfClient: needsToVerifySelfClientOnAuthenticationDidSucceed)
    }
    
    public var currentPhase : ClientUpdatePhase {
        if isFetchingClients {
            return .FetchingClients
        }
        if isWaitingToDeleteClients {
            return .DeletingClients
        }
        return .Done
    }
    
    public func needsToFetchClients(andVerifySelfClient verifySelfClient: Bool) {
        isFetchingClients = true
        
        // there are three cases in which this method is called
        // (1) when not registered - we try to register a device but there are too many devices registered
        // (2) when registered - we want to manage our registered devices from the settings screen
        // (3) when registered - we want to verify the selfClient on startup
        // we only want to verify the selfClient when we are already registered
        needsToVerifySelfClient = verifySelfClient
    }
    
    public func didFetchClients(clients: Array<UserClient>) {
        if isFetchingClients {
            isFetchingClients = false
            var excludingSelfClient = clients
            if needsToVerifySelfClient {
                do {
                    excludingSelfClient = try filterSelfClientIfValid(excludingSelfClient)
                    ZMClientUpdateNotification.notifyFetchingClientsCompletedWithUserClients(excludingSelfClient)
                }
                catch let error as NSError {
                    ZMClientUpdateNotification.notifyFetchingClientsDidFail(error)
                }
            }
            else {
                ZMClientUpdateNotification.notifyFetchingClientsCompletedWithUserClients(clients)
            }
        }
    }
    
    func filterSelfClientIfValid(clients: [UserClient]) throws -> [UserClient] {
        guard let selfClient = ZMUser.selfUserInContext(self.syncManagedObjectContext).selfClient()
        else {
            throw ClientUpdateError.errorForType(.SelfClientIsInvalid)()
        }
        var error : NSError?
        var excludingSelfClient : [UserClient] = []
        
        var didContainSelf = false
        excludingSelfClient = clients.filter {
            if ($0.remoteIdentifier != selfClient.remoteIdentifier) {
                return true
            }
            didContainSelf = true
            return false
        }
        if !didContainSelf {
            // the selfClient was removed by an other user
            error = ClientUpdateError.errorForType(.SelfClientIsInvalid)()
            excludingSelfClient = []
        }

        if let error = error {
            throw error
        }
        return excludingSelfClient
    }
    
    public func failedToFetchClients() {
        if isFetchingClients {
            let error = ClientUpdateError.errorForType(.DeviceIsOffline)()
            ZMClientUpdateNotification.notifyFetchingClientsDidFail(error)
        }
    }
    
    public func deleteClients(withCredentials emailCredentials:ZMEmailCredentials) {
        if emailCredentials.password?.characters.count > 0 {
            isWaitingToDeleteClients = true
            internalCredentials = emailCredentials
        } else {
            ZMClientUpdateNotification.notifyDeletionFailed(ClientUpdateError.errorForType(.InvalidCredentials)())
        }
    }
    
    public func failedToDeleteClient(client:UserClient, error: NSError) {
        if !isWaitingToDeleteClients {
            return
        }
        if let errorCode = ClientUpdateError(rawValue: error.code) where error.domain == ClientUpdateErrorDomain {
            if  errorCode == .ClientToDeleteNotFound {
                // the client existed locally but not remotely, we delete it locally (done by the transcoder)
                // this should not happen since we just fetched the clients
                // however if it happens and there is no other client to delete we should notify that all clients where deleted
                if !hasClientsToDelete {
                    internalCredentials = nil
                    ZMClientUpdateNotification.notifyDeletionCompleted(selfUserClientsExcludingSelfClient)
                }
            }
            else if  errorCode == .InvalidCredentials {
                isWaitingToDeleteClients = false
                internalCredentials = nil
                ZMClientUpdateNotification.notifyDeletionFailed(error)
            }
        }
    }
    
    public func didDeleteClient() {
        if isWaitingToDeleteClients && !hasClientsToDelete {
            isWaitingToDeleteClients = false
            internalCredentials = nil;
            ZMClientUpdateNotification.notifyDeletionCompleted(selfUserClientsExcludingSelfClient)
        }
    }
    
    var selfUserClientsExcludingSelfClient : [UserClient] {
        let selfUser = ZMUser.selfUserInContext(self.syncManagedObjectContext);
        let selfClient = selfUser.selfClient()
        let remainingClients = selfUser.clients.filter{$0 != selfClient && !$0.isZombieObject}
        return remainingClients
    }
    
    var hasClientsToDelete : Bool {
        let selfUser = ZMUser.selfUserInContext(self.syncManagedObjectContext)
        let undeletedClients = selfUser.clients.filter{$0.markedToDelete}
        return (undeletedClients.count > 0)
    }
}

