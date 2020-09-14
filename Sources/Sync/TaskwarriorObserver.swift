//
//  TaskwarriorObserver.swift
//
//
//  Created by Bryce Lampe on 1/1/20.
//

import EonilFSEvents
import Foundation
import Repositories

public class TaskwarriorObserver {
    private var tw: TaskwarriorRepository
    private var repo: RemindersRepository
    private var lastModifiedDate: Date
    private var defaults: UserDefaults
    private var lock: DispatchSemaphore

    public func taskwarriorChanged(event: EonilFSEventsEvent) {
        if self.lock.wait(timeout: DispatchTime.now() + 1) == .timedOut {
            // Reminders is updating things, don't step on it
            return
        }
        let tasks = tw.tasksModifiedSince(date: self.lastModifiedDate)
        tasks.forEach({task in
            print("[Taskwarrior ▶ Reminders]", task.uniqueID)
            let syncResult = self.repo.upsertToReminders(task: task)
            if !syncResult.madeChanges {
                return
            }
            self.lastModifiedDate = max(self.lastModifiedDate, task.lastModified ?? self.lastModifiedDate)
            if task.reminderID == nil {
                self.tw.upsertToTaskwarrior(syncResult.task)
            }
        })
        self.lock.signal()
        self.defaults.set(self.lastModifiedDate, forKey: "lastModifiedDate")
    }

    public init(_ repo: RemindersRepository, syncSince: Date = Date(), lock: DispatchSemaphore) {
        // TODO read TW config path instead of hard coding
        self.repo = repo
        self.repo.assertAuthorized()
        self.tw = TaskwarriorRepository.init()
        self.tw.syncWithTaskd()
        self.lastModifiedDate = syncSince
        self.defaults = UserDefaults.standard
        self.lock = lock
        try! EonilFSEvents.startWatching(
            paths: [NSString(string: "~/.task/").expandingTildeInPath],
        for: ObjectIdentifier(self),
        with: self.taskwarriorChanged)
    }
}
