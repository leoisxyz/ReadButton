import CryptoSwift
import Foundation
import Security

enum DPTCrypto {
    private static let prime = BigUInteger(
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF",
        radix: 16
    )!
    private static let keyTag = Data("com.readbutton.dpt.rsa".utf8)

    static func makeDH(devicePublic: Data) throws -> (publicKey: Data, sharedKey: Data) {
        let privateKey = BigUInteger(try randomData(count: 32))
        let deviceKey = BigUInteger(devicePublic)
        guard deviceKey >= 2, deviceKey <= prime - 2 else { throw DPTError.crypto }
        let publicKey = BigUInteger(2).power(privateKey, modulus: prime)
        let sharedKey = deviceKey.power(privateKey, modulus: prime)
        return (Data([0]) + fixedData(publicKey, count: 256), fixedData(sharedKey, count: 256))
    }

    static func deriveKey(sharedKey: Data, salt: Data) throws -> (auth: [UInt8], wrap: [UInt8]) {
        let bytes = try PKCS5.PBKDF2(
            password: Array(sharedKey),
            salt: Array(salt),
            iterations: 10_000,
            keyLength: 48,
            variant: .sha2(.sha256)
        ).calculate()
        return (Array(bytes.prefix(32)), Array(bytes.suffix(16)))
    }

    static func hmac(key: [UInt8], data: Data) throws -> Data {
        Data(try HMAC(key: key, variant: .sha2(.sha256)).authenticate(Array(data)))
    }

    static func wrap(_ data: Data, authKey: [UInt8], wrapKey: [UInt8]) throws -> Data {
        let kwa = Data(try hmac(key: authKey, data: data).prefix(8))
        let iv = try randomData(count: 16)
        let aes = try AES(key: wrapKey, blockMode: CBC(iv: Array(iv)), padding: .pkcs7)
        return Data(try aes.encrypt(Array(data + kwa))) + iv
    }

    static func unwrap(_ data: Data, authKey: [UInt8], wrapKey: [UInt8]) throws -> Data {
        guard data.count > 16 else { throw DPTError.crypto }
        let iv = Data(data.suffix(16))
        let aes = try AES(key: wrapKey, blockMode: CBC(iv: Array(iv)), padding: .pkcs7)
        let clear = Data(try aes.decrypt(Array(data.dropLast(16))))
        guard clear.count >= 8 else { throw DPTError.crypto }
        let value = Data(clear.dropLast(8))
        let expected = try hmac(key: authKey, data: value).prefix(8)
        guard clear.suffix(8).elementsEqual(expected) else { throw DPTError.crypto }
        return value
    }

    static func replaceRSAKey() throws -> String {
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag] as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrApplicationTag: keyTag]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let external = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw DPTError.crypto
        }
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let spki = der(0x30, algorithm + der(0x03, Data([0]) + external))
        let body = spki.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(body)-----END PUBLIC KEY-----\n"
    }

    static func sign(_ message: Data) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag,
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecReturnRef: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let privateKey = item as! SecKey?,
              let signature = SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                message as CFData,
                nil
              ) as Data? else { throw DPTError.crypto }
        return signature
    }

    static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw DPTError.crypto
        }
        return Data(bytes)
    }

    private static func fixedData(_ integer: BigUInteger, count: Int) -> Data {
        let value = integer.serialize()
        return Data(repeating: 0, count: max(0, count - value.count)) + value.suffix(count)
    }

    private static func der(_ tag: UInt8, _ value: Data) -> Data {
        Data([tag]) + derLength(value.count) + value
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 128 { return Data([UInt8(length)]) }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
