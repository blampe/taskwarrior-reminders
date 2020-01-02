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

    public func taskwarriorChanged(event: EonilFSEventsEvent) {
        let now = Date()
        let secondsBetween = (now.timeIntervalSince1970 - lastModifiedDate.timeIntervalSince1970).magnitude
        if secondsBetween < 1 {
            return
        }

        let tasks = tw.tasksModifiedSince(date: lastModifiedDate)
        tasks.forEach({task in
            print("[Taskwarrior ▶ Reminders]", task.uniqueID)
            let syncTask = self.repo.upsertToReminders(task: task)
            if task.reminderID == nil {
                self.tw.upsertToTaskwarrior(syncTask)
            }
        })
        self.lastModifiedDate = now
    }

    public init(_ repo: RemindersRepository, syncSince: Date = Date()) {
        // TODO read TW config path instead of hard coding
        self.repo = repo
        self.repo.assertAuthorized()
        self.tw = TaskwarriorRepository.init()
        self.lastModifiedDate = syncSince
        try! EonilFSEvents.startWatching(
            paths: [NSString(string: "~/.task/").expandingTildeInPath],
        for: ObjectIdentifier(self),
        with: self.taskwarriorChanged)
    }
}
