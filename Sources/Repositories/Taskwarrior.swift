//
//  Taskwarrior.swift
//  taskwarrior-reminders
//
//  Created by Bryce Lampe on 12/29/19.
//

import Foundation
import Models

import SwiftyJSON

public class TaskwarriorRepository {
    public init () {}

    public func readTask(from: Data) -> Task {
        let utf8Data = String(decoding: from, as: UTF8.self).data(using: .utf8)!
        let tw = TaskwarriorTask(from: utf8Data)
        return taskwarriorToTask(tw)
    }

    public func writeTask(_ from: Task) -> Data {
        let tw = taskToTaskwarrior(from)
        let encoder = JSONEncoder()
        return try! encoder.encode(tw)
    }

    public func syncWithTaskd() {
        execTaskwarrior(args: ["sync"])
    }

    public func fetchTaskwarriorTask(filter: String) -> Task? {
        syncWithTaskd()
        guard let data = execTaskwarrior(args: [filter, "export"]) else {
            return nil
        }
        for taskData in try! JSON(data: data).arrayValue {
            return taskwarriorToTask(TaskwarriorTask(from: try! taskData.rawData()))
        }
        return nil
    }

    public func deleteFromTaskwarrior(_ t: Task) {
        guard t.reminderID != nil else {
            return
        }
        execTaskwarrior(args: ["reminderID:" + t.reminderID!, "-COMPLETED", "delete"])
        syncWithTaskd()
    }

    public func upsertToTaskwarrior(_ t: Task) -> SyncResult {
        let existingTask = fetchTaskwarriorTask(
            filter: "reminderID:" + (t.reminderID ?? "")
            ) ?? Task()

        let syncResult = synchronize(updatesFrom: t, toOlder: existingTask)

        if syncResult.madeChanges {
            writeToTaskwarrior(task: syncResult.task)
        }

        return syncResult
    }

    public func tasksModifiedSince(date: Date) -> [Task] {
        guard let data = execTaskwarrior(args: ["modified.after:" + toTaskwarriorDate(date)!, "export"]) else {
            return []
        }

        var tasks: [Task] = []
        let utf8Data = String(decoding: data, as: UTF8.self).data(using: .utf8)!
        let json = try? JSON(data: utf8Data).arrayValue
        guard json != nil else {
            print("tasksModifiedSince unable to fetch tasks since", date)
            return []
        }
        for subJson in json! {
            let twtask = TaskwarriorTask(from: try! subJson.rawData())
            if fromTaskwarriorDate(twtask.modified)! >= date {
                tasks += [taskwarriorToTask(twtask)]
            }
        }
        return tasks
    }

    private func writeToTaskwarrior(task: Task) {
        let args = ["import", "-"]
        execTaskwarrior(args: args, input: task)
        syncWithTaskd()
    }

    private func execTaskwarrior(args: [String], input: Task? = nil) -> Data? {
        let process = Process.init()
        defer { process.terminate() }

        var taskBinaryPath = "/usr/local/bin/task" // Default Taskwarrior path.
        if !FileManager.default.isExecutableFile(atPath: taskBinaryPath) {
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/task") {
               taskBinaryPath = "/opt/homebrew/bin/task" //If Taskwarrior is Homebrew installed
            } else if FileManager.default.isExecutableFile(atPath: "/opt/local/bin/task") {
               taskBinaryPath = "/opt/local/bin/task" //If Taskwarrior is Macports installed
        }
        }

        process.launchPath = taskBinaryPath

        let arguments = [
            "rc.uda.reminderID.type=string",
            "rc.confirmation=off",
            "rc.context=none",
            "rc.recurrence.confirmation=off",
            "rc.search.case.sensitive=no",
            "rc.verbose=nothing"
            ] + args
        process.arguments = arguments

        let stdOut = Pipe()
        let stdIn = Pipe()
        let stdErr = Pipe()
        if input != nil {
            let jsonEncoder = JSONEncoder.init()
            let data = writeTask(input!)

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

    private struct TaskWarriorAnnotation: Encodable {
        var entry: String
        var description: String
    }

    private struct TaskwarriorTask: Encodable {
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

        public var UDA: [String: String] = [:]

        enum Keys: String, CodingKey {
            case description, status, uuid, priority, project, modified, due, wait, tags, annotations, reminderID, reminderListID
        }

        struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) {
                self.stringValue = stringValue
            }
            var intValue: Int? { return nil }
            init?(intValue: Int) { return nil }
        }

        public init(from data: Data? = nil) {
            guard data != nil else {
                return
            }
            let json = try! JSON(data: data!)
            for (key, subJson):(String, JSON) in json {
                let value = subJson.stringValue
                switch key {
                case Keys.description.rawValue:
                    self.description = value
                case Keys.status.rawValue:
                    self.status = value
                case Keys.uuid.rawValue:
                    self.uuid = value
                case Keys.priority.rawValue:
                    self.priority = value
                case Keys.project.rawValue:
                    self.project = value
                case Keys.modified.rawValue:
                    self.modified = value
                case Keys.due.rawValue:
                    self.due = value
                case Keys.wait.rawValue:
                    self.wait = value
                case Keys.tags.rawValue:
                    self.tags = subJson.arrayValue.map {$0.stringValue}
                case Keys.annotations.rawValue:
                    self.annotations = subJson.arrayValue.map {TaskWarriorAnnotation(entry: $0["entry"].stringValue, description: $0["description"].stringValue)}
                case Keys.reminderID.rawValue:
                    self.reminderID = value
                case Keys.reminderListID.rawValue:
                    self.reminderListID = value
                default:
                    self.UDA[key] = value
                }
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(description, forKey: Keys.description)
            try container.encode(status, forKey: Keys.status)
            try container.encode(uuid, forKey: Keys.uuid)
            try container.encodeIfPresent(priority, forKey: Keys.priority)
            try container.encodeIfPresent(project, forKey: Keys.project)
            try container.encodeIfPresent(modified, forKey: Keys.modified)
            try container.encodeIfPresent(due, forKey: Keys.due)
            try container.encodeIfPresent(wait, forKey: Keys.wait)
            try container.encodeIfPresent(tags, forKey: Keys.tags)
            try container.encodeIfPresent(annotations, forKey: Keys.annotations)
            try container.encodeIfPresent(reminderID, forKey: Keys.reminderID)
            try container.encodeIfPresent(reminderListID, forKey: Keys.reminderListID)
            var udaContainer = encoder.container(keyedBy: DynamicKey.self)
            for (k, v) in UDA {
                try udaContainer.encode(v, forKey: DynamicKey(stringValue: k)!)
            }
        }
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
        t.UDA = tw.UDA
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
        tw.UDA = t.UDA
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
        if priority == nil {
            return Priority.none
        }
        let priority = priority!.lowercased()

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
        if d == nil {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return formatter.string(from: d!)
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
