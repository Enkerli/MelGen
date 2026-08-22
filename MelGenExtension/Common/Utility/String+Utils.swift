//
//  String+Utils.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import Foundation

extension String {
    var range: NSRange {
        NSRange(location: 0, length: count)
    }
    
    func isAlphanumeric() -> Bool {
        if self.isEmpty { return false }
        let regex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]*$", options: .caseInsensitive)
        guard regex.firstMatch(in: self, options: [], range: range) != nil else {
            return false
        }
        return true
    }
}
