import SwiftUI
import UIKit

struct SelectionAwareTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var isEditable: Bool = true
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.selectedRange = clampedRange(selectedRange, in: text)
        textView.isEditable = isEditable
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        let safeRange = clampedRange(selectedRange, in: uiView.text ?? "")
        if uiView.selectedRange != safeRange {
            uiView.selectedRange = safeRange
        }

        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let safeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: safeLength)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectionAwareTextEditor

        init(parent: SelectionAwareTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}
