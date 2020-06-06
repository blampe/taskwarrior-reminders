//
//  Taskwarrior.swift
//  taskwarrior-reminders
//
//  Created by Bryce Lampe on 12/29/19.
//

import Foundation
import Models

public class TaskwarriorRepository {
    public init () {}

    public func readTask(from: Data) -> Task {
        let decoder = JSONDecoder()
        let utf8Data = String(decoding: from, as: UTF8.self).data(using: .utf8)!
        let tw = try! decoder.decode(TaskwarriorTask.self, from: utf8Data)
        return taskwarriorToTask(tw)
    }

    public func writeTask(_ from: Task) -> Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(taskToTaskwarrior(from))
    }

    public func fetchTaskwarriorTask(filter: String) -> Task? {
        execTaskwarrior(args: ["sync"])
        guard let data = execTaskwarrior(args: [filter, "export"]) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let tw = (try! decoder.decode([TaskwarriorTask].self, from: data)).first else { return nil }
        return taskwarriorToTask(tw)
    }

    public func deleteFromTaskwarrior(_ t: Task) {
        execTaskwarrior(args: ["reminderID:" + (t.reminderID ?? "ERROR"), "-COMPLETED", "delete"])
        execTaskwarrior(args: ["sync"])
    }

    public func upsertToTaskwarrior(_ t: Task) {
        let existingTask = fetchTaskwarriorTask(
            filter: "reminderID:" + (t.reminderID ?? "")
            ) ?? Task.init()

        let syncResult = synchronize(updatesFrom: t, toOlder: existingTask)

        if syncResult.madeChanges {
            writeToTaskwarrior(task: syncResult.task)
        }
    }

    public func tasksModifiedSince(date: Date) -> [Task] {
        guard let data = execTaskwarrior(args: ["export"]) else {
            return []
        }

        var tasks: [Task] = []
        let decoder = JSONDecoder()
        let utf8Data = String(decoding: data, as: UTF8.self).data(using: .utf8)!
        guard let twtasks = try? decoder.decode([TaskwarriorTask].self, from: utf8Data) else {
            print("tasksModifiedSince unable to fetch tasks")
            return []
        }
        for twtask in twtasks {
            if fromTaskwarriorDate(twtask.modified) ?? date >= date {
                tasks += [taskwarriorToTask(twtask)]
            }
        }
        return tasks
    }

    private func writeToTaskwarrior(task: Task) {
        let args = ["import", "-"]
        execTaskwarrior(args: args, input: task)
        execTaskwarrior(args: ["sync"])
    }

    private func execTaskwarrior(args: [String], input: Task? = nil) -> Data? {
        let process = Process.init()
        process.launchPath = "/usr/local/bin/task" // TODO: does just "task" work?

        let arguments = [
            "rc.uda.reminderID.type=string",
            "rc.confirmation=off",
            "rc.context=none",
            "rc.recurrence.confirmation=off"
            ] + args
        process.arguments = arguments

        let stdOut = Pipe()
        let stdIn = Pipe()
        let stdErr = Pipe()
        if input != nil {
            let jsonEncoder = JSONEncoder.init()
            let data = try! jsonEncoder.encode(taskToTaskwarrior(input!))

            // Stream input data so we don't deadlock on a full write buffer
            var iter = data.makeIterator()
            stdIn.fileHandleForWriting.writeabilityHandler = { pipe in
                if let next = iter.next() {
                    pipe.write(Data.init([next]))
                } else {
                    stdIn.fileHandleForWriting.writeabilityHandler = nil
                    stdIn.fileHandleForWriting.closeFile()
                }
            }
        }

        process.standardInput = stdIn
        process.standardOutput = stdOut
        process.standardError = stdErr

        print("  [Taskwarrior] \(args.joined(separator: " "))")
        try process.launch()

        let dataOut = stdOut.fileHandleForReading.readDataToEndOfFile()
        let dataErr = stdErr.fileHandleForReading.readDataToEndOfFile()

        if CommandLine.arguments.contains("--verbose") {
            print("\tStdOut:", String.init(data: dataOut, encoding: .utf8) ?? "")
            print("\tStdErr:", String.init(data: dataErr, encoding: .utf8) ?? "")
        }
        return dataOut
    }

    private func getTaskwarriorDataDir() -> String {
        return ""
    }

    private struct TaskWarriorAnnotation: Codable {
        var entry: String
        var description: String
    }

    private struct TaskwarriorTask: Codable {
        public var description: String = "new task"
        public var status: String = "pending"
        public var uuid: String = ""

        public var priority: String?
        public var project: String?

        // Dates
        public var modified: String?
        public var due: String?
        //public var entry: String? // TODO
        //public var end: String? // TODO
        public var wait: String? // TODO

        public var tags: [String]? // TODO
        public var annotations: [TaskWarriorAnnotation]? = []

        public var reminderID: String?
        public var reminderListID: String?

        public init() {}
    }

    private func taskwarriorToTask(_ tw: TaskwarriorTask) -> Task {
        let t = Task.init()
        t.uniqueID = tw.uuid
        t.title = tw.description
        t.status = fromTaskwarriorStatus(tw.status)
        t.priority = fromTaskwarriorPriority(tw.priority)
        t.project = tw.project
        t.reminderID = tw.reminderID
        t.due = fromTaskwarriorDate(tw.due)
        t.wait = fromTaskwarriorDate(tw.wait)
        t.lastModified = fromTaskwarriorDate(tw.modified)
        t.notes = fromTaskwarriorNotes(tw.annotations ?? [])
        t.tags = tw.tags ?? []
        return t
    }

    private func taskToTaskwarrior(_ t: Task) -> TaskwarriorTask {
        var tw = TaskwarriorTask.init()
        tw.description = t.title
        tw.status = toTaskwarriorStatus(t.status)
        tw.uuid = t.uniqueID
        tw.priority = toTaskwarriorPriority(t.priority)
        tw.project = t.project
        tw.modified = toTaskwarriorDate(t.lastModified)
        tw.due = toTaskwarriorDate(t.due)
        tw.wait = toTaskwarriorDate(t.wait)
        tw.tags = t.tags
        tw.annotations = toTaskwarriorNotes(t.notes)

        tw.reminderID = t.reminderID
        tw.reminderListID = nil //TODO???
        return tw
    }

    private func toTaskwarriorPriority(_ p: Priority) -> String? {
        switch p {
        case Priority.low:
            return "L"
        case Priority.medium:
            return "M"
        case Priority.high:
            return "H"
        default:
            return nil
        }
    }

    private func fromTaskwarriorPriority(_ priority: String?) -> Priority {
        guard var priority = priority else {
            return Priority.none
        }
        priority = priority.lowercased()

        switch priority {
        case "l", "low":
            return Priority.low
        case "m", "med", "medium":
            return Priority.medium
        case "h", "high":
            return Priority.high
        default:
            return Priority.none
        }
    }

    private func toTaskwarriorStatus(_ status: Status) -> String {
        switch status {
        case Status.completed:
            return "completed"
        case Status.started:
            return "started"
        case Status.deleted:
            return "deleted"
        default:
            return "pending"
        }
    }

    private func fromTaskwarriorStatus(_ s: String) -> Status {
        switch s {
        case "started":
            return Status.started
        case "completed":
            return Status.completed
        case "deleted":
            return Status.deleted
        default:
            return Status.pending
        }
    }

    private func toTaskwarriorDate(_ d: Date?) -> String? {
        guard let d = d else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return formatter.string(from: d)
    }

    private func fromTaskwarriorDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        // TODO(https://bugs.swift.org/browse/SR-11984)
        let pattern = #"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let nsrange = NSRange(s.startIndex..<s.endIndex, in: s)

        var components = DateComponents()
        regex.enumerateMatches(in: s, options: [], range: nsrange) { (match, _, _) in
            guard let match = match else { return }
            components.year = Int(s[Range(match.range(at: 1), in: s)!])
            components.month = Int(s[Range(match.range(at: 2), in: s)!])
            components.day = Int(s[Range(match.range(at: 3), in: s)!])
            components.hour = Int(s[Range(match.range(at: 4), in: s)!])
            components.minute = Int(s[Range(match.range(at: 5), in: s)!])
            components.second = Int(s[Range(match.range(at: 6), in: s)!])
            components.timeZone = TimeZone(abbreviation: "GMT")
        }
        return Calendar.current.date(from: components)!
    }

    private func toTaskwarriorNotes(_ ann: [Annotation]) -> [TaskWarriorAnnotation] {
        var annotations: [TaskWarriorAnnotation] = []
        for a in ann {
            annotations += [
                TaskWarriorAnnotation.init(
                    entry: toTaskwarriorDate(a.entry)!,
                    description: a.description
                )
            ]
        }
        return annotations
    }

    private func fromTaskwarriorNotes(_ twas: [TaskWarriorAnnotation]) -> [Annotation] {
        var annotations: [Annotation] = []
        for twa in twas {
            var a = Annotation.init()
            a.entry = fromTaskwarriorDate(twa.entry)!
            a.description = twa.description
            annotations += [a]
        }
        return annotations
    }

}
