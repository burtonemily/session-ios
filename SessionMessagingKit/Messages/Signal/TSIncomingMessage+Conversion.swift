
public extension TSIncomingMessage {

    static func from(_ visibleMessage: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, associatedWith thread: TSThread) -> TSIncomingMessage {
        let sender = visibleMessage.sender!
        var expiration: UInt32 = 0
        Storage.read { transaction in
            expiration = thread.disappearingMessagesDuration(with: transaction)
        }
        let openGroupServerMessageId = visibleMessage.openGroupServerMessageId ?? 0
        let isOpenGroupMessage = (openGroupServerMessageId != 0)
        let result = TSIncomingMessage(
            timestamp: visibleMessage.sentTimestamp!,
            in: thread,
            authorId: sender,
            sourceDeviceId: 1,
            messageBody: visibleMessage.text,
            attachmentIds: visibleMessage.attachmentIds,
            expiresInSeconds: !isOpenGroupMessage ? expiration : 0, // Ensure we don't ever expire open group messages
            quotedMessage: quotedMessage,
            linkPreview: linkPreview,
            wasReceivedByUD: true,
            openGroupInvitationName: visibleMessage.openGroupInvitation?.name,
            openGroupInvitationURL: visibleMessage.openGroupInvitation?.url,
            serverHash: visibleMessage.serverHash
        )
        result.openGroupServerMessageID = openGroupServerMessageId
        return result
    }
}
