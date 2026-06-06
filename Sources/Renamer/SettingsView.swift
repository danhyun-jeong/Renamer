import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSaved = false
    @State private var showLogCleared = false
    @State private var showClearLogConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Claude API Key 입력하기") {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("sk-ant-...", text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Claude Console([platform.claude.com](https://platform.claude.com/dashboard))에서 API Key를 발급할 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button("검증 및 저장") {
                            appState.saveAndStart()
                            showSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSaved = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.apiKey.isEmpty)

                        if showSaved {
                            Label("저장됨", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 13))
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("모델") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("모델", selection: $appState.selectedModel) {
                        ForEach(AppState.availableModels, id: \.id) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: appState.selectedModel) {
                        appState.saveModel()
                    }

                    Text("Claude에서 어떤 모델을 적용할지 선택할 수 있습니다. Haiku는 가볍고 신속하며 저렴합니다. Sonnet는 좀 더 정확할 수 있지만 토큰 비용이 Haiku에 비해 3배 비쌉니다. 되도록이면 Haiku 사용을 권장합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
            }

            GroupBox("적용 대상") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("PDF", systemImage: "doc.text")
                        Spacer()
                        Toggle("", isOn: $appState.enablePDF)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    HStack {
                        Label("이미지(JPG, PNG 등)", systemImage: "photo")
                        Spacer()
                        Toggle("", isOn: $appState.enableImage)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }

                    if !appState.enablePDF && !appState.enableImage {
                        Label("모두 비활성화되어 있습니다. ‘동작 중지’ 상태와 사실상 동일합니다.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .onChange(of: appState.enablePDF)   { appState.saveTargets() }
            .onChange(of: appState.enableImage)  { appState.saveTargets() }

            GroupBox("파일 이름 규칙") {
                VStack(alignment: .leading, spacing: 14) {
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("논문(PDF)", systemImage: "doc.text")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("초기화") { appState.resetArticleTemplate() }
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        TextField(NameTemplate.defaultArticleTemplate,
                                  text: $appState.articleTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("{name}은 저자 이름, {title}은 논문 본제목, {year}은 발행년입니다. 저자가 2명이면 한국어일 경우 가운뎃점(·)으로, 영어일 경우 앤퍼센트(&)로 구분합니다. 저자가 3명 이상이면 대표저자 1인의 이름을 표기한 뒤 한국어일 경우 ‘외’로, 영어일 경우 ‘et al.’로 적습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("포스터 이미지(JPG, PNG 등)", systemImage: "photo")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("초기화") { appState.resetPosterTemplate() }
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        TextField(NameTemplate.defaultPosterTemplate,
                                  text: $appState.posterTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("{title}은 행사 제목, {when}은 날짜(연·월·일)입니다. 콜론(:) 다음의 날짜 포맷을 변경하여 연·월·일 표기 방식을 바꿀 수 있습니다. 예) YY/MM/DD → 26/05/30")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .padding(6)
            }
            .onChange(of: appState.posterTemplate)  { appState.saveTemplates() }
            .onChange(of: appState.articleTemplate) { appState.saveTemplates() }

            GroupBox("로그") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("최대 보관 건수")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $appState.maxLogCount) {
                            ForEach(AppState.logCountOptions, id: \.self) { count in
                                Text("\(count)건").tag(count)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        .onChange(of: appState.maxLogCount) { appState.saveMaxLogCount() }
                    }

                    HStack(spacing: 10) {
                        Button("로그 초기화") {
                            showClearLogConfirm = true
                        }
                        .foregroundColor(.red)

                        if showLogCleared {
                            Label("로그 삭제 완료", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 13))
                        }
                    }
                    .alert("로그를 초기화하시겠습니까?", isPresented: $showClearLogConfirm) {
                        Button("취소", role: .cancel) { }
                        Button("삭제", role: .destructive) {
                            appState.clearLog()
                            showLogCleared = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showLogCleared = false
                            }
                        }
                    } message: {
                        Text("저장된 로그가 모두 삭제됩니다. 삭제된 로그는 복구할 수 없습니다.")
                    }
                }
                .padding(6)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}
