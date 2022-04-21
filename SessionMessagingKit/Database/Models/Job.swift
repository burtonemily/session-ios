// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit
import SwiftProtobuf

public struct Job: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "job" }
    internal static let threadForeignKey = ForeignKey(
        [Columns.threadId],
        to: [Interaction.Columns.threadId]
    )
    internal static let thread = hasOne(SessionThread.self, using: Job.threadForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case failureCount
        case variant
        case behaviour
        case nextRunTimestamp
        case threadId
        case details
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        /// This is a recurring job that handles the removal of disappearing messages and is triggered
        /// at the timestamp of the next disappearing message
        case disappearingMessages
        
        
        /// This is a recurring job that runs on launch and flags any messages marked as 'sending' to
        /// be in their 'failed' state
        case failedMessages = 1000
        
        /// This is a recurring job that runs on launch and flags any attachments marked as 'uploading' to
        /// be in their 'failed' state
        case failedAttachmentDownloads
        
        /// This is a recurring job that runs on return from background and registeres and uploads the
        /// latest device push tokens
        case syncPushTokens = 2000
        
        /// This is a job that runs once whenever a message is sent to notify the push notification server
        /// about the message
        case notifyPushServer
        
        /// This is a job that runs once at most every 3 seconds per thread whenever a message is marked as read
        /// (if read receipts are enabled) to notify other members in a conversation that their message was read
        case sendReadReceipts
        
        /// This is a job that runs once whenever a message is received to attempt to decode and properly
        /// process the message
        case messageReceive = 3000
        
        /// This is a job that runs once whenever a message is sent to attempt to encode and properly
        /// send the message
        case messageSend
        
        /// This is a job that runs once whenever an attachment is uploaded to attempt to encode and properly
        /// upload the attachment
        case attachmentUpload
        
        /// This is a job that runs once whenever an attachment is downloaded to attempt to decode and properly
        /// download the attachment
        case attachmentDownload
    }
    
    public enum Behaviour: Int, Codable, DatabaseValueConvertible {
        /// This job will run once and then be removed from the jobs table
        case runOnce
        
        /// This job will run once the next time the app launches and then be removed from the jobs table
        case runOnceNextLaunch
        
        /// This job will run and then will be updated with a new `nextRunTimestamp` (at least 1 second in
        /// the future) in order to be run again
        case recurring
        
        /// This job will run once each launch
        case recurringOnLaunch
        
        /// This job will run once each whenever the app becomes active (launch and return from background)
        case recurringOnActive
    }
    
    /// The `id` value is auto incremented by the database, if the `Job` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// A counter for the number of times this job has failed
    public let failureCount: UInt
    
    /// The type of job
    public let variant: Variant
    
    /// The type of job
    public let behaviour: Behaviour
    
    /// Seconds since epoch to indicate the next datetime that this job should run
    public let nextRunTimestamp: TimeInterval
    
    /// The id of the thread this job is associated with
    ///
    /// **Note:** This will only be populated for Jobs associated to threads
    public let threadId: String?
    
    /// JSON encoded data required for the job
    public let details: Data?
    
    // MARK: - Relationships
    
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: Job.thread)
    }
    
    // MARK: - Initialization
    
    fileprivate init(
        id: Int64?,
        failureCount: UInt,
        variant: Variant,
        behaviour: Behaviour,
        nextRunTimestamp: TimeInterval,
        threadId: String?,
        details: Data?
    ) {
        self.id = id
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.details = details
    }
    
    public init(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil
    ) {
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.details = nil
    }
    
    public init?<T: Encodable>(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil,
        details: T? = nil
    ) {
        let detailsData: Data?
        
        if let details: T = details {
            guard let encodedDetails: Data = try? JSONEncoder().encode(details) else { return nil }
            
            detailsData = encodedDetails
        }
        else {
            detailsData = nil
        }
        
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.details = detailsData
    }
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

// MARK: - Convenience

public extension Job {
    internal func with(
        failureCount: UInt = 0,
        nextRunTimestamp: TimeInterval?
    ) -> Job {
        return Job(
            id: id,
            failureCount: failureCount,
            variant: variant,
            behaviour: behaviour,
            nextRunTimestamp: (nextRunTimestamp ?? self.nextRunTimestamp),
            threadId: threadId,
            details: details
        )
    }
    
    internal func with<T: Encodable>(details: T) -> Job? {
        guard let detailsData: Data = try? JSONEncoder().encode(details) else { return nil }
        
        return Job(
            id: id,
            failureCount: failureCount,
            variant: variant,
            behaviour: behaviour,
            nextRunTimestamp: nextRunTimestamp,
            threadId: threadId,
            details: detailsData
        )
    }
}
