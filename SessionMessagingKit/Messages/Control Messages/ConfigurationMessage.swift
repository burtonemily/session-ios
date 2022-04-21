// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit
import SessionUtilitiesKit

@objc(SNConfigurationMessage)
public final class ConfigurationMessage : ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case closedGroups
        case openGroups
        case displayName
        case profilePictureURL
        case profileKey
        case contacts
    }
    
    public var closedGroups: Set<ClosedGroup> = []
    public var openGroups: Set<String> = []
    public var displayName: String?
    public var profilePictureURL: String?
    public var profileKey: Data?
    public var contacts: Set<CMContact> = []

    public override var isSelfSendValid: Bool { true }
    
    // MARK: Initialization
    public override init() { super.init() }

    public init(displayName: String?, profilePictureURL: String?, profileKey: Data?, closedGroups: Set<ClosedGroup>, openGroups: Set<String>, contacts: Set<CMContact>) {
        super.init()
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.profileKey = profileKey
        self.closedGroups = closedGroups
        self.openGroups = openGroups
        self.contacts = contacts
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let closedGroups = coder.decodeObject(forKey: "closedGroups") as! Set<ClosedGroup>? { self.closedGroups = closedGroups }
        if let openGroups = coder.decodeObject(forKey: "openGroups") as! Set<String>? { self.openGroups = openGroups }
        if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profileKey = coder.decodeObject(forKey: "profileKey") as! Data? { self.profileKey = profileKey }
        if let contacts = coder.decodeObject(forKey: "contacts") as! Set<CMContact>? { self.contacts = contacts }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(closedGroups, forKey: "closedGroups")
        coder.encode(openGroups, forKey: "openGroups")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(profilePictureURL, forKey: "profilePictureURL")
        coder.encode(profileKey, forKey: "profileKey")
        coder.encode(contacts, forKey: "contacts")
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        closedGroups = ((try? container.decode(Set<ClosedGroup>.self, forKey: .closedGroups)) ?? [])
        openGroups = ((try? container.decode(Set<String>.self, forKey: .openGroups)) ?? [])
        displayName = try? container.decode(String.self, forKey: .displayName)
        profilePictureURL = try? container.decode(String.self, forKey: .profilePictureURL)
        profileKey = try? container.decode(Data.self, forKey: .profileKey)
        contacts = ((try? container.decode(Set<CMContact>.self, forKey: .contacts)) ?? [])
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(closedGroups, forKey: .closedGroups)
        try container.encodeIfPresent(openGroups, forKey: .openGroups)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(profilePictureURL, forKey: .profilePictureURL)
        try container.encodeIfPresent(profileKey, forKey: .profileKey)
        try container.encodeIfPresent(contacts, forKey: .contacts)
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> ConfigurationMessage? {
        guard let configurationProto = proto.configurationMessage else { return nil }
        let displayName = configurationProto.displayName
        let profilePictureURL = configurationProto.profilePicture
        let profileKey = configurationProto.profileKey
        let closedGroups = Set(configurationProto.closedGroups.compactMap { ClosedGroup.fromProto($0) })
        let openGroups = Set(configurationProto.openGroups)
        let contacts = Set(configurationProto.contacts.compactMap { CMContact.fromProto($0) })
        return ConfigurationMessage(displayName: displayName, profilePictureURL: profilePictureURL, profileKey: profileKey,
            closedGroups: closedGroups, openGroups: openGroups, contacts: contacts)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        let configurationProto = SNProtoConfigurationMessage.builder()
        if let displayName = displayName { configurationProto.setDisplayName(displayName) }
        if let profilePictureURL = profilePictureURL { configurationProto.setProfilePicture(profilePictureURL) }
        if let profileKey = profileKey { configurationProto.setProfileKey(profileKey) }
        configurationProto.setClosedGroups(closedGroups.compactMap { $0.toProto() })
        configurationProto.setOpenGroups([String](openGroups))
        configurationProto.setContacts(contacts.compactMap { $0.toProto() })
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setConfigurationMessage(try configurationProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct configuration proto from: \(self).")
            return nil
        }
    }

    // MARK: Description
    public override var description: String {
        """
        ConfigurationMessage(
            closedGroups: \([ClosedGroup](closedGroups).prettifiedDescription),
            openGroups: \([String](openGroups).prettifiedDescription),
            displayName: \(displayName ?? "null"),
            profilePictureURL: \(profilePictureURL ?? "null"),
            profileKey: \(profileKey?.toHexString() ?? "null"),
            contacts: \([CMContact](contacts).prettifiedDescription)
        )
        """
    }
}

