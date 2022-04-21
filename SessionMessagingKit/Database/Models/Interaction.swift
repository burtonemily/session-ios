// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Interaction: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "interaction" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    internal static let linkPreviewForeignKey = ForeignKey(
        [Columns.linkPreviewUrl],
        to: [LinkPreview.Columns.url]
    )
    internal static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    internal static let interactionAttachments = hasMany(
        InteractionAttachment.self,
        using: InteractionAttachment.interactionForeignKey
    )
    internal static let attachments = hasMany(
        Attachment.self,
        through: interactionAttachments,
        using: InteractionAttachment.attachment
    )
    public static let quote = hasOne(Quote.self, using: Quote.interactionForeignKey)
    internal static let linkPreview = hasOne(LinkPreview.self, using: LinkPreview.interactionForeignKey)
    private static let recipientStates = hasMany(RecipientState.self, using: RecipientState.interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case serverHash
        case threadId
        case authorId
        
        case variant
        case body
        case timestampMs
        case receivedAtTimestampMs
        case wasRead
        
        case expiresInSeconds
        case expiresStartedAtMs
        case linkPreviewUrl
        
        // Open Group specific properties
        
        case openGroupServerMessageId
        case openGroupWhisperMods
        case openGroupWhisperTo
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standardIncoming
        case standardOutgoing
        case standardIncomingDeleted
        
        // Info Message Types (spacing the values out to make it easier to extend)
        case infoClosedGroupCreated = 1000
        case infoClosedGroupUpdated
        case infoClosedGroupCurrentUserLeft
        
        case infoDisappearingMessagesUpdate = 2000
        
        case infoScreenshotNotification = 3000
        case infoMediaSavedNotification
        
        case infoMessageRequestAccepted = 4000
    }
    
    /// The `id` value is auto incremented by the database, if the `Interaction` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// The hash returned by the server when this message was created on the server
    ///
    /// **Note:** This will only be populated for `standardIncoming`/`standardOutgoing` interactions
    /// from either `contact` or `closedGroup` threads
    public let serverHash: String?
    
    /// The id of the thread that this interaction belongs to (used to expose the `thread` variable)
    public let threadId: String
    
    /// The id of the user who sent the interaction, also used to expose the `profile` variable)
    public let authorId: String
    
    /// The type of interaction
    public let variant: Variant
    
    /// The body of this interaction
    public let body: String?
    
    /// When the interaction was created in milliseconds since epoch
    ///
    /// **Note:** This value will be `0` if it hasn't been set yet
    public let timestampMs: Int64
    
    /// When the interaction was received in milliseconds since epoch
    ///
    /// **Note:** This value will be `0` if it hasn't been set yet
    public let receivedAtTimestampMs: Int64
    
    /// A flag indicating whether the interaction has been read (this is a flag rather than a timestamp because
    /// we couldn’t know if a read timestamp is accurate)
    ///
    /// **Note:** This flag is not applicable to standardOutgoing or standardIncomingDeleted interactions
    public let wasRead: Bool
    
    /// The number of seconds until this message should expire
    public let expiresInSeconds: TimeInterval?
    
    /// The timestamp in milliseconds since 1970 at which this messages expiration timer started counting
    /// down (this is stored in order to allow the `expiresInSeconds` value to be updated before a
    /// message has expired)
    public let expiresStartedAtMs: Double?
    
    /// This value is the url for the link preview for this interaction
    ///
    /// **Note:** This is also used for open group invitations
    public let linkPreviewUrl: String?
    
    // Open Group specific properties
    
    /// The `openGroupServerMessageId` value will only be set for messages from SOGS
    public let openGroupServerMessageId: Int64?
    
    /// This flag indicates whether this interaction is a whisper to the mods of an Open Group
    public let openGroupWhisperMods: Bool
    
    /// This value is the id of the user within an Open Group who is the target of this whisper interaction
    public let openGroupWhisperTo: String?
    
    // MARK: - Relationships
         
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: Interaction.thread)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Interaction.profile)
    }
    
    /// Depending on the data associated to this interaction this array will represent different things, these
    /// cases are mutually exclusive:
    ///
    /// **Quote:** The thumbnails associated to the `Quote`
    /// **LinkPreview:** The thumbnails associated to the `LinkPreview`
    /// **Other:** The files directly attached to the interaction
    public var attachments: QueryInterfaceRequest<Attachment> {
        request(for: Interaction.attachments)
    }

    public var quote: QueryInterfaceRequest<Quote> {
        request(for: Interaction.quote)
    }

    public var linkPreview: QueryInterfaceRequest<LinkPreview> {
        let linkPreviewAlias: TableAlias = TableAlias()
        
        return LinkPreview
            .aliased(linkPreviewAlias)
            .joining(
                required: LinkPreview.interactions
                    .filter(literal: [
                        "(ROUND((\(Interaction.Columns.timestampMs) / 1000 / 100000) - 0.5) * 100000)",
                        "=",
                        "\(linkPreviewAlias[LinkPreview.Columns.timestamp])"
                    ].joined(separator: " "))
                    .limit(1)   // Avoid joining to multiple interactions
            )
            .limit(1)   // Avoid joining to multiple interactions
    }
    
    public var recipientStates: QueryInterfaceRequest<RecipientState> {
        request(for: Interaction.recipientStates)
    }
    
    // MARK: - Initialization
    
    internal init(
        id: Int64? = nil,
        serverHash: String?,
        threadId: String,
        authorId: String,
        variant: Variant,
        body: String?,
        timestampMs: Int64,
        receivedAtTimestampMs: Int64,
        wasRead: Bool,
        expiresInSeconds: TimeInterval?,
        expiresStartedAtMs: Double?,
        linkPreviewUrl: String?,
        openGroupServerMessageId: Int64?,
        openGroupWhisperMods: Bool,
        openGroupWhisperTo: String?
    ) {
        self.id = id
        self.serverHash = serverHash
        self.threadId = threadId
        self.authorId = authorId
        self.variant = variant
        self.body = body
        self.timestampMs = timestampMs
        self.receivedAtTimestampMs = receivedAtTimestampMs
        self.wasRead = wasRead
        self.expiresInSeconds = expiresInSeconds
        self.expiresStartedAtMs = expiresStartedAtMs
        self.linkPreviewUrl = linkPreviewUrl
        self.openGroupServerMessageId = openGroupServerMessageId
        self.openGroupWhisperMods = openGroupWhisperMods
        self.openGroupWhisperTo = openGroupWhisperTo
    }
    
    public init(
        serverHash: String? = nil,
        threadId: String,
        authorId: String,
        variant: Variant,
        body: String? = nil,
        timestampMs: Int64 = 0,
        wasRead: Bool = false,
        expiresInSeconds: TimeInterval? = nil,
        expiresStartedAtMs: Double? = nil,
        linkPreviewUrl: String? = nil,
        openGroupServerMessageId: Int64? = nil,
        openGroupWhisperMods: Bool = false,
        openGroupWhisperTo: String? = nil
    ) throws {
        self.serverHash = serverHash
        self.threadId = threadId
        self.authorId = authorId
        self.variant = variant
        self.body = body
        self.timestampMs = timestampMs
        self.receivedAtTimestampMs = {
            switch variant {
                case .standardIncoming, .standardOutgoing: return Int64(Date().timeIntervalSince1970 * 1000)

                /// For TSInteractions which are not `standardIncoming` and `standardOutgoing` use the `timestampMs` value
                default: return timestampMs
            }
        }()
        self.wasRead = wasRead
        self.expiresInSeconds = expiresInSeconds
        self.expiresStartedAtMs = expiresStartedAtMs
        self.linkPreviewUrl = linkPreviewUrl
        self.openGroupServerMessageId = openGroupServerMessageId
        self.openGroupWhisperMods = openGroupWhisperMods
        self.openGroupWhisperTo = openGroupWhisperTo
    }
    
    // MARK: - Custom Database Interaction
    
    public mutating func insert(_ db: Database) throws {
        try performInsert(db)
        
        // Since we need to do additional logic upon insert we can just set the 'id' value
        // here directly instead of in the 'didInsert' method (if you look at the docs the
        // 'db.lastInsertedRowID' value is the row id of the newly inserted row which the
        // interaction uses as it's id)
        let interactionId: Int64 = db.lastInsertedRowID
        self.id = interactionId
        
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: threadId) else {
            SNLog("Inserted an interaction but couldn't find it's associated thead")
            return
        }
        
        switch variant {
            case .standardOutgoing:
                // New outgoing messages should immediately determine their recipient list
                // from current thread state
                switch thread.variant {
                    case .contact:
                        try RecipientState(
                            interactionId: interactionId,
                            recipientId: threadId,  // Will be the contact id
                            state: .sending
                        ).insert(db)
                        
                    case .closedGroup:
                        guard
                            let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db),
                            let members: [GroupMember] = try? closedGroup.members.fetchAll(db)
                        else {
                            SNLog("Inserted an interaction but couldn't find it's associated thread members")
                            return
                        }
                        
                        try members.forEach { member in
                            try RecipientState(
                                interactionId: interactionId,
                                recipientId: member.profileId,
                                state: .sending
                            ).insert(db)
                        }
                        
                    case .openGroup:
                        // Since we use the 'RecipientState' type to manage the message state
                        // we need to ensure we have a state for all threads; so for open groups
                        // we just use the open group id as the 'recipientId' value
                        try RecipientState(
                            interactionId: interactionId,
                            recipientId: threadId,  // Will be the open group id
                            state: .sending
                        ).insert(db)
                }
                
            default: break
        }
        
    }
    
    }
    
    public func delete(_ db: Database) throws -> Bool {
        // If we have a LinkPreview then check if this is the only interaction that has it
        // and delete the LinkPreview if so
        if linkPreviewUrl != nil {
            let interactionAlias: TableAlias = TableAlias()
            let numInteractions: Int? = try? Interaction
                .aliased(interactionAlias)
                .joining(
                    required: Interaction.linkPreview
                        .filter(literal: [
                            "(ROUND((\(interactionAlias[Columns.timestampMs]) / 1000 / 100000) - 0.5) * 100000)",
                            "=",
                            "\(LinkPreview.Columns.timestamp)"
                        ].joined(separator: " "))
                )
                .fetchCount(db)
            let tmp = try linkPreview.fetchAll(db)
            
            if numInteractions == 1 {
                try linkPreview.deleteAll(db)
            }
        }
        
        return try performDelete(db)
    }
}

