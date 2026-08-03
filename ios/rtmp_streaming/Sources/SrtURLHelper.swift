import Foundation
import SRTHaishinKit

/// Parses SRT URLs that contain SRS/ZLMediaKit-style `streamid` values with `#`
/// (e.g. `srt://host:10080?streamid=#!::r=live/livestream,m=publish`).
/// Foundation treats `#` as a fragment delimiter, which breaks `URL(string:)` / `SRTSocketURL`.
enum SrtURLHelper {
  struct Parsed {
    /// Safe URL for `SRTConnection.connect` (streamid removed; other query params kept).
    let connectURL: URL
    /// Pre-connect socket options extracted from the original string (at least streamid).
    let preOptions: [SRTSocketOption]
  }

  /// Known SRT query keys (excluding streamid, which is handled specially).
  private static let knownKeys: Set<String> = [
    "mode", "adapter", "port", "timeout", "passphrase", "pbkeylen", "nakreport",
    "conntimeo", "drifttracer", "enforcedencryption", "fc", "ioctl", "peeridletimeo",
    "rcvbuf", "rcvlatency", "rcvtimeo", "sndbuf", "snddropdelay", "sndsyn", "sndtimeo",
    "tlpktdrop", "tsbpdmode", "latency", "linger", "lossmaxttl", "minversion",
    "messageapi", "payloadsize", "kmrefreshrate", "kmpreannounce", "transtype",
    "ffs", "ipttl", "iptos", "inputbw", "oheadbw", "peerlatency", "mss"
  ]

  static func parse(_ raw: String) -> Parsed? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.lowercased().hasPrefix("srt://") else { return nil }

    var options: [SRTSocketOption] = []
    var working = trimmed

    if let streamId = extractStreamId(from: &working),
       let option = try? SRTSocketOption(name: .streamid, value: streamId) {
      options.append(option)
    }

    guard let connectURL = encodeQueryIfNeeded(working) else { return nil }
    return Parsed(connectURL: connectURL, preOptions: options)
  }

  /// Pulls `streamid=...` out of the raw string without treating `#` as a fragment.
  private static func extractStreamId(from working: inout String) -> String? {
    guard let markerRange = working.range(of: "streamid=", options: .caseInsensitive) else {
      return nil
    }
    let valueStart = markerRange.upperBound
    let after = working[valueStart...]

    let valueEnd: String.Index
    if let next = nextQuerySeparator(in: after) {
      valueEnd = next
    } else {
      valueEnd = working.endIndex
    }

    let rawValue = String(working[valueStart..<valueEnd])
    let value = rawValue.removingPercentEncoding ?? rawValue

    var keyStart = markerRange.lowerBound
    if keyStart > working.startIndex {
      let prev = working.index(before: keyStart)
      if working[prev] == "?" || working[prev] == "&" {
        keyStart = prev
      }
    }
    working.removeSubrange(keyStart..<valueEnd)
    if working.hasSuffix("?") || working.hasSuffix("&") {
      working.removeLast()
    }
    working = working.replacingOccurrences(of: "?&", with: "?")
    working = working.replacingOccurrences(of: "&&", with: "&")
    return value.isEmpty ? nil : value
  }

  /// Finds `&knownKey=` so embedded `m=publish` inside streamid is kept.
  private static func nextQuerySeparator(in after: Substring) -> String.Index? {
    var search = after.startIndex
    while let amp = after[search...].firstIndex(of: "&") {
      let keyStart = after.index(after: amp)
      guard let eq = after[keyStart...].firstIndex(of: "=") else {
        return amp
      }
      let key = String(after[keyStart..<eq]).lowercased()
      if knownKeys.contains(key) {
        return amp
      }
      search = after.index(after: amp)
    }
    return nil
  }

  private static func encodeQueryIfNeeded(_ urlString: String) -> URL? {
    if let url = URL(string: urlString), url.scheme?.lowercased() == "srt" {
      return url
    }
    guard let qIndex = urlString.firstIndex(of: "?") else {
      return URL(string: urlString)
    }
    let head = String(urlString[..<qIndex])
    let query = String(urlString[urlString.index(after: qIndex)...])
    let encodedPairs = query.split(separator: "&").compactMap { pair -> String? in
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let key = parts.first else { return nil }
      if parts.count == 1 {
        return String(key)
      }
      let rawValue = String(parts[1])
      let encoded = rawValue.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed)
        ?? rawValue
      return "\(key)=\(encoded)"
    }
    let rebuilt = encodedPairs.isEmpty ? head : "\(head)?\(encodedPairs.joined(separator: "&"))"
    return URL(string: rebuilt)
  }

  private static let queryValueAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: ":#[]@!$&'()*+,;=")
    return set
  }()
}
