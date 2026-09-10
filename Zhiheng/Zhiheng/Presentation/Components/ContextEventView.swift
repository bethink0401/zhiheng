import SwiftUI

struct TodayContextEventsSummary: View {
  @ObservedObject var session: ContextEventSession

  var body: some View {
    Button {
      session.open()
    } label: {
      HStack(spacing: 8) {
        Label("生活事件", systemImage: "tag")
        Spacer(minLength: 0)
        Text(
          !session.didLoadRecords
            ? "重新读取" : (session.events.isEmpty ? "可选记录" : "今天 \(session.events.count) 条"))
        Image(systemName: "chevron.right").font(.caption2)
      }
      .font(.footnote.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("记录生活事件")
    .sheet(isPresented: $session.isPresented) { ContextEventSheet(session: session) }
  }
}

private struct ContextEventSheet: View {
  @ObservedObject var session: ContextEventSession
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var deletionCandidate: ContextEvent?
  @FocusState private var customLabelFocused: Bool

  private var columns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: 10),
      count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("生活事件").font(.title2.weight(.bold))
          Text("可选记录当前发生的事，时间按现在保存。仅作生活背景，不代表诊断或变化原因。")
            .font(.subheadline).foregroundStyle(.secondary)
          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ContextEventKind.defaultKinds + [.custom], id: \.self) { kind in
              let selected = session.selectedKind == kind
              Button {
                session.select(kind)
              } label: {
                HStack {
                  Text(kind.title).multilineTextAlignment(.leading)
                  Spacer(minLength: 4)
                  if selected { Image(systemName: "checkmark") }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.teal : Color.primary)
                .background(
                  selected
                    ? Color.teal.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground),
                  in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 12).stroke(
                    selected ? Color.teal : Color.clear, lineWidth: 1.5)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(kind.title)
              .accessibilityValue(selected ? "已选择" : "未选择")
              .accessibilityAddTraits(selected ? .isSelected : [])
            }
          }
          VStack(alignment: .leading, spacing: 14) {
            if session.selectedKind == .custom {
              VStack(alignment: .leading, spacing: 8) {
                Text("标签名称").font(.subheadline.weight(.semibold))
                TextField("例如：园艺", text: $session.customLabel)
                  .textFieldStyle(.roundedBorder)
                  .autocorrectionDisabled()
                  .focused($customLabelFocused)
                  .submitLabel(.done)
                  .onSubmit { customLabelFocused = false }
                  .accessibilityLabel("自定义标签名称")
                Text(
                  "\(session.customLabel.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(ContextEvent.customLabelCharacterLimit) 字"
                )
                .font(.caption).foregroundStyle(.secondary)
              }
            }
            if session.selectedKind != nil {
              OptionalRecordNoteField(
                note: $session.note, characterLimit: ContextEvent.noteCharacterLimit)
            }
          }
          .id("event-text-fields")
          if let error = session.validationMessage ?? session.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.orange)
          }
          if !session.didLoadRecords {
            Button("重新读取") { session.open() }
              .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
          }
          if let notice = session.notice {
            Text(notice).font(.footnote).foregroundStyle(.secondary)
          }
          Text("今天已记录").font(.headline)
          if session.events.isEmpty && session.didLoadRecords {
            Text("今天还没有生活事件记录").foregroundStyle(.secondary)
          }
          ForEach(session.events) { event in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(event.customLabel ?? event.kind.title).font(.body.weight(.medium))
                Text(event.startedAt, format: .dateTime.month().day().hour().minute())
                  .font(.caption).foregroundStyle(.secondary)
                if let note = event.note {
                  Text(note).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              Spacer(minLength: 0)
              Button {
                deletionCandidate = event
              } label: {
                Image(systemName: "trash").frame(width: 48, height: 48)
                  .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
              }
              .buttonStyle(.plain)
              .accessibilityLabel("删除\(event.customLabel ?? event.kind.title)记录")
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
          }
          Label("仅保存在本机，不会发送给 AI", systemImage: "lock.fill")
            .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
      }
      .scrollDismissesKeyboard(.interactively)
      .toolbar {
        if customLabelFocused {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { customLabelFocused = false }
          }
        }
      }
      .onChange(of: session.selectedKind) { _, kind in
        if kind == .custom {
          withAnimation { proxy.scrollTo("event-text-fields", anchor: .center) }
        }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 12) {
          Button("关闭") { session.isPresented = false }
            .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
          Button("添加记录") { session.save() }
            .buttonStyle(FeelingActionButtonStyle(isPrimary: true))
            .disabled(!session.canSave)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(.regularMaterial)
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(28)
      .alert(
        "删除这条生活事件？",
        isPresented: Binding(
          get: { deletionCandidate != nil },
          set: { if !$0 { deletionCandidate = nil } }
        )
      ) {
        Button("取消", role: .cancel) { deletionCandidate = nil }
        Button("删除", role: .destructive) {
          if let event = deletionCandidate { session.delete(id: event.id) }
          deletionCandidate = nil
        }
      } message: {
        Text("只删除这一条记录，不影响今日感受或其他生活事件。删除后无法恢复。")
      }
    }
  }
}

/// Collapsed by default, so adding private context never becomes a required step.
struct OptionalRecordNoteField: View {
  @Binding var note: String
  let characterLimit: Int
  var onExpand: () -> Void = {}
  @State private var isExpanded = false
  @FocusState private var isFocused: Bool

  private var count: Int { note.trimmingCharacters(in: .whitespacesAndNewlines).count }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        TextField("补充此刻的感受或生活背景", text: $note, axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          .focused($isFocused)
          .accessibilityLabel("备注内容")
        HStack {
          Text("仅保存在本机")
          Spacer()
          Text("\(count)/\(characterLimit) 字")
            .foregroundStyle(count > characterLimit ? Color.orange : Color.secondary)
        }
        .font(.caption).foregroundStyle(.secondary)
      }
      .padding(.top, 8)
    } label: {
      Text(count == 0 ? "补充备注（可选）" : "备注（已填写）")
        .font(.subheadline.weight(.medium))
        .frame(minHeight: 44, alignment: .leading)
    }
    .tint(.teal)
    .onChange(of: isExpanded) { _, expanded in
      if expanded { onExpand() } else { isFocused = false }
    }
    .toolbar {
      if isFocused {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { isFocused = false }
        }
      }
    }
  }
}