// MARK: - Mutation

public extension Interaction {
    func with(
        serverHash: String? = nil,
        authorId: String? = nil,
        timestampMs: Int64? = nil,
        wasRead: Bool? = nil,
        expiresInSeconds: TimeInterval? = nil,
        expiresStartedAtMs: Double? = nil,
        openGroupServerMessageId: Int64? = nil
    ) -> Interaction {
        return Interaction(
            id: id,
            serverHash: (serverHash ?? self.serverHash),
            threadId: threadId,
            authorId: (authorId ?? self.authorId),
            variant: variant,
            body: body,
            timestampMs: (timestampMs ?? self.timestampMs),
            receivedAtTimestampMs: receivedAtTimestampMs,
            wasRead: (wasRead ?? self.wasRead),
            expiresInSeconds: (expiresInSeconds ?? self.expiresInSeconds),
            expiresStartedAtMs: (expiresStartedAtMs ?? self.expiresStartedAtMs),
            linkPreviewUrl: linkPreviewUrl,
            openGroupServerMessageId: (openGroupServerMessageId ?? self.openGroupServerMessageId),
            openGroupWhisperMods: openGroupWhisperMods,
            openGroupWhisperTo: openGroupWhisperTo
        )
    }
}

// MARK: - GRDB Interactions

