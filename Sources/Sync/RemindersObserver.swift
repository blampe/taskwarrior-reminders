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
    private var lock: DispatchSemaphore

    @objc
    public func storeChanged(notification: Notification) {
        if self.lock.wait(timeout: DispatchTime.now() + 1) == .timedOut {
            // TW is currently updating Reminders, don't step on it.
            return
        }

        var nextModifiedDate = lastModifiedDate

        var newKnownReminderIds = Set<String>()

        let allReminders = self.repo.fetchAllReminders()
        allReminders.forEach({ reminder in
            // Don't want to refresh here beacuse it triggers another
            // notification to the observer, but if we don't then we
            // potentially write stale data back to TW...
            newKnownReminderIds.insert(reminder.calendarItemIdentifier)
            if reminder.lastModifiedDate! < self.lastModifiedDate {
                return
            }
            nextModifiedDate = max(nextModifiedDate, reminder.lastModifiedDate!)
            DispatchQueue.main.async(
                execute: {
                    print("[Reminders ▶ Taskwarrior]", reminder.title ?? "")
                    let syncResult = self.tw.upsertToTaskwarrior(
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
                    let taskToDelete = self.tw.fetchTaskwarriorTask(
                        filter: "reminderID:" + reminderID
                    )
                    if taskToDelete != nil {
                        print("[Reminders ▶ Taskwarrior]")
                        self.tw.deleteFromTaskwarrior(taskToDelete!)
                    }
                }
            )
        }
        self.lock.signal()
        self.lastModifiedDate = nextModifiedDate
        self.knownReminderIDs = newKnownReminderIds
    }

    public init(_ repo: RemindersRepository, syncSince: Date = Date(), lock: DispatchSemaphore) {
        self.repo = repo
        self.repo.assertAuthorized()
        self.tw = TaskwarriorRepository.init()
        self.lastModifiedDate = syncSince
        self.lock = lock
    }
}
