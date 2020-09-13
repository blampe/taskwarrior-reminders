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

    public func taskwarriorChanged(event: EonilFSEventsEvent) {
        let secondsBetween = (Date().timeIntervalSince1970 - self.lastModifiedDate.timeIntervalSince1970).magnitude
        if secondsBetween < 1 {
            return
        }

        let tasks = tw.tasksModifiedSince(date: self.lastModifiedDate)
        tasks.forEach({task in
            print("[Taskwarrior ▶ Reminders]", task.uniqueID)
            let syncTask = self.repo.upsertToReminders(task: task)
            self.lastModifiedDate = max(self.lastModifiedDate, task.lastModified ?? self.lastModifiedDate)
            if task.reminderID == nil {
                self.tw.upsertToTaskwarrior(syncTask)
            }
        })
        self.defaults.set(self.lastModifiedDate, forKey: "lastModifiedDate")
    }

    public init(_ repo: RemindersRepository, syncSince: Date = Date()) {
        // TODO read TW config path instead of hard coding
        self.repo = repo
        self.repo.assertAuthorized()
        self.tw = TaskwarriorRepository.init()
        self.tw.syncWithTaskd()
        self.lastModifiedDate = syncSince
        self.defaults = UserDefaults.standard
        try! EonilFSEvents.startWatching(
            paths: [NSString(string: "~/.task/").expandingTildeInPath],
        for: ObjectIdentifier(self),
        with: self.taskwarriorChanged)
    }
}
