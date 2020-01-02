//
//  Annotations.swift
//  
//
//  Created by Bryce Lampe on 12/31/19.
//

import Foundation

public struct Annotation: Equatable {
    public var entry: Date
    public var description: String = ""

    public init () {
        self.entry = Date()
    }

    public static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        return lhs.entry == rhs.entry && lhs.description == rhs.description
    }
}

public func mergeAnnotationLists(from: [Annotation], into: [Annotation]) -> [Annotation] {

    var idx = 0
    var newAnnotations: [Annotation] = []

    for f in from {
        var a = Annotation.init()
        a.entry = f.entry
        a.description = f.description
        // Editing a prior annotation, keep the entry date
        if idx < into.count {
            a.entry = into[idx].entry
        }
        newAnnotations += [a]
        idx += 1
    }

    return newAnnotations
}