// MARK: Closed Group
extension ConfigurationMessage {

    @objc(SNClosedGroup)
    public final class ClosedGroup: NSObject, Codable, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        private enum CodingKeys: String, CodingKey {
            case publicKey
            case name
            case encryptionKeyPublicKey
            case encryptionKeySecretKey
            case members
            case admins
            case expirationTimer
        }
        
        public let publicKey: String
        public let name: String
        public let encryptionKeyPair: ECKeyPair
        public let members: Set<String>
        public let admins: Set<String>
        public let expirationTimer: UInt32

        public var isValid: Bool { !members.isEmpty && !admins.isEmpty }

        public init(publicKey: String, name: String, encryptionKeyPair: ECKeyPair, members: Set<String>, admins: Set<String>, expirationTimer: UInt32) {
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
            self.expirationTimer = expirationTimer
        }

        public required init?(coder: NSCoder) {
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let name = coder.decodeObject(forKey: "name") as! String?,
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as! ECKeyPair?,
                let members = coder.decodeObject(forKey: "members") as! Set<String>?,
                let admins = coder.decodeObject(forKey: "admins") as! Set<String>? else { return nil }
                let expirationTimer = coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
            self.expirationTimer = expirationTimer
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
            coder.encode(expirationTimer, forKey: "expirationTimer")
        }
        
        // MARK: - Codable
        
        public required init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            publicKey = try container.decode(String.self, forKey: .publicKey)
            name = try container.decode(String.self, forKey: .name)
            encryptionKeyPair = try ECKeyPair(
                publicKeyData: try container.decode(Data.self, forKey: .encryptionKeyPublicKey),
                privateKeyData: try container.decode(Data.self, forKey: .encryptionKeySecretKey)
            )
            members = try container.decode(Set<String>.self, forKey: .members)
            admins = try container.decode(Set<String>.self, forKey: .admins)
            expirationTimer = try container.decode(UInt32.self, forKey: .expirationTimer)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(name, forKey: .name)
            try container.encode(encryptionKeyPair.publicKey, forKey: .encryptionKeyPublicKey)
            try container.encode(encryptionKeyPair.privateKey, forKey: .encryptionKeySecretKey)
            try container.encode(members, forKey: .members)
            try container.encode(admins, forKey: .admins)
            try container.encode(expirationTimer, forKey: .expirationTimer)
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageClosedGroup) -> ClosedGroup? {
            guard let publicKey = proto.publicKey?.toHexString(),
                let name = proto.name,
                let encryptionKeyPairAsProto = proto.encryptionKeyPair else { return nil }
            let encryptionKeyPair: ECKeyPair
            do {
                encryptionKeyPair = try ECKeyPair(publicKeyData: encryptionKeyPairAsProto.publicKey, privateKeyData: encryptionKeyPairAsProto.privateKey)
            } catch {
                SNLog("Couldn't construct closed group from proto: \(self).")
                return nil
            }
            let members = Set(proto.members.map { $0.toHexString() })
            let admins = Set(proto.admins.map { $0.toHexString() })
            let expirationTimer = proto.expirationTimer
            let result = ClosedGroup(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair, members: members, admins: admins, expirationTimer: expirationTimer)
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageClosedGroup? {
            guard isValid else { return nil }
            let result = SNProtoConfigurationMessageClosedGroup.builder()
            result.setPublicKey(Data(hex: publicKey))
            result.setName(name)
            do {
                let encryptionKeyPairAsProto = try SNProtoKeyPair.builder(publicKey: encryptionKeyPair.publicKey, privateKey: encryptionKeyPair.privateKey).build()
                result.setEncryptionKeyPair(encryptionKeyPairAsProto)
            } catch {
                SNLog("Couldn't construct closed group proto from: \(self).")
                return nil
            }
            result.setMembers(members.map { Data(hex: $0) })
            result.setAdmins(admins.map { Data(hex: $0) })
            result.setExpirationTimer(expirationTimer)
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct closed group proto from: \(self).")
                return nil
            }
        }

        public override var description: String { name }
    }
}

// MARK: Contact
extension ConfigurationMessage {

    @objc(SNConfigurationMessageContact)
    public final class CMContact: NSObject, Codable, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        private enum CodingKeys: String, CodingKey {
            case publicKey
            case displayName
            case profilePictureURL
            case profileKey
            
            case hasIsApproved
            case isApproved
            case hasIsBlocked
            case isBlocked
            case hasDidApproveMe
            case didApproveMe
        }
        
        public var publicKey: String?
        public var displayName: String?
        public var profilePictureURL: String?
        public var profileKey: Data?
        
