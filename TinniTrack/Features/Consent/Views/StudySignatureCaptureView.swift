import SwiftUI
import UIKit

struct StudySignatureCaptureCard: View {
    let signatureImageData: Data?
    let drawSignature: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signature")
                .font(.footnote)
                .foregroundStyle(StudyConsentReadableColors.bodyText)

            if let signatureImage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved signature")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LoudnessMatchModalColors.text)

                    Image(uiImage: signatureImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 96)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                        }
                        .accessibilityLabel("Saved signature preview")
                        .accessibilityIdentifier("study_signature_preview_image")
                }
            }

            Button(action: drawSignature) {
                HStack(spacing: 16) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .frame(width: 36)
                        .accessibilityHidden(true)

                    Rectangle()
                        .fill(LoudnessMatchModalColors.primary.opacity(0.22))
                        .frame(width: 1, height: 34)
                        .accessibilityHidden(true)

                    Text("Tap to draw your signature.")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LoudnessMatchModalColors.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(LoudnessMatchModalColors.primary, lineWidth: 1)
                }
            }
            .buttonStyle(AppRoundedButtonStyle(cornerRadius: 7))
            .accessibilityLabel("Tap to draw your signature.")
            .accessibilityIdentifier("study_consent_draw_signature_button")
        }
    }

    private var signatureImage: UIImage? {
        guard let signatureImageData else { return nil }
        return UIImage(data: signatureImageData)
    }
}

struct StudySignatureCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var signatureImageData: Data?
    let clear: () -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Dismiss signature")
                .accessibilityIdentifier("study_signature_dismiss_button")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Draw signature")
                        .font(.headline)
                        .foregroundStyle(LoudnessMatchModalColors.text)
                    Text("Use your finger inside the box, then save.")
                        .font(.subheadline)
                        .foregroundStyle(StudyConsentReadableColors.bodyText)
                }

                Spacer()
            }

            StudySignatureDrawingSurface(
                strokes: $strokes,
                currentStroke: $currentStroke,
                canvasSize: $canvasSize
            )
            .frame(height: 214)

            Text("Your signature is used only for this consent record.")
                .font(.footnote)
                .foregroundStyle(StudyConsentReadableColors.bodyText)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    clearDrawing()
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .frame(minWidth: 92)
                        .frame(height: 34)
                        .background(LoudnessMatchModalColors.controlBackground)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                        }
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .accessibilityIdentifier("study_signature_clear_button")

                Spacer(minLength: 0)

                Button {
                    saveDrawing()
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canSaveDrawing ? LoudnessMatchModalColors.primaryText : LoudnessMatchModalColors.disabledText)
                        .frame(minWidth: 92)
                        .frame(height: 34)
                        .background(canSaveDrawing ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.disabledFill)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(LoudnessMatchModalColors.buttonStroke, lineWidth: 1)
                        }
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .disabled(!canSaveDrawing)
                .accessibilityIdentifier("study_signature_save_button")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(LoudnessMatchModalColors.background)
    }

    private var hasDrawableSignature: Bool {
        strokes.contains { $0.count > 1 } || currentStroke.count > 1
    }

    private var canSaveDrawing: Bool {
        hasDrawableSignature && canvasSize != .zero
    }

    private func clearDrawing() {
        strokes = []
        currentStroke = []
        clear()
    }

    private func saveDrawing() {
        let allStrokes = strokes + (currentStroke.count > 1 ? [currentStroke] : [])
        signatureImageData = StudySignatureRenderer.render(strokes: allStrokes, size: canvasSize)
        strokes = allStrokes
        currentStroke = []
        dismiss()
    }
}

private struct StudySignatureDrawingSurface: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var currentStroke: [CGPoint]
    @Binding var canvasSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))

                Canvas { context, _ in
                    StudySignatureRenderer.draw(
                        strokes: strokes + [currentStroke],
                        size: proxy.size,
                        context: &context
                    )
                }
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        if currentStroke.count > 1 {
                            strokes.append(currentStroke)
                        }
                        currentStroke = []
                    }
            )
            .onAppear {
                canvasSize = proxy.size
            }
            .onChange(of: proxy.size) { _, newSize in
                canvasSize = newSize
            }
            .accessibilityLabel("Signature drawing area")
            .accessibilityIdentifier("study_signature_drawing_surface")
        }
    }
}

private enum StudySignatureRenderer {
    static func draw(strokes: [[CGPoint]], size: CGSize, context: inout GraphicsContext) {
        for stroke in strokes where stroke.count > 1 {
            var path = Path()
            path.move(to: stroke[0])
            for point in stroke.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 16, y: size.height - 48))
        baseline.addLine(to: CGPoint(x: size.width - 16, y: size.height - 48))
        context.stroke(baseline, with: .color(Color(uiColor: .systemGray3)), lineWidth: 1)
    }

    static func render(strokes: [[CGPoint]], size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(2.2)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)

            for stroke in strokes where stroke.count > 1 {
                context.cgContext.beginPath()
                context.cgContext.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    context.cgContext.addLine(to: point)
                }
                context.cgContext.strokePath()
            }
        }
        return image.pngData()
    }
}
