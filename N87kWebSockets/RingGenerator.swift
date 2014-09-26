//
//  RingGenerator.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 2014-09-25.
//  Copyright (c) 2014 jacob berkman. All rights reserved.
//

struct RingGenerator<S: CollectionType>: GeneratorType {
    typealias Element = S.Generator.Element
    
    private let collection: S
    private var cur: S.Index
    
    init(collection: S) {
        self.collection = collection
        cur = collection.startIndex
    }
    
    mutating func next() -> Element? {
        let ret = collection[cur]
        switch cur.successor() {
        case collection.endIndex:
            cur = collection.startIndex
        case let newCur:
            cur = newCur
        }
        return ret
    }
}