public extension Interaction {
    /// Immutable version of the `markAsRead(_:includingOlder:trySendReadReceipt:)` function
    func markingAsRead(_ db: Database, includingOlder: Bool, trySendReadReceipt: Bool) throws -> Interaction {
        var updatedInteraction: Interaction = self
        try updatedInteraction.markAsRead(db, includingOlder: includingOlder, trySendReadReceipt: trySendReadReceipt)
        
        return updatedInteraction
    }
    
    /// This will update the `wasRead` state the the interaction
    ///
    /// - Parameters
    ///   - includingOlder: Setting this to `true` will updated the `wasRead` flag for all older interactions as well
    ///   - trySendReadReceipt: Setting this to `true` will schedule a `ReadReceiptJob`
    mutating func markAsRead(_ db: Database, includingOlder: Bool, trySendReadReceipt: Bool) throws {
        // Once all of the below is done schedule the jobs
        func scheduleJobs(interactionIds: [Int64]) {
            // Add the 'DisappearingMessagesJob' if needed - this will update any expiring
            // messages `expiresStartedAtMs` values
            JobRunner.add(
                db,
                job: Job(
                    variant: .disappearingMessages,
                    details: DisappearingMessagesJob.updateNextRunIfNeeded(
                        db,
                        interactionIds: interactionIds,
                        startedAtMs: (Date().timeIntervalSince1970 * 1000)
                    )
                )
            )
            
            // If we want to send read receipts then try to add the 'SendReadReceiptsJob'
            if trySendReadReceipt {
                JobRunner.upsert(
                    db,
                    job: SendReadReceiptsJob.createOrUpdateIfNeeded(
                        db,
                        threadId: threadId,
                        interactionIds: interactionIds
                    )
                )
            }
        }
        
        // If we aren't including older interactions then update and save the current one
        guard includingOlder else {
            let updatedInteraction: Interaction = try self
                .with(wasRead: true)
                .saved(db)
            
            guard let id: Int64 = updatedInteraction.id else { throw GRDBStorageError.objectNotFound }
            
            scheduleJobs(interactionIds: [id])
            return
        }
        
        // Need an id in order to continue
        guard let id: Int64 = self.id else { throw GRDBStorageError.objectNotFound }
        
        let interactionQuery = Interaction
            .filter(Columns.threadId == threadId)
            .filter(Columns.id <= id)
            // The `wasRead` flag doesn't apply to `standardOutgoing` or `standardIncomingDeleted`
            .filter(Columns.variant != Variant.standardOutgoing && Columns.variant != Variant.standardIncomingDeleted)
        
        // Update the `wasRead` flag to true
        try interactionQuery.updateAll(db, Columns.wasRead.set(to: true))
        
        // Retrieve the interaction ids we want to update
        scheduleJobs(
            interactionIds: try Int64.fetchAll(
                db,
                interactionQuery.select(Interaction.Columns.id)
            )
        )
    }
    
