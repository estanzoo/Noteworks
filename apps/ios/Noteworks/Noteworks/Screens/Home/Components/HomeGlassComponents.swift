//
//  HomeGlassComponents.swift
//  Noteworks
//

import SwiftUI

// MARK: - Glass Icon Button

struct HomeGlassIconButton: View {
    let icon: String
    var isActive: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(isActive ? HomeTheme.accent : HomeTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(isActive ? HomeTheme.accent.opacity(0.15) : Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(isActive ? AnyShape(RoundedRectangle(cornerRadius: 12)) : AnyShape(Circle()))
                .overlay {
                    Group {
                        if isActive {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(HomeTheme.accent.opacity(0.4), lineWidth: 1)
                        } else {
                            Circle().strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AnyShape helper

private struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { _path = { shape.path(in: $0) } }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

// MARK: - Badge Pill

struct HomeBadgePill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.06 * 11)
            .foregroundStyle(Color(red: 0x7A/255, green: 0x8A/255, blue: 0x96/255))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.45))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Bubble Press Style

struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Course Bubble Model

struct CourseBubble: Identifiable {
    let id = UUID()
    let name: String
    let noteCount: Int
    let size: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
}

// MARK: - Bubble View

struct BubbleView: View {
    let course: CourseBubble

    private var titleSize: CGFloat {
        max(16, course.size * 0.09)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.15)],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                .frame(width: course.size, height: course.size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: course.size, height: course.size)
                )
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                }
                .shadow(color: Color.white.opacity(0.7), radius: 0, x: 0, y: -0.5)
                .shadow(color: Color.white.opacity(0.3), radius: 0.25)
                .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(course.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Image("Icons/fluent_notebook-24-regular")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(HomeTheme.textMuted)

                    Text("\(course.noteCount) \(course.noteCount == 1 ? "Note" : "Notes")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomeTheme.textMuted)
                }
            }
            .padding(12)
            .frame(width: course.size)
        }
    }
}
