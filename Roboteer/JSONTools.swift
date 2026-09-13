//
//  JSONTools.swift
//  Two small tools the builder needs and Foundation will not give us.
//
//  1. `JSONValue` parses JSON while REMEMBERING THE ORDER the keys were written in, because
//     `Shared/parts.json` is the catalogue and the catalogue's order is the order the player sees.
//     `JSONSerialization` returns a Dictionary, which has no order at all.
//  2. `JSONText` writes a Swift value back out as JSON text with floats that stay floats.
//     `JSONSerialization` turns 1.0 into `1`, and the arena would then read a condition as an int
//     (docs/stage3-swift-notes.md). Every number that arrives as a Double leaves with a decimal.
//

import Foundation

/// One key and value of a JSON object, in the order the text had them.
struct JSONMember {
    let key: String
    let value: JSONValue
}

/// A parsed JSON value. Objects keep their key order.
indirect enum JSONValue {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func parse(_ text: String) -> JSONValue? {
        var parser = JSONParser(bytes: Array(text.utf8))
        return parser.parseDocument()
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first(where: { $0.key == key })?.value
    }

    var members: [JSONMember] {
        if case .object(let members) = self { return members }
        return []
    }

    var items: [JSONValue] {
        if case .array(let items) = self { return items }
        return []
    }

    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let text): return Double(text)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var intValue: Int? {
        guard let value = doubleValue else { return nil }
        return Int(value.rounded())
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    /// The strings of an array of strings, ignoring anything that is not one.
    var stringItems: [String] {
        items.compactMap { $0.stringValue }
    }
}

/// A small recursive descent parser. It is deliberately strict about structure and forgiving
/// about nothing: a malformed catalogue should fail loudly at load, not half load.
private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func parseDocument() -> JSONValue? {
        skipWhitespace()
        guard let value = parseValue() else { return nil }
        skipWhitespace()
        return index == bytes.count ? value : value
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private mutating func parseValue() -> JSONValue? {
        skipWhitespace()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "{"): return parseObject()
        case UInt8(ascii: "["): return parseArray()
        case UInt8(ascii: "\""): return parseString().map { JSONValue.string($0) }
        case UInt8(ascii: "t"): return match("true") ? .bool(true) : nil
        case UInt8(ascii: "f"): return match("false") ? .bool(false) : nil
        case UInt8(ascii: "n"): return match("null") ? JSONValue.null : nil
        default: return parseNumber()
        }
    }

    private mutating func match(_ word: String) -> Bool {
        let wordBytes = Array(word.utf8)
        guard index + wordBytes.count <= bytes.count else { return false }
        for (offset, byte) in wordBytes.enumerated() where bytes[index + offset] != byte { return false }
        index += wordBytes.count
        return true
    }

    private mutating func parseObject() -> JSONValue? {
        index += 1 // {
        var members: [JSONMember] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while index < bytes.count {
            skipWhitespace()
            guard let key = parseString() else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            guard let value = parseValue() else { return nil }
            members.append(JSONMember(key: key, value: value))
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            return nil
        }
        return nil
    }

    private mutating func parseArray() -> JSONValue? {
        index += 1 // [
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while index < bytes.count {
            guard let value = parseValue() else { return nil }
            items.append(value)
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            return nil
        }
        return nil
    }

    private mutating func parseString() -> String? {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { return nil }
        index += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []

        func flushRaw() {
            guard !raw.isEmpty else { return }
            if let text = String(bytes: raw, encoding: .utf8) {
                scalars.append(contentsOf: text.unicodeScalars)
            }
            raw.removeAll(keepingCapacity: true)
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                flushRaw()
                return String(scalars)
            }
            if byte == UInt8(ascii: "\\") {
                flushRaw()
                index += 1
                guard index < bytes.count else { return nil }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append(UnicodeScalar(8))
                case UInt8(ascii: "f"): scalars.append(UnicodeScalar(12))
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    guard let scalar = parseUnicodeEscape() else { return nil }
                    scalars.append(scalar)
                default: return nil
                }
                continue
            }
            raw.append(byte)
            index += 1
        }
        return nil
    }

    /// `\uXXXX`, including a surrogate pair when one follows.
    private mutating func parseUnicodeEscape() -> UnicodeScalar? {
        guard let first = readHexQuad() else { return nil }
        if first >= 0xD800, first <= 0xDBFF,
           index + 1 < bytes.count,
           bytes[index] == UInt8(ascii: "\\"),
           bytes[index + 1] == UInt8(ascii: "u") {
            let save = index
            index += 2
            if let second = readHexQuad(), second >= 0xDC00, second <= 0xDFFF {
                let combined = 0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00)
                return UnicodeScalar(combined)
            }
            index = save
        }
        return UnicodeScalar(first)
    }

    private mutating func readHexQuad() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A")) + 10
            default: return nil
            }
            value = value * 16 + digit
        }
        return value
    }

    private mutating func parseNumber() -> JSONValue? {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        while index < bytes.count {
            let byte = bytes[index]
            let isDigit = byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
            let isNumberPunctuation = byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e")
                || byte == UInt8(ascii: "E") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-")
            guard isDigit || isNumberPunctuation else { break }
            index += 1
        }
        guard start < index,
              let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let value = Double(text) else { return nil }
        return .number(value)
    }
}

/// Writes JSON text. The one rule that matters: a Double leaves with a decimal point, so the
/// arena reads `1.0` as a float and never as an int.
enum JSONText {

    static func string(from value: Any) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: Any, into out: inout String) {
        switch value {
        case let text as String:
            out += quoted(text)
        case let number as NSNumber:
            // Native Bool, Int and Double all bridge to NSNumber, so this one case covers the lot
            // and keeps the float or int distinction that the bridged type carries.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                out += number.boolValue ? "true" : "false"
            } else if CFNumberIsFloatType(number) {
                out += float(number.doubleValue)
            } else {
                out += String(number.int64Value)
            }
        case let list as [Any]:
            out += "["
            for (offset, item) in list.enumerated() {
                if offset > 0 { out += "," }
                write(item, into: &out)
            }
            out += "]"
        case let dictionary as [String: Any]:
            out += "{"
            for (offset, key) in dictionary.keys.sorted().enumerated() {
                if offset > 0 { out += "," }
                out += quoted(key)
                out += ":"
                write(dictionary[key] ?? NSNull(), into: &out)
            }
            out += "}"
        default:
            out += "null"
        }
    }

    /// Always a decimal point, never scientific notation for the values this app sends.
    private static func float(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.1f", value)
        }
        return String(value)
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
