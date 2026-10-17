//
//  CaptureLibrarySearch.swift
//  Screendrop
//

import CoreGraphics
import Foundation

/// Library search: every word of the query has to appear somewhere in a
/// capture's name, app, window title, category, the model's title and
/// keywords, its month and weekday, or the text inside it. Matching ignores
/// case, accents and width, so "cafe" finds "Café".
nonisolated enum CaptureLibrarySearch {
    private static let folding: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func fold(_ text: String) -> String {
        text.folding(options: folding, locale: nil)
    }

    static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The folded text a capture is searched by.
    static func document(for item: CaptureLibraryItem, analysis: CaptureAnalysis?) -> String {
        var fields = [item.name, item.fileURL.lastPathComponent, item.kindTitle]
        if let source = item.source {
            fields.append(source.appName)
            if let window = source.windowTitle { fields.append(window) }
        }
        // "october", "friday" or "2026" narrow by when.
        fields.append(item.createdAt.formatted(.dateTime.month(.wide).year().weekday(.wide)))
        if let analysis {
            if let category = analysis.category { fields.append(category.title) }
            if let title = analysis.title { fields.append(title) }
            fields.append(contentsOf: analysis.keywords)
            fields.append(analysis.text)
            if let transcript = analysis.transcript { fields.append(transcript) }
        }
        return fold(fields.joined(separator: "\n"))
    }

    /// Where the query's words sit in the capture, normalized to the image
    /// with a top-left origin. Vision reports whole lines, so a match's span
    /// is estimated from its share of the line's characters.
    static func highlights(in lines: [CaptureTextLine], tokens: [String], limit: Int = 24) -> [CGRect] {
        guard !tokens.isEmpty else { return [] }
        var rects: [CGRect] = []
        for line in lines {
            guard let box = line.box else { continue }
            let text = fold(line.text)
            let length = CGFloat(text.count)
            guard length > 0 else { continue }
            for token in tokens {
                var searchRange = text.startIndex..<text.endIndex
                while let range = text.range(of: token, range: searchRange) {
                    let start: Int = text.distance(from: text.startIndex, to: range.lowerBound)
                    let count: Int = text.distance(from: range.lowerBound, to: range.upperBound)
                    let x: CGFloat = box.minX + box.width * CGFloat(start) / length
                    let width: CGFloat = box.width * CGFloat(count) / length
                    rects.append(CGRect(x: x, y: box.minY, width: width, height: box.height))
                    if rects.count >= limit { return rects }
                    searchRange = range.upperBound..<text.endIndex
                }
            }
        }
        return rects
    }
}
