//
//  Task.swift
//  
//
//  Created by Bryce Lampe on 12/29/19.
//

import Foundation

public class Task: Equatable {
    public var uniqueID: String = ""

    public var title: String = ""
    public var status: Status = Status.unknown
    public var priority: Priority = Priority.none
    public var project: String?
    public var reminderID: String?

    public var due: Date?
    public var wait: Date?
    public var lastModified: Date?

    public var notes: [Annotation] = []
    public var tags: [String] = []

    public init() {}

    public static func == (lhs: Task, rhs: Task) -> Bool {
        var same = true
        if lhs.title != rhs.title {
            same = false
            print("\ttitle[\(lhs.title) ▶ \(rhs.title)]")
        }
        // Reminders only knows unknown/completed, so we only want to sync on
        // those changes.
        if (lhs.status == Status.completed && rhs.status != Status.completed) ||
            (lhs.status != Status.completed && rhs.status == Status.completed) {
            same = false
            print("\tstatus[\(lhs.status) ▶ \(rhs.status)]")
        }
        if lhs.priority != rhs.priority {
            same = false
            print("\tpriority[\(lhs.priority) ▶ \(rhs.priority)]")
        }
        if lhs.project != rhs.project {
            same = false
            print("\tproject[\(lhs.project ?? " ") ▶ \(rhs.project ?? " ")]")
        }
        if lhs.reminderID != rhs.reminderID {
            same = false
            print("\treminderID[\(lhs.reminderID ?? " ") ▶ \(rhs.reminderID ?? " ")]")
        }
        if lhs.due != rhs.due {
            same = false
            print("\tdue[\(String(describing: lhs.due)) ▶ \(String(describing: rhs.due))]")
        }
        if lhs.notes != rhs.notes {
            same = false
            print("\tnotes[\(lhs.notes) ▶ \(rhs.notes)]")
        }
        return same
    }

    public func isCompleted() -> Bool {
        return status == .completed
    }

    public func isDeleted() -> Bool {
        return status == .deleted
    }
}

public struct SyncResult {
    public var task: Task
    public var madeChanges: Bool
}

public func synchronize(updatesFrom: Task, toOlder: Task) -> SyncResult {
    let newTask = Task.init()
    newTask.uniqueID = mergeUniqueID(from: updatesFrom, into: toOlder)
    newTask.title = updatesFrom.title
    newTask.status = mergeStatus(from: updatesFrom.status, into: toOlder.status)
    newTask.priority = updatesFrom.priority
    newTask.project = updatesFrom.project

    // Prefer not to overwrite existing reminder id unless its unset
    newTask.reminderID = toOlder.reminderID ?? updatesFrom.reminderID
    newTask.due = updatesFrom.due
    newTask.wait = updatesFrom.wait ?? toOlder.wait
    newTask.lastModified = updatesFrom.lastModified
    newTask.notes = mergeAnnotationLists(from: updatesFrom.notes, into: toOlder.notes)
    newTask.tags = mergeTags(from: updatesFrom.tags, into: toOlder.tags)

    return SyncResult.init(task: newTask, madeChanges: (toOlder != newTask))
}

private func mergeUniqueID(from: Task, into: Task) -> String {
    if from.uniqueID != "" {
        return from.uniqueID
    }
    if into.uniqueID != "" {
        return into.uniqueID
    }
    // Use ReminderID for Taskwarrior's UUID when inserting from Reminders, so
    // we can run the sync job on multiple hosts.
    return (into.reminderID ?? from.reminderID ?? "no-reminder-id").lowercased()
}

private func mergeTags(from: [String], into: [String]) -> [String] {
    if into == [] {
        return from
    }

    if from == [] {
        return into
    }

    return from
}

private func mergeStatus(from: Status, into: Status) -> Status {
    if into == Status.unknown {
        return from
    }

    if from == Status.unknown {
        return into
    }

    return from
}
