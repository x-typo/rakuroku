import Foundation
import Security
import Testing
@testable import Rakuroku

@Suite("Keychain persistence")
@MainActor
struct KeychainHelperTests {
    @Test("Replacing a saved token updates it without adding another item")
    func replacementUpdatesExistingItem() {
        let security = InMemoryKeychain(data: Data("old-token".utf8))
        let replacement = Data("new-token".utf8)

        #expect(KeychainHelper.save(
            key: "test-token",
            data: replacement,
            update: security.update,
            add: security.add
        ))

        #expect(security.data == replacement)
        #expect(security.operations == ["update"])
    }

    @Test("A failed replacement preserves the previous token without attempting an add")
    func failedReplacementPreservesExistingItem() {
        let original = Data("old-token".utf8)
        let security = InMemoryKeychain(data: original)
        security.updateFailure = errSecInteractionNotAllowed

        #expect(!KeychainHelper.save(
            key: "test-token",
            data: Data("new-token".utf8),
            update: security.update,
            add: security.add
        ))

        #expect(security.data == original)
        #expect(security.operations == ["update"])
    }

    @Test("A first save adds only after update reports that the item is absent")
    func firstSaveAddsMissingItem() {
        let security = InMemoryKeychain()
        let token = Data("new-token".utf8)

        #expect(KeychainHelper.save(
            key: "test-token",
            data: token,
            update: security.update,
            add: security.add
        ))

        #expect(security.data == token)
        #expect(security.operations == ["update", "add"])
    }

    @Test("An add failure is reported without retrying or storing a token")
    func firstSaveFailure() {
        let security = InMemoryKeychain()
        security.addFailure = errSecNotAvailable

        #expect(!KeychainHelper.save(
            key: "test-token",
            data: Data("new-token".utf8),
            update: security.update,
            add: security.add
        ))

        #expect(security.data == nil)
        #expect(security.operations == ["update", "add"])
    }

    @Test("Deletion succeeds for a deleted or absent item and reports other failures")
    func deletionStatus() {
        for status in [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed] {
            var deleteCount = 0
            let result = KeychainHelper.delete(key: "test-token") { query in
                deleteCount += 1
                #expect((query as NSDictionary)[kSecAttrAccount] as? String == "test-token")
                #expect((query as NSDictionary)[kSecClass] as? String == kSecClassGenericPassword as String)
                return status
            }

            #expect(result == (status == errSecSuccess || status == errSecItemNotFound))
            #expect(deleteCount == 1)
        }
    }
}

@MainActor
private final class InMemoryKeychain {
    private(set) var data: Data?
    private(set) var operations: [String] = []
    var updateFailure: OSStatus?
    var addFailure: OSStatus?

    init(data: Data? = nil) {
        self.data = data
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        operations.append("update")
        #expect((query as NSDictionary)[kSecAttrAccount] as? String == "test-token")
        #expect((query as NSDictionary)[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect((query as NSDictionary)[kSecValueData] == nil)
        if let updateFailure { return updateFailure }
        guard data != nil else { return errSecItemNotFound }
        store(attributes)
        return errSecSuccess
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        operations.append("add")
        #expect((attributes as NSDictionary)[kSecAttrAccount] as? String == "test-token")
        #expect((attributes as NSDictionary)[kSecClass] as? String == kSecClassGenericPassword as String)
        if let addFailure { return addFailure }
        guard data == nil else { return errSecDuplicateItem }
        store(attributes)
        return errSecSuccess
    }

    private func store(_ attributes: CFDictionary) {
        let values = attributes as NSDictionary
        #expect(values[kSecAttrAccessible] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        data = values[kSecValueData] as? Data
        #expect(data != nil)
    }
}
