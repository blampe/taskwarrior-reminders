//
//  main.swift
//
//  Reads a Taskwarrior task in JSON format from stdin, and synchronizes the
//  task with Reminders.
//
//  The resulting binary can be used as a stand-alone hook for one-way sync:
//
//      ln -s path/to/upsert-reminder ~/.task/hooks/on-add.10-reminder
//      ln -s path/to/upsert-reminder ~/.task/hooks/on-mod.10-reminder
//
//  Created by Bryce Lampe on 12/29/19.
//

import AppKit
import Foundation
import Repositories
import EventKit
import Models

private func main(store: EKEventStore) {
    let encoder = JSONEncoder()

    let tasks = TaskwarriorRepository()
    let reminders = RemindersRepository(store)
    reminders.assertAuthorized()

    let string = readLine(strippingNewline: true)!
    let task = tasks.readTask(from: string.data(using: .utf8)!)

    let data = tasks.writeTask(reminders.upsertToReminders(task: task))
    print(String(data: data, encoding: .utf8)!)

    exit(0)
}

private let store = EKEventStore.init()
main(store: store)

RunLoop.main.run()
