import CryptoKit
import Foundation
import Darwin

struct Config: Decodable {
    struct Endpoint: Decodable { let baseURL: String; let enabled: Bool }
    struct Services: Decodable { let cn: Endpoint; let global: Endpoint? }
    let schemaVersion: Int
    let revision: Int
    let services: Services
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func validate(_ endpoint: Config.Endpoint, domestic: Bool) {
    let text = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.contains("\\"), var c = URLComponents(string: text),
          let host = c.host, !host.isEmpty,
          c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
          c.port.map({ (1...65_535).contains($0) }) ?? true else {
        fail("Invalid endpoint: credentials, query, fragment and invalid ports are not allowed.")
    }
    while c.path.hasSuffix("/") { c.path.removeLast() }
    let approvedHTTP = domestic ? "http://47.120.49.23" : "http://www.breadmilk.top"
    guard c.scheme?.lowercased() == "https" || c.url?.absoluteString == approvedHTTP else {
        fail("Invalid endpoint: use HTTPS or the exact designated HTTP root for this service group.")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 || (args.count == 4 && args[3] == "--create-key") else {
    fail("Usage: swift scripts/sign-config.swift endpoints.json server-config.json /path/outside/repo/private.key [--create-key]")
}
let fileManager = FileManager.default
let inputURL = URL(fileURLWithPath: args[0]).standardizedFileURL
let outputURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let keyURL = URL(fileURLWithPath: args[2]).standardizedFileURL.resolvingSymlinksInPath()
let repositoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
guard !keyURL.path.hasPrefix(repositoryURL.path + "/"), keyURL != inputURL, keyURL != outputURL else {
    fail("Keep the signing private key outside the repository and separate from input/output files.")
}

do {
    let payload = try Data(contentsOf: inputURL)
    guard payload.count < 32_768 else { fail("Configuration payload must be smaller than 32 KiB.") }
    let config = try JSONDecoder().decode(Config.self, from: payload)
    guard config.schemaVersion == 1, config.revision > 0, config.services.cn.enabled else {
        fail("Expected schemaVersion 1, positive revision and enabled domestic endpoint.")
    }
    validate(config.services.cn, domestic: true)
    if let overseas = config.services.global { validate(overseas, domestic: false) }

    let key: Curve25519.Signing.PrivateKey
    if fileManager.fileExists(atPath: keyURL.path) {
        let attributes = try fileManager.attributesOfItem(atPath: keyURL.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            fail("Signing key permissions must restrict access to its owner (chmod 600).")
        }
        key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    } else {
        guard args.last == "--create-key" else { fail("Signing key is missing; use --create-key only for initial setup.") }
        try fileManager.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        key = Curve25519.Signing.PrivateKey()
        guard fileManager.createFile(atPath: keyURL.path, contents: key.rawRepresentation, attributes: [.posixPermissions: 0o600]) else {
            fail("Could not create signing key.")
        }
    }

    let signature = try key.signature(for: payload)
    guard key.publicKey.isValidSignature(signature, for: payload) else { fail("Signature self-check failed.") }
    let envelope = ["payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()]
    var output = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    output.append(0x0A)
    try output.write(to: outputURL, options: .atomic)
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    try (publicKey + "\n").write(to: outputURL.deletingLastPathComponent().appendingPathComponent("signing-public-key.txt"), atomically: true, encoding: .utf8)
    print("Signed revision \(config.revision). Public verification key: \(publicKey)")
} catch {
    fail("Signing failed: \(error.localizedDescription)")
}