    static func markAsRead(_ db: Database, recipientId: String, timestampMsValues: [Double], readTimestampMs: Double) throws {
        guard db[.areReadReceiptsEnabled] == true else { return }
        
        try RecipientState
            .filter(RecipientState.Columns.recipientId == recipientId)
            .joining(
                required: RecipientState.interaction
                    .filter(Columns.variant == Variant.standardOutgoing)
                    .filter(timestampMsValues.contains(Columns.timestampMs))
            )
            .updateAll(
                db,
                RecipientState.Columns.readTimestampMs.set(to: readTimestampMs),
                RecipientState.Columns.state.set(to: RecipientState.State.sent)
            )
    }
}

// MARK: - Convenience

public extension Interaction {
    static let oversizeTextMessageSizeThreshold: UInt = (2 * 1024)
    
    // MARK: - Variables
    
    var isExpiringMessage: Bool {
        guard variant == .standardIncoming || variant == .standardOutgoing else { return false }
        
        return (expiresInSeconds ?? 0 > 0)
    }
    
    var openGroupWhisper: Bool { return (openGroupWhisperMods || (openGroupWhisperTo != nil)) }
    
    var notificationIdentifiers: [String] {
        [
            notificationIdentifier(isBackgroundPoll: true),
            notificationIdentifier(isBackgroundPoll: false)
        ]
    }
    
    // MARK: - Functions
    
    func notificationIdentifier(isBackgroundPoll: Bool) -> String {
        // When the app is in the background we want the notifications to be grouped to prevent spam
        guard isBackgroundPoll else { return threadId }
        
        return "\(threadId)-\(id ?? 0)"
    }
    
    func markingAsDeleted() -> Interaction {
        return Interaction(
            id: id,
            serverHash: nil,
            threadId: threadId,
            authorId: authorId,
            variant: .standardIncomingDeleted,
            body: nil,
            timestampMs: timestampMs,
            receivedAtTimestampMs: receivedAtTimestampMs,
            wasRead: wasRead,
            expiresInSeconds: expiresInSeconds,
            expiresStartedAtMs: expiresStartedAtMs,
            linkPreviewUrl: linkPreviewUrl,
            openGroupServerMessageId: openGroupServerMessageId,
            openGroupWhisperMods: openGroupWhisperMods,
            openGroupWhisperTo: openGroupWhisperTo
        )
    }
    
