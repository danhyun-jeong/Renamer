import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var showStats = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a hh:mm"
        return f
    }()

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy. MM. dd."
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            logView
            Divider()
            footerView
        }
        .frame(width: 360)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var headerView: some View {
        HStack {
            Circle()
                .fill(appState.service.isRunning ? Color.green : Color.yellow)
                .frame(width: 8, height: 8)
            Text(appState.service.isRunning ? "동작 중" : "동작 중지")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if appState.apiKey.isEmpty {
                Text("API 키 필요")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Button(appState.service.isRunning ? "중지" : "시작") {
                    if appState.service.isRunning {
                        appState.service.stop()
                    } else {
                        appState.service.start(apiKey: appState.apiKey, model: appState.selectedModel)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var logView: some View {
        Group {
            if appState.service.activityLog.isEmpty {
                Text("PDF/이미지 파일 검토 및 제목 변경 로그가 표시됩니다.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.service.activityLog) { entry in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(Self.timeFormatter.string(from: entry.timestamp))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 58, alignment: .trailing)
                                    Text(entry.message)
                                        .font(.system(size: 11))
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(height: 220)
    }

    private var footerView: some View {
        HStack {
            Button("설정") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("통계") {
                showStats.toggle()
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showStats, arrowEdge: .bottom) {
                statsPopover
            }
            Spacer()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statsPopover: some View {
        let service = appState.service
        let resetLabel = appState.statsResetDate == .distantPast
            ? "처음부터"
            : Self.resetDateFormatter.string(from: appState.statsResetDate)
        return VStack(alignment: .leading, spacing: 10) {

            // ── 기준일 이후 누적 ──────────────────────────────
            statsRow("분석 건수", value: "\(service.totalAnalyzed)건")
            statsRow("파일 이름 수정 건수", value: "\(service.totalRenamed)건")
            statsRow("누적 API 비용", value: String(format: "$%.4f", service.totalCost))
            HStack {
                Text("기준일: \(resetLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button("카운팅 초기화") {
                    appState.resetStats()
                }
                .foregroundColor(.red)
                .font(.system(size: 12))
            }

            Divider()

            // ── 지난 30일 (고정) ──────────────────────────────
            Text("지난 30일 간의")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            statsRow("분석 건수", value: "\(service.last30DaysAnalyzed)건")
            statsRow("파일 이름 수정 건수", value: "\(service.last30DaysRenamed)건")
            statsRow("누적 API 비용", value: String(format: "$%.4f", service.last30DaysCost))

        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .font(.system(size: 13, design: .monospaced))
        }
        .font(.system(size: 13))
    }
}
