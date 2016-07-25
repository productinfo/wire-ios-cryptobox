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

class _CBoxSession : PointerWrapper {}

/// An encryption state that is usable to encrypt/decrypt messages
/// It maintains an in-memory cache of encryption sessions with other clients
/// that is persisted to disk as soon as it is deallocated.
public class EncryptionSessionsDirectory {
    
    /// Used for testing only. If set to true,
    /// will not try to validate with the generating context
    var debug_disableContextValidityCheck = false
    
    /// Context that created this status
    private weak var generatingContext: EncryptionContext!
    
    /// Local fingerprint
    public var localFingerprint : NSData
    
    /// Cache of transient sessions, indexed by client ID.
    /// Transient sessions are session that are (potentially) modified in memory
    /// and not yet committed to disk. When trying to load a session,
    /// and that session is already in the list of transient sessions,
    /// the transient session will be returned without any loading
    /// occurring. As soon as a session is saved, it is removed from the cache.
    ///
    /// - note: This is an optimization: instead of loading, decrypting,
    /// saving, unloading every time, if the same session is reused within
    /// the same execution block, we don't need to spend time reading
    /// and writing to disk every time we use the session, we can just
    /// load once and save once at the end.
    private var pendingSessionsCache : [String : EncryptionSession] = [:]
    
    init(generatingContext: EncryptionContext) {
        self.generatingContext = generatingContext
        self.localFingerprint = generatingContext.implementation.localFingerprint
    }
    
    /// The underlying implementation of the box
    var box : _CBox {
        return self.generatingContext!.implementation
    }
    
    /// Checks whether self is in a valid state, i.e. the generating context is still open and
    /// this is the current status. If not, it means that we are using this status after
    /// the context was done using this status.
    /// Will assert if this is the case.
    private func validateContext() -> EncryptionContext {
        guard self.debug_disableContextValidityCheck || self.generatingContext.currentSessionsDirectory === self else {
            // If you hit this line, check if the status was stored in a variable for later use,
            // or if it was used from different threads - it should never be.
            fatalError("Using encryption status outside of a context")
        }
        return self.generatingContext!
    }
    
    deinit {
        self.commitCache()
    }
}

// MARK: - Accessing sessions
extension EncryptionSessionsDirectory {
    
    /// Creates a session to a client using a prekey of that client
    /// The session is not saved to disk until the cache is committed
    /// - throws: CryptoBox error in case of lower-level error
    public func createClientSession(clientId: String, base64PreKeyString: String) throws {
        
        // validate
        guard let prekeyData = NSData(base64EncodedString: base64PreKeyString, options: []) else {
            fatalError("String is not base64 encoded")
        }
        let context = self.validateContext()

        // check if pre-existing
        if clientSessionById(clientId) != nil {
            return
        }

        // init
        let cbsession = _CBoxSession()
        let result = cbox_session_init_from_prekey(context.implementation.ptr,
                                                   clientId,
                                                   UnsafeMutablePointer<UInt8>(prekeyData.bytes),
                                                   prekeyData.length,
                                                   &cbsession.ptr
        )
        guard result == CBOX_SUCCESS else {
            throw result
        }
        let session = EncryptionSession(id: clientId,
                                        session: cbsession,
                                        requiresSave: true)
        self.pendingSessionsCache[clientId] = session
    }
    
    /// Creates a session to a client using a prekey message from that client
    /// The session is not saved to disk until the cache is committed
    /// - returns: the plaintext
    /// - throws: CryptoBox error in case of lower-level error
    public func createClientSessionAndReturnPlaintext(clientId: String, prekeyMessage: NSData) throws -> NSData {
        let context = self.validateContext()
        let cbsession = _CBoxSession()
        var plainTextBacking : COpaquePointer = nil
        let result = cbox_session_init_from_message(context.implementation.ptr,
                                                    clientId,
                                                    UnsafePointer<UInt8>(prekeyMessage.bytes),
                                                    prekeyMessage.length,
                                                    &cbsession.ptr,
                                                    &plainTextBacking)
        guard result == CBOX_SUCCESS else {
            throw result
        }
        let plainText = NSData.moveFromCBoxVector(plainTextBacking)
        let session = EncryptionSession(id: clientId,
                                        session: cbsession,
                                        requiresSave: true)
        self.pendingSessionsCache[clientId] = session
        return plainText
    }
    
