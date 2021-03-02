import SignalCoreKit

extension MessageReceiver {

    internal static func isBlocked(_ publicKey: String) -> Bool {
        return SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
    }

    public static func handle(_ message: Message, associatedWithProto proto: SNProtoContent, openGroupID: String?, isBackgroundPoll: Bool, using transaction: Any) throws {
        switch message {
        case let message as ReadReceipt: handleReadReceipt(message, using: transaction)
        case let message as TypingIndicator: handleTypingIndicator(message, using: transaction)
        case let message as ClosedGroupControlMessage: handleClosedGroupControlMessage(message, using: transaction)
        case let message as DataExtractionNotification: handleDataExtractionNotification(message, using: transaction)
        case let message as ExpirationTimerUpdate: handleExpirationTimerUpdate(message, using: transaction)
        case let message as ConfigurationMessage: handleConfigurationMessage(message, using: transaction)
        case let message as VisibleMessage: try handleVisibleMessage(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction)
        default: fatalError()
        }
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        guard isMainAppAndActive else { return }
        // Touch the thread to update the home screen preview
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let threadID = storage.getOrCreateThread(for: message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
        thread.touch(with: transaction)
    }

    
    
    // MARK: - Read Receipts
    
    private static func handleReadReceipt(_ message: ReadReceipt, using transaction: Any) {
        SSKEnvironment.shared.readReceiptManager.processReadReceipts(fromRecipientId: message.sender!, sentTimestamps: message.timestamps!.map { NSNumber(value: $0) }, readTimestamp: message.receivedTimestamp!)
    }

    
    
    // MARK: - Typing Indicators
    
    private static func handleTypingIndicator(_ message: TypingIndicator, using transaction: Any) {
        switch message.kind! {
        case .started: showTypingIndicatorIfNeeded(for: message.sender!)
        case .stopped: hideTypingIndicatorIfNeeded(for: message.sender!)
        }
    }

    public static func showTypingIndicatorIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func showTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStartedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            showTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                showTypingIndicatorsIfNeeded()
            }
        }
    }

    public static func hideTypingIndicatorIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func hideTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStoppedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            hideTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                hideTypingIndicatorsIfNeeded()
            }
        }
    }

    public static func cancelTypingIndicatorsIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func cancelTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveIncomingMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            cancelTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                cancelTypingIndicatorsIfNeeded()
            }
        }
    }
    
    
    
    // MARK: - Data Extraction Notification
    
    private static func handleDataExtractionNotification(_ message: DataExtractionNotification, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard message.groupPublicKey == nil,
            let thread = TSContactThread.getWithContactId(message.sender!, transaction: transaction) else { return }
        // TODO: Handle media saved type notifications
        let message = DataExtractionNotificationInfoMessage(type: .screenshotNotification, sentTimestamp: message.sentTimestamp!, thread: thread, referencedAttachmentTimestamp: nil)
        message.save(with: transaction)
    }
    
    
    
    // MARK: - Expiration Timers

    private static func handleExpirationTimerUpdate(_ message: ExpirationTimerUpdate, using transaction: Any) {
        if message.duration! > 0 {
            setExpirationTimer(to: message.duration!, for: message.sender!, syncTarget: message.syncTarget, groupPublicKey: message.groupPublicKey, messageSentTimestamp: message.sentTimestamp!, using: transaction)
        } else {
            disableExpirationTimer(for: message.sender!, syncTarget: message.syncTarget, groupPublicKey: message.groupPublicKey, messageSentTimestamp: message.sentTimestamp!, using: transaction)
        }
    }

    public static func setExpirationTimer(to duration: UInt32, for senderPublicKey: String, syncTarget: String?, groupPublicKey: String?, messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactId(syncTarget ?? senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: true, durationSeconds: duration)
        configuration.save(with: transaction)
        let senderDisplayName = Storage.shared.getContact(with: senderPublicKey)?.displayName(for: .regular) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: messageSentTimestamp, thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    public static func disableExpirationTimer(for senderPublicKey: String, syncTarget: String?, groupPublicKey: String?, messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactId(syncTarget ?? senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: false, durationSeconds: 24 * 60 * 60)
        configuration.save(with: transaction)
        let senderDisplayName = Storage.shared.getContact(with: senderPublicKey)?.displayName(for: .regular) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: messageSentTimestamp, thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }
    
    
    
    // MARK: - Configuration Messages
    
    private static func handleConfigurationMessage(_ message: ConfigurationMessage, using transaction: Any) {
        guard message.sender == getUserHexEncodedPublicKey() else { return }
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let userDefaults = UserDefaults.standard
        // Profile
        let userProfile = storage.getUserProfile(using: transaction)
        if let displayName = message.displayName {
            let shouldUpdate = given(userDefaults[.lastDisplayNameUpdate]) { message.sentTimestamp! > UInt64($0.timeIntervalSince1970 * 1000) } ?? true
            if shouldUpdate {
                userProfile.profileName = displayName
                userDefaults[.lastDisplayNameUpdate] = Date(timeIntervalSince1970: TimeInterval(message.sentTimestamp! / 1000))
            }
        }
        if let profilePictureURL = message.profilePictureURL, let profileKeyAsData = message.profileKey {
            let shouldUpdate = given(userDefaults[.lastProfilePictureUpdate]) { message.sentTimestamp! > UInt64($0.timeIntervalSince1970 * 1000) } ?? true
            if shouldUpdate {
                userProfile.avatarUrlPath = profilePictureURL
                userProfile.profileKey = OWSAES256Key(data: profileKeyAsData)
                userDefaults[.lastProfilePictureUpdate] = Date(timeIntervalSince1970: TimeInterval(message.sentTimestamp! / 1000))
            }
        }
        userProfile.save(with: transaction)
        transaction.addCompletionQueue(DispatchQueue.main) {
            SSKEnvironment.shared.profileManager.downloadAvatar(for: userProfile)
        }
        // Initial configuration sync
        if !UserDefaults.standard[.hasSyncedInitialConfiguration] {
            UserDefaults.standard[.hasSyncedInitialConfiguration] = true
            NotificationCenter.default.post(name: .initialConfigurationMessageReceived, object: nil)
            // Contacts
            for contact in message.contacts {
                let sessionID = contact.publicKey!
                let userProfile = OWSUserProfile.getOrBuild(forRecipientId: sessionID, transaction: transaction)
                userProfile.profileKey = given(contact.profileKey) { OWSAES256Key(data: $0)! }
                userProfile.avatarUrlPath = contact.profilePictureURL
                userProfile.profileName = contact.displayName
                userProfile.save(with: transaction)
                let thread = TSContactThread.getOrCreateThread(withContactId: sessionID, transaction: transaction)
                thread.shouldThreadBeVisible = true
                thread.save(with: transaction)
            }
            // Closed groups
            let allClosedGroupPublicKeys = storage.getUserClosedGroupPublicKeys()
            for closedGroup in message.closedGroups {
                guard !allClosedGroupPublicKeys.contains(closedGroup.publicKey) else { continue }
                handleNewClosedGroup(groupPublicKey: closedGroup.publicKey, name: closedGroup.name, encryptionKeyPair: closedGroup.encryptionKeyPair,
                    members: [String](closedGroup.members), admins: [String](closedGroup.admins), messageSentTimestamp: message.sentTimestamp!, using: transaction)
            }
            // Open groups
            let allOpenGroups = Set(storage.getAllUserOpenGroups().keys)
            for openGroupURL in message.openGroups {
                guard !allOpenGroups.contains(openGroupURL) else { continue }
                OpenGroupManager.shared.add(with: openGroupURL, using: transaction).retainUntilComplete()
            }
        }
    }
    
    
    
    // MARK: - Visible Messages

    @discardableResult
    public static func handleVisibleMessage(_ message: VisibleMessage, associatedWithProto proto: SNProtoContent, openGroupID: String?, isBackgroundPoll: Bool, using transaction: Any) throws -> String {
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        // Parse & persist attachments
        let attachments: [VisibleMessage.Attachment] = proto.dataMessage!.attachments.compactMap { proto in
            guard let attachment = VisibleMessage.Attachment.fromProto(proto) else { return nil }
            return attachment.isValid ? attachment : nil
        }
        let attachmentIDs = storage.persist(attachments, using: transaction)
        message.attachmentIDs = attachmentIDs
        var attachmentsToDownload = attachmentIDs
        // Update profile if needed
        if let newProfile = message.profile {
            let profileManager = SSKEnvironment.shared.profileManager
            let sessionID = message.sender!
            let oldProfile = OWSUserProfile.fetch(uniqueId: sessionID, transaction: transaction)
            let contact = Storage.shared.getContact(with: sessionID) ?? Contact(sessionID: sessionID)
            if let displayName = newProfile.displayName, displayName != oldProfile?.profileName {
                profileManager.updateProfileForContact(withID: sessionID, displayName: displayName, with: transaction)
                contact.name = displayName
            }
            if let profileKey = newProfile.profileKey, let profilePictureURL = newProfile.profilePictureURL, profileKey.count == kAES256_KeyByteLength,
                profileKey != oldProfile?.profileKey?.keyData {
                profileManager.setProfileKeyData(profileKey, forRecipientId: sessionID, avatarURL: profilePictureURL)
                contact.profilePictureURL = profilePictureURL
                contact.profilePictureEncryptionKey = OWSAES256Key(data: profileKey)
            }
            if let rawDisplayName = newProfile.displayName, let openGroupID = openGroupID {
                let endIndex = sessionID.endIndex
                let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
                let displayName = "\(rawDisplayName) (...\(sessionID[cutoffIndex..<endIndex]))"
                Storage.shared.setOpenGroupDisplayName(to: displayName, for: sessionID, inOpenGroupWithID: openGroupID, using: transaction)
            }
        }
        // Get or create thread
        guard let threadID = storage.getOrCreateThread(for: message.syncTarget ?? message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
        // Parse quote if needed
        var tsQuotedMessage: TSQuotedMessage? = nil
        if message.quote != nil && proto.dataMessage?.quote != nil, let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) {
            tsQuotedMessage = TSQuotedMessage(for: proto.dataMessage!, thread: thread, transaction: transaction)
            if let id = tsQuotedMessage?.thumbnailAttachmentStreamId() ?? tsQuotedMessage?.thumbnailAttachmentPointerId() {
                attachmentsToDownload.append(id)
            }
        }
        // Parse link preview if needed
        var owsLinkPreview: OWSLinkPreview?
        if message.linkPreview != nil && proto.dataMessage?.preview.isEmpty == false {
            owsLinkPreview = try? OWSLinkPreview.buildValidatedLinkPreview(dataMessage: proto.dataMessage!, body: message.text, transaction: transaction)
            if let id = owsLinkPreview?.imageAttachmentId {
                attachmentsToDownload.append(id)
            }
        }
        // Persist the message
        guard let tsMessageID = storage.persist(message, quotedMessage: tsQuotedMessage, linkPreview: owsLinkPreview,
            groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
        message.threadID = threadID
        // Start attachment downloads if needed
        attachmentsToDownload.forEach { attachmentID in
            let downloadJob = AttachmentDownloadJob(attachmentID: attachmentID, tsMessageID: tsMessageID)
            if isMainAppAndActive {
                JobQueue.shared.add(downloadJob, using: transaction)
            } else {
                JobQueue.shared.addWithoutExecuting(downloadJob, using: transaction)
            }
        }
        // Cancel any typing indicators if needed
        if isMainAppAndActive {
            cancelTypingIndicatorsIfNeeded(for: message.sender!)
        }
        // Keep track of the open group server message ID ↔ message ID relationship
        if let serverID = message.openGroupServerMessageID {
            storage.setIDForMessage(withServerID: serverID, to: tsMessageID, using: transaction)
        }
        // Notify the user if needed
        guard (isMainAppAndActive || isBackgroundPoll), let tsIncomingMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) as? TSIncomingMessage,
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return tsMessageID }
        SSKEnvironment.shared.notificationsManager!.notifyUser(for: tsIncomingMessage, in: thread, transaction: transaction)
        return tsMessageID
    }

    
    
    // MARK: - Closed Groups
    private static func handleClosedGroupControlMessage(_ message: ClosedGroupControlMessage, using transaction: Any) {
        switch message.kind! {
        case .new: handleNewClosedGroup(message, using: transaction)
        case .encryptionKeyPair: handleClosedGroupEncryptionKeyPair(message, using: transaction)
        case .nameChange: handleClosedGroupNameChanged(message, using: transaction)
        case .membersAdded: handleClosedGroupMembersAdded(message, using: transaction)
        case .membersRemoved: handleClosedGroupMembersRemoved(message, using: transaction)
        case .memberLeft: handleClosedGroupMemberLeft(message, using: transaction)
        case .encryptionKeyPairRequest: handleClosedGroupEncryptionKeyPairRequest(message, using: transaction)
        }
    }
    
    private static func handleNewClosedGroup(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .new(publicKeyAsData, name, encryptionKeyPair, membersAsData, adminsAsData) = message.kind else { return }
        let groupPublicKey = publicKeyAsData.toHexString()
        let members = membersAsData.map { $0.toHexString() }
        let admins = adminsAsData.map { $0.toHexString() }
        handleNewClosedGroup(groupPublicKey: groupPublicKey, name: name, encryptionKeyPair: encryptionKeyPair,
            members: members, admins: admins, messageSentTimestamp: message.sentTimestamp!, using: transaction)
    }

    private static func handleNewClosedGroup(groupPublicKey: String, name: String, encryptionKeyPair: ECKeyPair, members: [String], admins: [String], messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Create the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread: TSGroupThread
        if let t = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) {
            thread = t
            thread.setGroupModel(group, with: transaction)
        } else {
            thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
            thread.save(with: transaction)
            // Notify the user
            let infoMessage = TSInfoMessage(timestamp: messageSentTimestamp, in: thread, messageType: .groupUpdate)
            infoMessage.save(with: transaction)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
        // Store the key pair
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Store the formation timestamp
        Storage.shared.setClosedGroupFormationTimestamp(to: messageSentTimestamp, for: groupPublicKey, using: transaction)
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
    }

    private static func handleClosedGroupEncryptionKeyPair(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .encryptionKeyPair(explicitGroupPublicKey, wrappers) = message.kind,
            let groupPublicKey = explicitGroupPublicKey?.toHexString() ?? message.groupPublicKey else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let userPublicKey = getUserHexEncodedPublicKey()
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
            return SNLog("Couldn't find user X25519 key pair.")
        }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Ignoring closed group encryption key pair for nonexistent group.")
        }
        guard thread.groupModel.groupMemberIds.contains(message.sender!) else {
            return SNLog("Ignoring closed group encryption key pair from non-member.")
        }
        // Find our wrapper and decrypt it if possible
        guard let wrapper = wrappers.first(where: { $0.publicKey == userPublicKey }), let encryptedKeyPair = wrapper.encryptedKeyPair else { return }
        let plaintext: Data
        do {
            plaintext = try MessageReceiver.decryptWithSessionProtocol(ciphertext: encryptedKeyPair, using: userKeyPair).plaintext
        } catch {
            return SNLog("Couldn't decrypt closed group encryption key pair.")
        }
        // Parse it
        let proto: SNProtoKeyPair
        do {
            proto = try SNProtoKeyPair.parseData(plaintext)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        let keyPair: ECKeyPair
        do {
            keyPair = try ECKeyPair(publicKeyData: proto.publicKey.removing05PrefixIfNeeded(), privateKeyData: proto.privateKey)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        // Store it if needed
        let closedGroupEncryptionKeyPairs = Storage.shared.getClosedGroupEncryptionKeyPairs(for: groupPublicKey)
        guard !closedGroupEncryptionKeyPairs.contains(keyPair) else {
            return SNLog("Ignoring duplicate closed group encryption key pair.")
        }
        Storage.shared.addClosedGroupEncryptionKeyPair(keyPair, for: groupPublicKey, using: transaction)
        SNLog("Received a new closed group encryption key pair.")
    }
    
    private static func handleClosedGroupNameChanged(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .nameChange(name) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Update the group
            let newGroupModel = TSGroupModel(title: name, memberIds: group.groupMemberIds, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard name != group.groupName else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMembersAdded(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersAdded(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Update the group
            let members = Set(group.groupMemberIds).union(membersAsData.map { $0.toHexString() })
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Send the latest encryption key pair to the added members if the current user is the admin of the group
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if isCurrentUserAdmin {
                for member in membersAsData.map({ $0.toHexString() }) {
                    MessageSender.sendLatestEncryptionKeyPair(to: member, for: message.groupPublicKey!, using: transaction)
                }
            }
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
 
    private static func handleClosedGroupMembersRemoved(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersRemoved(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Check that the admin wasn't removed
            let members = Set(group.groupMemberIds).subtracting(membersAsData.map { $0.toHexString() })
            guard members.contains(group.groupAdminIds.first!) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // If the current user was removed:
            // • Stop polling for the group
            // • Remove the key pairs associated with the group
            // • Notify the PN server
            let userPublicKey = getUserHexEncodedPublicKey()
            let wasCurrentUserRemoved = !members.contains(userPublicKey)
            if wasCurrentUserRemoved {
                Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            }
            // Generate and distribute a new encryption key pair if needed
            // NOTE: If we're the admin we can be sure at this point that we weren't removed
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if isCurrentUserAdmin {
                do {
                    try MessageSender.generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: Set(members), using: transaction)
                } catch {
                    SNLog("Couldn't distribute new encryption key pair.")
                }
            }
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let infoMessageType: TSInfoMessageType = wasCurrentUserRemoved ? .groupQuit : .groupUpdate
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: infoMessageType, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMemberLeft(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case .memberLeft = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            let didAdminLeave = group.groupAdminIds.contains(message.sender!)
            let members: Set<String> = didAdminLeave ? [] : Set(group.groupMemberIds).subtracting([ message.sender! ]) // If the admin leaves the group is disbanded
            let userPublicKey = getUserHexEncodedPublicKey()
            let isCurrentUserAdmin = group.groupAdminIds.contains(userPublicKey)
            // If a regular member left:
            // • Distribute a new encryption key pair if we're the admin of the group
            // If the admin left:
            // • Don't distribute a new encryption key pair
            // • Unsubscribe from PNs, delete the group public key, etc. as the group will be disbanded
            if didAdminLeave {
                // Remove the group from the database and unsubscribe from PNs
                Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            } else if isCurrentUserAdmin {
                // Generate and distribute a new encryption key pair if needed
                do {
                    try MessageSender.generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: members, using: transaction)
                } catch {
                    SNLog("Couldn't distribute new encryption key pair.")
                }
            }
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupEncryptionKeyPairRequest(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case .encryptionKeyPairRequest = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, _, group in
            let publicKey = message.sender!
            // Guard against self-sends
            guard publicKey != getUserHexEncodedPublicKey() else {
                return SNLog("Ignoring invalid closed group update.")
            }
            MessageSender.sendLatestEncryptionKeyPair(to: publicKey, for: groupPublicKey, using: transaction)
        }
    }
    
    private static func performIfValid(for message: ClosedGroupControlMessage, using transaction: Any, _ update: (Data, TSGroupThread, TSGroupModel) -> Void) {
        // Prepare
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Get the group
        guard let groupPublicKey = message.groupPublicKey else { return }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Ignoring closed group update for nonexistent group.")
        }
        let group = thread.groupModel
        // Check that the message isn't from before the group was created
        if let formationTimestamp = Storage.shared.getClosedGroupFormationTimestamp(for: groupPublicKey) {
            guard message.sentTimestamp! > formationTimestamp else {
                return SNLog("Ignoring closed group update from before thread was created.")
            }
        }
        // Check that the sender is a member of the group
        guard Set(group.groupMemberIds).contains(message.sender!) else {
            return SNLog("Ignoring closed group update from non-member.")
        }
        // Perform the update
        update(groupID, thread, group)
    }
}