    func isUserMentioned(_ db: Database) -> Bool {
        guard variant == .standardIncoming else { return false }
        
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        return (
            (
                body != nil &&
                (body ?? "").contains("@\(userPublicKey)")
            ) || (
                (try? quote.fetchOne(db))?.authorId == userPublicKey
            )
        )
    }
    
    func previewText(_ db: Database) -> String {
        switch variant {
            case .standardIncomingDeleted: return ""
                
            case .standardIncoming, .standardOutgoing:
                var bodyDescription: String?
                
                if let body: String = self.body, !body.isEmpty {
                    bodyDescription = body
                }
                
                if bodyDescription == nil {
                    let maybeTextAttachment: Attachment? = try? attachments
                        .filter(Attachment.Columns.contentType == OWSMimeTypeOversizeTextMessage)
                        .fetchOne(db)
                    
                    if
                        let attachment: Attachment = maybeTextAttachment,
                        attachment.state == .downloaded,
                        let filePath: String = attachment.originalFilePath,
                        let data: Data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                        let dataString: String = String(data: data, encoding: .utf8)
                    {
                        bodyDescription = dataString.filterForDisplay
                    }
                }
                
                var attachmentDescription: String?
                let maybeMediaAttachment: Attachment? = try? attachments
                    .filter(Attachment.Columns.contentType != OWSMimeTypeOversizeTextMessage)
                    .fetchOne(db)
                
                if let attachment: Attachment = maybeMediaAttachment {
                    attachmentDescription = attachment.description
                }
                
                if
                    let attachmentDescription: String = attachmentDescription,
                    let bodyDescription: String = bodyDescription,
                    !attachmentDescription.isEmpty,
                    !bodyDescription.isEmpty
                {
                    if CurrentAppContext().isRTL {
                        return "\(bodyDescription): \(attachmentDescription)"
                    }
                    
                    return "\(attachmentDescription): \(bodyDescription)"
                }
                
                if let bodyDescription: String = bodyDescription, !bodyDescription.isEmpty {
                    return bodyDescription
                }
                
                if let attachmentDescription: String = attachmentDescription, !attachmentDescription.isEmpty {
                    return attachmentDescription
                }
                
                if let linkPreview: LinkPreview = try? linkPreview.fetchOne(db), linkPreview.variant == .openGroupInvitation {
                    return "😎 Open group invitation"
                }
                
                // TODO: We should do better here
                return ""
                
            case .infoMediaSavedNotification:
                // Note: This should only occur in 'contact' threads so the `threadId`
                // is the contact id
                let displayName: String = Profile.displayName(id: threadId)
                
                // TODO: Use referencedAttachmentTimestamp to tell the user * which * media was saved
                return String(format: "media_saved".localized(), displayName)
                
            case .infoScreenshotNotification:
                // Note: This should only occur in 'contact' threads so the `threadId`
                // is the contact id
                let displayName: String = Profile.displayName(id: threadId)
                
                return String(format: "screenshot_taken".localized(), displayName)
                
            case .infoClosedGroupCreated: return "GROUP_CREATED".localized()
            case .infoClosedGroupCurrentUserLeft: return "GROUP_YOU_LEFT".localized()
            case .infoClosedGroupUpdated: return (body ?? "GROUP_UPDATED".localized())
            case .infoMessageRequestAccepted: return (body ?? "MESSAGE_REQUESTS_ACCEPTED".localized())
            
            case .infoDisappearingMessagesUpdate:
                // TODO: We should do better here
                return (body ?? "")
        }
    }
    
    func state(_ db: Database) throws -> RecipientState.State {
        let states: [RecipientState.State] = try recipientStates
            .fetchAll(db)
            .map { $0.state }
        var hasFailed: Bool = false
        
        for state in states {
            switch state {
                // If there are any "sending" recipients, consider this message "sending"
                case .sending: return .sending
                    
                case .failed:
                    hasFailed = true
                    break
                    
                default: break
            }
        }
        
        // If there are any "failed" recipients, consider this message "failed"
        guard !hasFailed else { return .failed }
        
        // Otherwise, consider the message "sent"
        //
        // Note: This includes messages with no recipients
        return .sent
    }
}