        public var hasIsApproved: Bool
        public var isApproved: Bool
        public var hasIsBlocked: Bool
        public var isBlocked: Bool
        public var hasDidApproveMe: Bool
        public var didApproveMe: Bool

        public var isValid: Bool { publicKey != nil && displayName != nil }

        public init(
            publicKey: String,
            displayName: String,
            profilePictureURL: String?,
            profileKey: Data?,
            hasIsApproved: Bool,
            isApproved: Bool,
            hasIsBlocked: Bool,
            isBlocked: Bool,
            hasDidApproveMe: Bool,
            didApproveMe: Bool
        ) {
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureURL = profilePictureURL
            self.profileKey = profileKey
            self.hasIsApproved = hasIsApproved
            self.isApproved = isApproved
            self.hasIsBlocked = hasIsBlocked
            self.isBlocked = isBlocked
            self.hasDidApproveMe = hasDidApproveMe
            self.didApproveMe = didApproveMe
        }

        public required init?(coder: NSCoder) {
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let displayName = coder.decodeObject(forKey: "displayName") as! String? else { return nil }
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String?
            self.profileKey = coder.decodeObject(forKey: "profileKey") as! Data?
            self.hasIsApproved = (coder.decodeObject(forKey: "hasIsApproved") as? Bool ?? false)
            self.isApproved = (coder.decodeObject(forKey: "isApproved") as? Bool ?? false)
            self.hasIsBlocked = (coder.decodeObject(forKey: "hasIsBlocked") as? Bool ?? false)
            self.isBlocked = (coder.decodeObject(forKey: "isBlocked") as? Bool ?? false)
            self.hasDidApproveMe = (coder.decodeObject(forKey: "hasDidApproveMe") as? Bool ?? false)
            self.didApproveMe = (coder.decodeObject(forKey: "didApproveMe") as? Bool ?? false)
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(displayName, forKey: "displayName")
            coder.encode(profilePictureURL, forKey: "profilePictureURL")
            coder.encode(profileKey, forKey: "profileKey")
            coder.encode(hasIsApproved, forKey: "hasIsApproved")
            coder.encode(isApproved, forKey: "isApproved")
            coder.encode(hasIsBlocked, forKey: "hasIsBlocked")
            coder.encode(isBlocked, forKey: "isBlocked")
            coder.encode(hasDidApproveMe, forKey: "hasDidApproveMe")
            coder.encode(didApproveMe, forKey: "didApproveMe")
        }
        
        // MARK: - Codable
        
        public required init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            publicKey = try? container.decode(String.self, forKey: .publicKey)
            displayName = try? container.decode(String.self, forKey: .displayName)
            profilePictureURL = try? container.decode(String.self, forKey: .profilePictureURL)
            profileKey = try? container.decode(Data.self, forKey: .profileKey)
            
            hasIsApproved = try container.decode(Bool.self, forKey: .hasIsApproved)
            isApproved = try container.decode(Bool.self, forKey: .isApproved)
            hasIsBlocked = try container.decode(Bool.self, forKey: .hasIsBlocked)
            isBlocked = try container.decode(Bool.self, forKey: .isBlocked)
            hasDidApproveMe = try container.decode(Bool.self, forKey: .hasDidApproveMe)
            didApproveMe = try container.decode(Bool.self, forKey: .didApproveMe)
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageContact) -> CMContact? {
            let result: CMContact = CMContact(
                publicKey: proto.publicKey.toHexString(),
                displayName: proto.name,
                profilePictureURL: proto.profilePicture,
                profileKey: proto.profileKey,
                hasIsApproved: proto.hasIsApproved,
                isApproved: proto.isApproved,
                hasIsBlocked: proto.hasIsBlocked,
                isBlocked: proto.isBlocked,
                hasDidApproveMe: proto.hasDidApproveMe,
                didApproveMe: proto.didApproveMe
            )
            
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageContact? {
            guard isValid else { return nil }
            guard let publicKey = publicKey, let displayName = displayName else { return nil }
            let result = SNProtoConfigurationMessageContact.builder(publicKey: Data(hex: publicKey), name: displayName)
            if let profilePictureURL = profilePictureURL { result.setProfilePicture(profilePictureURL) }
            if let profileKey = profileKey { result.setProfileKey(profileKey) }
            
            if hasIsApproved { result.setIsApproved(isApproved) }
            if hasIsBlocked { result.setIsBlocked(isBlocked) }
            if hasDidApproveMe { result.setDidApproveMe(didApproveMe) }
            
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct contact proto from: \(self).")
                return nil
            }
        }

        public override var description: String { displayName ?? "" }
    }
}
