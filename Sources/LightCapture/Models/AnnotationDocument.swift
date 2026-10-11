import AppKit
import SwiftUI

 enum AnnotationTool: String, CaseIterable, Codable {
    case select = "选择", rectangle = "矩形", ellipse = "椭圆", arrow = "箭头", pen = "画笔", highlight = "高亮", text = "文字", mosaic = "马赛克", number = "序号"
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .text: return "character.cursor.ibeam"
        case .mosaic: return "square.grid.3x3.fill"
        case .number: return "1.circle"
        }
    }
    var hint: String {
        switch self {
        case .select: return L("点击选中，拖动移动；拖动控制点调整；双击文字编辑")
        case .text: return L("点击输入文字；Return 完成，双击编辑；Shift 拖动锁定方向")
        case .number: return L("点击添加递增序号")
        default: return L("拖动绘制%@；已有标注可直接拖动，按住 Option 绘制重叠内容", L(rawValue))
        }
    }
}
struct AnnotationMark: Identifiable, Equatable, Codable {
    let id: UUID
    var tool: AnnotationTool
    var points: [CGPoint]
    var text: String = ""
    var colorIndex: Int = 0
    var lineWidth: CGFloat = 6
    var fontSize: CGFloat = 32
    var number: Int = 1
    var rect: CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { r, p in
            CGRect(x: min(r.minX, p.x), y: min(r.minY, p.y), width: max(r.maxX, p.x) - min(r.minX, p.x), height: max(r.maxY, p.y) - min(r.minY, p.y))
        }
    }
}
@MainActor final class AnnotationDocument: ObservableObject {
    nonisolated static let colors: [NSColor] = [NSColor(red: 0.92, green: 0.36, blue: 0.25, alpha: 1), .systemYellow, .systemGreen, .systemBlue, .systemPurple, .white, .black]
    @Published var marks: [AnnotationMark] = []
    @Published var selectedID: UUID?
    @Published var tool: AnnotationTool = .rectangle
    @Published var colorIndex = 0
    @Published var lineWidth: CGFloat = 6
    @Published var fontSize: CGFloat = 32
    @Published var undoStates: [[AnnotationMark]] = []
    @Published var redoStates: [[AnnotationMark]] = []
    // The view commits pending native text before copy/save or toolbar actions.
    private var outputMarks: [AnnotationMark] = []
    @Published var isProcessing = false
    var onOutput: (() -> Void)?
    var hasUnsavedChanges: Bool { marks != outputMarks }
    func acceptOutput() { outputMarks = marks; onOutput?() }
    var commitText: (() -> Void)?
    var selected: AnnotationMark? { marks.first { $0.id == selectedID } }
    func record(_ previous: [AnnotationMark]) {
        guard previous != marks else { return }
        undoStates.append(previous); redoStates.removeAll()
    }
    func add(_ mark: AnnotationMark) {
        let before = marks; marks.append(mark); selectedID = mark.id; record(before)
    }
    func undo() {
        commitText?()
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(marks); marks = previous; selectedID = nil
    }
    func redo() {
        commitText?()
        guard let next = redoStates.popLast() else { return }
        undoStates.append(marks); marks = next; selectedID = nil
    }
    func deleteSelected() {
        commitText?()
        guard let id = selectedID else { return }
        let before = marks; marks.removeAll { $0.id == id }; selectedID = nil; record(before)
    }
    func select(_ id: UUID?) {
        selectedID = id
        if let mark = selected { colorIndex = mark.colorIndex; lineWidth = mark.lineWidth; fontSize = mark.fontSize }
    }
    func style(color: Int? = nil, width: CGFloat? = nil, font: CGFloat? = nil) {
        commitText?()
        let before = marks
        if let color { colorIndex = color }
        if let width { lineWidth = width }
        if let font { fontSize = font }
        if let index = marks.firstIndex(where: { $0.id == selectedID }) {
            if let color { marks[index].colorIndex = color }
            if let width { marks[index].lineWidth = width }
            if let font { marks[index].fontSize = font }
            record(before)
        }
    }
    func makeMark(at point: CGPoint) -> AnnotationMark {
        AnnotationMark(id: UUID(), tool: tool, points: [point, point], colorIndex: colorIndex, lineWidth: lineWidth, fontSize: fontSize,
                       number: (marks.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1)
    }
}
