//
//  CommandBarView.swift
//  MeetingBarNG
//
//  Spotlight-style Command Bar surface. Presentation-only: a focused search
//  field plus a keyboard-navigable results list bound to CommandBarViewModel.
//  Keyboard handling uses macOS 12-safe modifiers (.onMoveCommand / .onExitCommand
//  / .onSubmit) — NOT .onKeyPress (macOS 14+).
//

import SwiftUI

struct CommandBarView: View {
    @ObservedObject var viewModel: CommandBarViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
        .frame(
            width: CommandBarWindowPresentationPolicy.width,
            height: CommandBarWindowPresentationPolicy.height
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .onMoveCommand { direction in
            switch direction {
            case .up: viewModel.moveSelection(-1)
            case .down: viewModel.moveSelection(1)
            default: break
            }
        }
        .onExitCommand { viewModel.dismiss() }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("command_bar_placeholder".loco(), text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($searchFocused)
                .onSubmit { viewModel.runSelected() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.rows.isEmpty {
            Text("command_bar_no_results".loco())
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { index, row in
                            CommandBarRowView(row: row, isSelected: index == viewModel.selectionIndex)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.select(index)
                                    viewModel.runSelected()
                                }
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: viewModel.selectionIndex) { newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct CommandBarRowView: View {
    let row: CommandBarResultRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    private var symbolName: String {
        switch row.result {
        case .event:
            return "calendar"
        case let .action(action):
            switch action {
            case .joinNext: return "video.fill"
            case .createMeeting: return "plus.circle.fill"
            case .openPreferences: return "gearshape.fill"
            case .copyAgenda: return "doc.on.clipboard"
            case .refreshCalendars: return "arrow.clockwise"
            }
        }
    }
}
