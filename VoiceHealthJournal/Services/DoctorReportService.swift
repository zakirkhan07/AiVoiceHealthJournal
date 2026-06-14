import Foundation
import UIKit

/// Renders a "bring to your doctor" PDF: chronological entries with symptoms and lifestyle.
/// Pure UIKit rendering — no dependencies.
struct DoctorReportService {

    static func generatePDF(entries: [JournalEntry]) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let margin: CGFloat = 48

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let df = DateFormatter()
        df.dateStyle = .medium

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageRect.height - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, attrs: [NSAttributedString.Key: Any], spacing: CGFloat = 6) {
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: pageRect.width - margin * 2, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                ensureSpace(bounding.height + spacing)
                (text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: bounding.height),
                    withAttributes: attrs)
                y += bounding.height + spacing
            }

            draw("Health Journal — Doctor Summary", attrs: titleAttrs, spacing: 4)
            draw("Generated \(df.string(from: .now)) · \(entries.count) check-ins · Patient-reported data", attrs: bodyAttrs, spacing: 16)

            for entry in entries.sorted(by: { $0.createdAt > $1.createdAt }) {
                draw(df.string(from: entry.createdAt), attrs: headerAttrs)
                if let summary = entry.aiSummary { draw(summary, attrs: bodyAttrs) }
                if let mood = entry.moodScore { draw("Mood: \(mood)/5", attrs: bodyAttrs) }
                for s in entry.symptoms {
                    let note = s.note.map { " — \($0)" } ?? ""
                    draw("• Symptom: \(s.name), severity \(s.severity)/5\(note)", attrs: bodyAttrs, spacing: 2)
                }
                for l in entry.lifestyle {
                    draw("• \(l.category.capitalized): \(l.detail)", attrs: bodyAttrs, spacing: 2)
                }
                y += 12
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthJournal-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url)
            AnalyticsLogger.shared.log(.doctorReportExported, props: ["entries": "\(entries.count)"])
            return url
        } catch {
            return nil
        }
    }
}
