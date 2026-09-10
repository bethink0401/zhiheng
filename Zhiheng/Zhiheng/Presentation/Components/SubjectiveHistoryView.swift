import SwiftUI

struct SubjectiveHistoryButton: View {
    @ObservedObject var session: SubjectiveHistorySession
    @ObservedObject var healthSession: HealthDataSession

    var body: some View {
        Button { session.open() } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .modifier(SubjectiveHistoryGlassModifier())
        .foregroundStyle(.teal)
        .accessibilityLabel("查看感受和生活事件历史")
        .sheet(isPresented: $session.isPresented) {
            SubjectiveHistoryView(session: session, healthSession: healthSession)
        }
    }
}

private struct SubjectiveHistoryGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
    }
}

private struct SubjectiveHistoryView: View {
    @ObservedObject var session: SubjectiveHistorySession
    @ObservedObject var healthSession: HealthDataSession
    @State private var isConfirmingDeletion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink {
                        HealthContextTimelineView(session: session, healthSession: healthSession)
                    } label: {
                        HStack {
                            Label("查看 7 天时间线", systemImage: "calendar")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.teal)
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    DatePicker("记录日期", selection: Binding(
                        get: { session.selectedDate },
                        set: { session.load(for: $0, timeZone: session.timeZone) }
                    ), in: ...Date(), displayedComponents: .date)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                    .datePickerStyle(.compact)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    Text("仅查看和修改已有记录，不会补填未记录的日期。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    if !session.didLoad || session.requiresReload {
                        Button("重新读取") {
                            session.load(for: session.selectedDate, timeZone: session.timeZone)
                        }
                        .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
                    }
                    if let notice = session.notice {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                    if session.didLoad {
                        Text("当日感受").font(.headline)
                        if let record = session.checkIn {
                            recordCard(.checkIn(record)) {
                                ForEach([DailyFeelingField.energy, .stress, .bodyFeeling], id: \.self) { field in
                                    HStack {
                                        Text(field.title).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(field.label(for: field.rating(in: record)))
                                    }
                                }
                                if let note = record.note { Text(note).foregroundStyle(.secondary) }
                            }
                        } else {
                            emptyMessage("这一天没有感受记录")
                        }
                        Text("生活事件").font(.headline)
                        if session.events.isEmpty {
                            emptyMessage("这一天没有生活事件记录")
                        }
                        ForEach(session.events) { event in
                            recordCard(.event(event)) {
                                Text(event.customLabel ?? event.kind.title).font(.headline)
                                Text(event.startedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                                if let note = event.note { Text(note).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Label("仅保存在本机，不会发送给 AI", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("记录历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { session.isPresented = false }
                }
            }
            .sheet(item: Binding(
                get: { session.editingRecord },
                set: { if $0 == nil { session.cancelEditing() } }
            )) { record in
                SubjectiveHistoryEditor(session: session, record: record)
            }
            .onChange(of: session.deletionCandidate) { _, record in
                isConfirmingDeletion = record != nil
            }
            .alert("删除这条记录？", isPresented: $isConfirmingDeletion) {
                Button("取消", role: .cancel) { session.cancelDeletion() }
                Button("删除", role: .destructive) { session.confirmDeletion() }
            } message: {
                // The native alert renders one message; keep target and warning together.
                Text(session.deletionCandidate?.deletionMessage(timeZone: session.timeZone) ?? "")
            }
        }
        .environment(\.timeZone, session.timeZone)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func emptyMessage(_ title: String) -> some View {
        Text(title).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func recordCard<Content: View>(
        _ record: SubjectiveHistoryRecord,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content().fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("修改") { session.beginEditing(record) }
                    .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
                    .accessibilityLabel("修改\(record.title)")
                Button { session.requestDeletion(record) } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
                .accessibilityLabel("删除\(record.title)")
            }
            .disabled(!session.canModify)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct SubjectiveHistoryEditor: View {
    @ObservedObject var session: SubjectiveHistorySession
    @State private var draft: SubjectiveHistoryDraft

    init(session: SubjectiveHistorySession, record: SubjectiveHistoryRecord) {
        self.session = session
        _draft = State(initialValue: SubjectiveHistoryDraft(record: record))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch draft.original {
                    case .checkIn(let record):
                        Text("原记录日期：\(record.localDay.storageKey)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        SubjectiveRatingPicker(field: .energy, selection: $draft.energy)
                        SubjectiveRatingPicker(field: .stress, selection: $draft.stress)
                        SubjectiveRatingPicker(field: .bodyFeeling, selection: $draft.bodyFeeling)
                    case .event(let event):
                        VStack(alignment: .leading, spacing: 6) {
                            Text("原记录时间")
                            Text(event.startedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        Picker("事件类型", selection: $draft.kind) {
                            ForEach(ContextEventKind.defaultKinds + [.custom], id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                        if draft.kind == .custom {
                            TextField("自定义标签名称（最多 30 字）", text: $draft.customLabel)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .accessibilityLabel("自定义标签名称")
                        }
                    }
                    OptionalRecordNoteField(note: $draft.note, characterLimit: DailyCheckIn.noteCharacterLimit)
                    if let message = draft.validationMessage ?? session.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                    Text("保存只修改这条记录的内容，原日期和时间保持不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("取消") { session.cancelEditing() }
                        .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
                    Button("保存修改") { session.save(draft) }
                        .buttonStyle(FeelingActionButtonStyle(isPrimary: true))
                        .disabled(!session.canModify || draft.validationMessage != nil)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(.regularMaterial)
            }
            .navigationTitle("修改记录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