    /// Deletes a session with a client
    public func delete(clientId: String) {
        let context = self.validateContext()
        self.discardFromCache(clientId)
        let result = cbox_session_delete(context.implementation.ptr, clientId)
        guard result == CBOX_SUCCESS else {
            fatalError("Error in deletion in cbox: \(result)")
        }
    }
}

// MARK: - Prekeys
extension EncryptionSessionsDirectory {
    
    /// Generates one prekey of the given ID. If the prekey exists already,
    /// it will replace that prekey
    /// - returns: base 64 encoded string
    public func generatePrekey(id: UInt16) throws -> String {
        guard id <= CBOX_LAST_PREKEY_ID else {
            // this should never happen, as CBOX_LAST_PREKEY_ID is UInt16.max
            fatalError("Prekey out of bound")
        }
        var vectorBacking : COpaquePointer = nil
        let context = self.validateContext()
        let result = cbox_new_prekey(context.implementation.ptr, id, &vectorBacking)
        let prekey = NSData.moveFromCBoxVector(vectorBacking)
        guard result == CBOX_SUCCESS else {
            throw result
        }
        return prekey.base64EncodedStringWithOptions([])
    }
    
    /// Generates the last prekey. If the prekey exists already,
    /// it will replace that prekey
    public func generateLastPrekey() throws -> String {
        return try generatePrekey(CBOX_LAST_PREKEY_ID)
    }
    
    /// Generates prekeys from a range of IDs. If prekeys with those IDs exist already,
    /// they will be replaced
    public func generatePrekeys(range: Range<UInt16>) throws -> [(id: UInt16, prekey: String)] {
        return try range.map {
            let prekey = try self.generatePrekey($0)
            return (id: $0, prekey: prekey)
        }
    }
}

// MARK: - Fingerprint
extension _CBox {
    
    /// Local fingerprint
    private var localFingerprint : NSData {
        var vectorBacking : COpaquePointer = nil
        let result = cbox_fingerprint_local(self.ptr, &vectorBacking)
        guard result == CBOX_SUCCESS else {
            fatalError("Can't get local fingerprint") // this is so rare, that we don't even throw
        }
        return NSData.moveFromCBoxVector(vectorBacking)
    }
}

extension EncryptionSessionsDirectory {
    
    /// Returns the remote fingerprint of a client session
    public func fingerprintForClient(clientId: String) -> NSData? {
        guard let session = self.clientSessionById(clientId) else {
            return nil
        }
        return session.remoteFingerprint
    }
}


// MARK: - Sessions cache management
extension EncryptionSessionsDirectory {
    
    /// Returns an existing session for a client
    /// - returns: a session if it exists, or nil if not there
    private func clientSessionById(clientId: String) -> EncryptionSession? {
        let context = self.validateContext()
        
        // check cache
        if let transientSession = self.pendingSessionsCache[clientId] {
            return transientSession
        }
        
        let cbsession = _CBoxSession()
        let result = cbox_session_load(context.implementation.ptr, clientId, &cbsession.ptr)
        switch(result) {
        case CBOX_SESSION_NOT_FOUND:
            return nil
        case CBOX_SUCCESS:
            let session = EncryptionSession(id: clientId,
                                            session: cbsession,
                                            requiresSave: false)
            self.pendingSessionsCache[clientId] = session
            return session
        default:
            fatalError("Error in loading from cbox: \(result)")
        }
    }
    
    /// Closes all transient sessions without saving them
    public func discardCache() {
        self.pendingSessionsCache = [:]
    }
    
    /// Save and unload all transient sessions
    private func commitCache() {
        for (_, session) in self.pendingSessionsCache {
            session.save(self.box)
        }
        discardCache()
    }
    
    /// Closes a transient session. Any unsaved change will be lost
    private func discardFromCache(clientId: String) {
        self.pendingSessionsCache.removeValueForKey(clientId)
    }

    /// Saves the cached session for a client and removes it from the cache
    private func saveSession(clientId: String) {
        guard let session = pendingSessionsCache[clientId] else {
            return
        }
        session.save(self.box)
        discardFromCache(clientId)
    }
}

