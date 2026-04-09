//
//  TableOfContentsView.swift
//  X-Reader
//
//  Left sidebar: Table of contents with bookmarks
//


import SwiftUI

struct TableOfContentsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @State private var searchText = ""
    @State private var expandedItems: Set<UUID> = []
    @State private var activeTab: SidebarTab = .outline

    private func t(_ key: L10nKey) -> String { l10n.string(key) }

    enum SidebarTab: String, CaseIterable {
        case outline = "outline"
        case bookmarks = "bookmarks"

        var l10nKey: L10nKey {
            switch self {
            case .outline: return .tocTab
            case .bookmarks: return .bookmarksTab
            }
        }

        var icon: String {
            switch self {
            case .outline: return "list.bullet.rectangle"
            case .bookmarks: return "bookmark"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab switcher
            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon).font(.caption)
                            Text(l10n.string(tab.l10nKey)).font(.caption).fontWeight(.medium)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(activeTab == tab ? .white : Color(nsColor: .textColor).opacity(0.8))
                        .background(activeTab == tab ? Color.accentColor : Color.clear)
                        .cornerRadius(4)
                    }.buttonStyle(.borderless).padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)

            Divider()

            switch activeTab {
            case .outline: outlineView
            case .bookmarks: bookmarksView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Outline View

    @ViewBuilder
    private var outlineView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(nsColor: .textColor).opacity(0.5)).font(.caption)
                TextField(t(.searchPlaceholder), text: $searchText)
                    .textFieldStyle(.plain).font(.subheadline)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(nsColor: .textColor).opacity(0.5))
                    }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor)).cornerRadius(6)
            .padding(.horizontal, 6).padding(.vertical, 4)

            if allFilteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? t(.noToc) : t(.noMatches))
                        .foregroundColor(Color(nsColor: .textColor).opacity(0.5)).font(.subheadline)
                    if searchText.isEmpty { Text(t(.noTocHint)).font(.caption).foregroundColor(Color(nsColor: .textColor).opacity(0.4)) }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(allFilteredItems) { item in
                            OutlineRowView(item: item, expandedItems: $expandedItems, onSelect: { appState.goToPage(item.page - 1) })
                                .environmentObject(appState)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Bookmarks View

    @ViewBuilder
    private var bookmarksView: some View {
        if appState.bookmarks.isEmpty {
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bookmark").font(.title2)
                        .foregroundColor(Color(nsColor: .textColor).opacity(0.5))
                    Text(t(.noBookmarks)).font(.subheadline)
                        .foregroundColor(Color(nsColor: .textColor).opacity(0.7))
                    Text(t(.addBookmarkHint)).font(.caption)
                        .foregroundColor(Color(nsColor: .textColor).opacity(0.4))
                }
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.bookmarks) { bookmark in
                        Button(action: { appState.goToPage(bookmark.page - 1) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill").font(.caption)
                                    .foregroundColor(.accentColor).frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title).font(.caption).fontWeight(.medium)
                                        .foregroundColor(Color(nsColor: .textColor)).lineLimit(1)
                                    Text(String(format: t(.pageN), bookmark.page))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color(nsColor: .textColor).opacity(0.5))
                                }
                                Spacer()
                                Button(action: { appState.removeBookmark(at: bookmark.page) }) {
                                    Image(systemName: "minus.circle").font(.caption)
                                        .foregroundColor(Color(nsColor: .textColor).opacity(0.5))
                                }.buttonStyle(.borderless).help(t(.deleteBookmark))
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                        Divider()
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    // MARK: - Outline filtering

    private var allFilteredItems: [OutlineItem] {
        guard !searchText.isEmpty else { return appState.outlineItems }
        var result: [OutlineItem] = []
        for item in appState.outlineItems {
            if let filtered = filterItem(item, searchText: searchText) { result.append(filtered) }
        }
        return result
    }

    private func filterItem(_ item: OutlineItem, searchText: String) -> OutlineItem? {
        let selfMatch = item.title.localizedCaseInsensitiveContains(searchText)
        var children: [OutlineItem] = []
        for child in item.children {
            if let filtered = filterItem(child, searchText: searchText) {
                children.append(filtered); expandedItems.insert(item.id)
            }
        }
        guard selfMatch || !children.isEmpty else { return nil }
        return OutlineItem(title: item.title, page: item.page, level: item.level, children: children)
    }
}

// MARK: - Outline Row

struct OutlineRowView: View {
    let item: OutlineItem
    @Binding var expandedItems: Set<UUID>
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: CGFloat(item.level) * 16)
                if !item.children.isEmpty {
                    Button(action: { withAnimation {
                        if expandedItems.contains(item.id) { expandedItems.remove(item.id) } else { expandedItems.insert(item.id) }
                    }}) {
                        Image(systemName: expandedItems.contains(item.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color(nsColor: .textColor).opacity(0.5))
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                } else { Color.clear.frame(width: 20) }
                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        Text("\(item.page)").font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: .textColor).opacity(0.4)).frame(width: 24, alignment: .trailing)
                        Text(item.title).font(item.level == 0 ? .subheadline : .caption)
                            .fontWeight(item.level == 0 ? .medium : .regular)
                            .foregroundColor(Color(nsColor: .textColor)).lineLimit(1)
                        Spacer()
                    }.padding(.vertical, 4).padding(.horizontal, 4).contentShape(Rectangle())
                }.buttonStyle(.borderless)
            }
            if !item.children.isEmpty && expandedItems.contains(item.id) {
                ForEach(item.children) { child in
                    OutlineRowView(item: child, expandedItems: $expandedItems, onSelect: { goToPage(child.page - 1) })
                        .environmentObject(appState_fromParent)
                }
            }
        }
    }

    @EnvironmentObject private var appState_fromParent: AppState
    private func goToPage(_ page: Int) { appState_fromParent.goToPage(page) }
}
