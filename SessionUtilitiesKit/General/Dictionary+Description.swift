
public extension Dictionary {
    
    var prettifiedDescription: String {
        return "[ " + map { key, value in
            let keyDescription = String(describing: key)
            let valueDescription = String(describing: value)
            let maxLength = 20
            let truncatedValueDescription = valueDescription.count > maxLength ? valueDescription.prefix(maxLength) + "..." : valueDescription
            return keyDescription + " : " + truncatedValueDescription
        }.joined(separator: ", ") + " ]"
    }
    
    func asArray() -> [(key: Key, value: Value)] {
        return Array(self)
    }
}

public extension Dictionary {
    func setting(_ key: Key, _ value: Value?) -> [Key: Value] {
        var updatedDictionary: [Key: Value] = self
        updatedDictionary[key] = value

        return updatedDictionary
    }
}

public extension Dictionary.Values {
    func asArray() -> [Value] {
        return Array(self)
    }
}
