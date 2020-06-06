//
//  RemindersObserver.swift
//  
//
//  Created by Bryce Lampe on 1/1/20.
//

import Foundation
import Repositories
import EventKit

public class RemindersObserver {
    private var lastModifiedDate: Date
    private var knownReminderIDs: Set<String> = []
    private let repo: RemindersRepository
    private let tw: TaskwarriorRepository

    @objc
    public func storeChanged(notification: Notification) {
        var nextModifiedDate = lastModifiedDate

        var newKnownReminderIds = Set<String>()

        let allReminders = self.repo.fetchAllReminders()
        allReminders.forEach({ reminder in
            // Don't want to refresh here beacuse it triggers another
            // notification to the observer, but if we don't then we
            // potentially write stale data back to TW...
            newKnownReminderIds.insert(reminder.calendarItemIdentifier)
            if reminder.lastModifiedDate ?? Date() < self.lastModifiedDate {
                return
            }
            nextModifiedDate = max(nextModifiedDate, reminder.lastModifiedDate!)
            DispatchQueue.main.async(
                execute: {
                    print("[Reminders ▶ Taskwarrior]", reminder.title ?? "")
                    self.tw.upsertToTaskwarrior(
                        self.repo.fetchReminderTask(
                            reminder.calendarItemIdentifier
                        )
                    )
            }
            )
        })

        let deletedReminderIDs = self.knownReminderIDs.subtracting(newKnownReminderIds)

        for reminderID in deletedReminderIDs {
            DispatchQueue.main.async(
                execute: {
                    print("[Reminders ▶ Taskwarrior]")
                    let taskToDelete = self.tw.fetchTaskwarriorTask(
                        filter: "reminderID:" + reminderID
                    )
                    if taskToDelete != nil {
                        self.tw.deleteFromTaskwarrior(taskToDelete!)
                    }
                }
            )
        }

        self.lastModifiedDate = nextModifiedDate
        self.knownReminderIDs = newKnownReminderIds
    }

    public init(_ repo: RemindersRepository, syncSince: Date = Date()) {
        self.repo = repo
        self.repo.assertAuthorized()
        self.tw = TaskwarriorRepository.init()
        self.lastModifiedDate = syncSince
    }
}
