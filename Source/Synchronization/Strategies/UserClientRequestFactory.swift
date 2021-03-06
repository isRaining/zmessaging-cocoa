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
import Cryptobox

enum UserClientRequestError: ErrorType {
    case NoPreKeys
    case NoLastPreKey
    case ClientNotRegistered
}

//TODO: when we should update last pre key or signaling keys?

public class UserClientRequestFactory {
    
    public init(keysCount: UInt = 100, missingClientsUserPageSize pageSize: Int = 128) {
        self.keyCount = keysCount
        missingClientsUserPageSize = pageSize
    }
    
    public let keyCount : UInt
    ///  The number of users that can be contained in a single request to get missing clients
    public let missingClientsUserPageSize : Int

    public func registerClientRequest(client: UserClient, credentials: ZMEmailCredentials?, authenticationStatus: ZMAuthenticationStatus) throws -> ZMUpstreamRequest {
        
        let (preKeysPayloadData, preKeysRangeMax) = try payloadForPreKeys(client)
        let (signalingKeysPayloadData, signalingKeys) = payloadForSignalingKeys()
        let lastPreKeyPayloadData = try payloadForLastPreKey(client)
        
        var payload: [String: AnyObject] = [
            "type": client.type,
            "label": (client.label ?? ""),
            "model": (client.model ?? ""),
            "class": (client.deviceClass ?? ""),
            "lastkey": lastPreKeyPayloadData,
            "prekeys": preKeysPayloadData,
            "sigkeys": signalingKeysPayloadData,
            "cookie" : ((authenticationStatus.cookieLabel.characters.count != 0) ? authenticationStatus.cookieLabel : "")
        ]
        
        if let password = credentials?.password {
            payload["password"] = password
        }
        
        let request = ZMTransportRequest(path: "/clients", method: ZMTransportRequestMethod.MethodPOST, payload: payload)
        request.addCompletionHandler(storeMaxRangeID(client, maxRangeID: preKeysRangeMax))
        request.addCompletionHandler(storeAPSSignalingKeys(client, signalingKeys: signalingKeys))
        
        let upstreamRequest = ZMUpstreamRequest(transportRequest: request)
        return upstreamRequest
    }
    
    
    func storeMaxRangeID(client: UserClient, maxRangeID: UInt) -> ZMCompletionHandler {
        let completionHandler = ZMCompletionHandler(onGroupQueue: client.managedObjectContext!, block: { response in
            if response.result == .Success {
                client.preKeysRangeMax = Int64(maxRangeID)
            }
        })
        return completionHandler
    }
    
    func storeAPSSignalingKeys(client: UserClient, signalingKeys: SignalingKeys) -> ZMCompletionHandler {
        let completionHandler = ZMCompletionHandler(onGroupQueue: client.managedObjectContext!, block: { response in
            if response.result == .Success {
                client.apsDecryptionKey = signalingKeys.decryptionKey
                client.apsVerificationKey = signalingKeys.verificationKey
                client.needsToUploadSignalingKeys = false
            }
        })
        return completionHandler
    }
    
    internal func payloadForPreKeys(client: UserClient, startIndex: UInt = 0) throws -> (payload: [NSDictionary], maxRange: UInt) {
        //we don't want to generate new prekeys if we already have them
        do {
            let (preKeys, preKeysRangeMin, preKeysRangeMax) = try client.keysStore.generateMoreKeys(keyCount, start: startIndex)
            let preKeysPayloadData = preKeys.enumerate().map { (index, preKey: CBPreKey) in
                ["key": preKey.data!.base64String(), "id": Int(preKeysRangeMin) + index]
            }
            return (preKeysPayloadData, preKeysRangeMax)
        }
        catch {
            throw UserClientRequestError.NoPreKeys
        }
    }
    
    internal func payloadForLastPreKey(client: UserClient) throws -> [String: AnyObject] {
        do {
            let lastKey = try client.keysStore.lastPreKey()
            let lastPreKeyString = lastKey.data!.base64String()
            let lastPreKeyPayloadData : [String: AnyObject] = ["key": lastPreKeyString, "id": CBMaxPreKeyID + 1]
            return lastPreKeyPayloadData
        } catch  {
            throw UserClientRequestError.NoLastPreKey
        }
    }
    
    internal func payloadForSignalingKeys() -> (payload: [String: String!], signalingKeys: SignalingKeys) {
        let signalingKeys = APSSignalingKeysStore.createKeys()
        let payload = ["enckey": signalingKeys.decryptionKey.base64String(), "mackey": signalingKeys.verificationKey.base64String()]
        return (payload, signalingKeys)
    }
    
    public func updateClientPreKeysRequest(client: UserClient) throws -> ZMUpstreamRequest {
        if let remoteIdentifier = client.remoteIdentifier {
            let startIndex = UInt(client.preKeysRangeMax)
            let (preKeysPayloadData, preKeysRangeMax) = try payloadForPreKeys(client, startIndex: startIndex)
            let payload: [String: AnyObject] = [
                "prekeys": preKeysPayloadData
            ]
            let request = ZMTransportRequest(path: "/clients/\(remoteIdentifier)", method: ZMTransportRequestMethod.MethodPUT, payload: payload)
            request.addCompletionHandler(storeMaxRangeID(client, maxRangeID: preKeysRangeMax))

            return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey), transportRequest: request, userInfo: nil)
        }
        throw UserClientRequestError.ClientNotRegistered
    }
    
    public func updateClientSignalingKeysRequest(client: UserClient) throws -> ZMUpstreamRequest {
        if let remoteIdentifier = client.remoteIdentifier {
            let (signalingKeysPayloadData, signalingKeys) = payloadForSignalingKeys()
            let payload: [String: AnyObject] = [
                "sigkeys": signalingKeysPayloadData,
                "prekeys": [] // NOTE backend always expects 'prekeys' to be present atm
            ]
            let request = ZMTransportRequest(path: "/clients/\(remoteIdentifier)", method: ZMTransportRequestMethod.MethodPUT, payload: payload)
            request.addCompletionHandler(storeAPSSignalingKeys(client, signalingKeys: signalingKeys))
            
            return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientNeedsToUpdateSignalingKeysKey), transportRequest: request, userInfo: nil)
        }
        throw UserClientRequestError.ClientNotRegistered
    }
    
    /// Password needs to be set
    public func deleteClientRequest(client: UserClient, credentials: ZMEmailCredentials) -> ZMUpstreamRequest! {
        let payload = [
                "email" : credentials.email!,
                "password" : credentials.password!
        ]
        let request =  ZMTransportRequest(path: "/clients/\(client.remoteIdentifier)", method: ZMTransportRequestMethod.MethodDELETE, payload: payload)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMarkedToDeleteKey), transportRequest: request)
    }
    
    public func fetchMissingClientKeysRequest(missingClientsMap: MissingClientsMap) -> ZMUpstreamRequest! {
        let request = ZMTransportRequest(path: "/users/prekeys", method: ZMTransportRequestMethod.MethodPOST, payload: missingClientsMap.payload)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMissingKey), transportRequest: request, userInfo: missingClientsMap.userInfo)
    }
    
    public func fetchClientsRequest() -> ZMTransportRequest! {
        return ZMTransportRequest(getFromPath: "/clients")
    }
    
}