/// A cryptographic session used to encrypt/decrypt data send to and received from
/// another client
/// - note: This class is private because we want to make sure that no one can use
/// sessions outside of a status, that only dirty sessions are kept in memory, and
/// that sessions are unloaded as soon as possible, and that sessions are closed as soon
/// as they are unloaded.
/// We let the status manages closing sessions as there is no
/// other easy way to enforce (other than asserting) that we don't use a session to encrypt/decrypt
/// after it has been closed, and there is no easy way to ensure that sessions are always closed.
/// By hiding the implementation inside this file, only code in this file has the chance to screw up!
private class EncryptionSession {
    
    /// Whether this session has changes that require saving
    var hasChanges : Bool
    
    /// client ID
    let id: String
    
    /// Underlying C-style implementation
    let implementation: _CBoxSession
    
    /// The fingerpint of the client
    let remoteFingerprint: NSData
    
    /// Creates a session from a C-level session pointer
    /// - parameter id: id of the client
    /// - parameter requiresSave: if true, mark this session as having pending changes to save
    init(id: String,
         session: _CBoxSession,
         requiresSave: Bool
        ) {
        self.id = id
        self.implementation = session
        self.remoteFingerprint = session.remoteFingerprint
        self.hasChanges = requiresSave
    }
    
    /// Closes the session in CBox
    private func closeInCryptobox() {
        cbox_session_close(self.implementation.ptr)
    }
    
    /// Save the session to disk
    private func save(cryptobox: _CBox) {
        if self.hasChanges {
            let result = cbox_session_save(cryptobox.ptr, self.implementation.ptr)
            switch(result) {
            case CBOX_SUCCESS:
                return
            default:
                fatalError("Can't save session: error \(result)")
            }
        }
    }
    
    deinit {
        closeInCryptobox()
    }
}

// MARK: - Encryption and decryption
extension EncryptionSessionsDirectory {
    
    /// Encrypts data for a client
    /// It immediately saves the session
    /// - returns: nil if there is no session with that client
    public func encrypt(plainText: NSData, recipientClientId: String) throws -> NSData? {
        self.validateContext()
        guard let session = self.clientSessionById(recipientClientId) else {
            return nil
        }
        let cypherText = try session.encrypt(plainText)
        self.saveSession(recipientClientId)
        return cypherText
    }
    
    /// Decrypts data from a client
    /// The session is not saved to disk until the cache is committed
    /// - returns: nil if there is no session with that client
    public func decrypt(cypherText: NSData, senderClientId: String) throws -> NSData? {
        self.validateContext()
        guard let session = self.clientSessionById(senderClientId) else {
            return nil
        }
        return try session.decrypt(cypherText)
    }
}


extension EncryptionSession {
    
    /// Decrypts data using the session. This function modifies the session
    /// and it should be saved later
    private func decrypt(cypher: NSData) throws -> NSData {
        var vectorBacking : COpaquePointer = nil
        let result = cbox_decrypt(self.implementation.ptr,
                                  UnsafePointer<UInt8>(cypher.bytes),
                                  cypher.length,
                                  &vectorBacking)
        guard result == CBOX_SUCCESS else {
            throw result
        }
        self.hasChanges = true
        return NSData.moveFromCBoxVector(vectorBacking)
    }
    
    /// Encrypts data using the session. This function modifies the session
    /// and it should be saved later
    private func encrypt(plainText: NSData) throws -> NSData {
        var vectorBacking : COpaquePointer = nil
        let result = cbox_encrypt(self.implementation.ptr,
                                  UnsafePointer<UInt8>(plainText.bytes),
                                  plainText.length,
                                  &vectorBacking
        )
        guard result == CBOX_SUCCESS else {
            throw result
        }
        self.hasChanges = true
        return NSData.moveFromCBoxVector(vectorBacking)
    }
}

// MARK: - Fingerprint
extension _CBoxSession {
    
    /// Returns the remote fingerprint associated with a session
    private var remoteFingerprint : NSData {
        var backingVector : COpaquePointer = nil
        let result = cbox_fingerprint_remote(self.ptr, &backingVector)
        guard result == CBOX_SUCCESS else {
            fatalError("Can't access remote fingerprint of session")
        }
        return NSData.moveFromCBoxVector(backingVector)
    }
}