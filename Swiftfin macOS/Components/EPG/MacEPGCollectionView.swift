//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import JellyfinAPI
import SwiftUI

struct EPGCollectionView: NSViewRepresentable {

    @AdaptiveLayout
    private var viewLayout

    @AppTheme
    private var theme

    let bottomInset: CGFloat
    let onReachedBottom: () -> Void
    let onSelect: (BaseItemDto) -> Void
    let onSelectGroup: (ProgramBlock) -> Void
    let proxy: EPGScrollProxy
    let viewModel: EPGViewModel

    private var layout: EPGLayout {
        EPGLayout(viewLayout: viewLayout)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = context.coordinator.gridLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false

        context.coordinator.representable = self
        context.coordinator.configure(collectionView, in: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.representable = self

        if scrollView.contentInsets.bottom != bottomInset {
            scrollView.contentInsets.bottom = bottomInset
        }

        context.coordinator.update()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

extension EPGCollectionView {

    @MainActor
    final class Coordinator: NSObject {

        private struct ItemID: Hashable {

            let channelID: String
            let blockID: ProgramBlock.ID
            let duplicateIndex: Int
        }

        private struct RenderItem: Equatable {

            let id: ItemID
            let block: ProgramBlock
            let frame: CGRect

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.id == rhs.id && lhs.frame == rhs.frame
            }
        }

        private struct RenderSection: Equatable {

            let id: String
            let items: [RenderItem]
        }

        private struct RenderContentSignature: Equatable {

            let channelIDs: [String]
            let programsRevision: Int
            let startDate: Date
            let layout: EPGLayout
        }

        private struct RenderState: Equatable {

            let sections: [RenderSection]
            let contentWidth: CGFloat
            let nowOffset: CGFloat?
            let now: Date
            let programsRevision: Int
            let rowHeight: CGFloat
        }

        var representable: EPGCollectionView?

        let gridLayout = EPGGridLayout()

        private weak var collectionView: NSCollectionView?
        private weak var scrollView: NSScrollView?

        private var accentColor: Color = .jellyfinPurple
        private var dataSource: NSCollectionViewDiffableDataSource<String, ItemID>?
        private var didRequestNextPage = false
        private var lastPaginationVerticalOffset: CGFloat?
        private var observations: [NSObjectProtocol] = []
        private var renderContentSignature: RenderContentSignature?
        private var renderItems: [ItemID: RenderItem] = [:]
        private var renderState: RenderState?
        private let scrollState = EPGScrollState()
        private var wasLoadingNextPage = false

        deinit {
            observations.forEach(NotificationCenter.default.removeObserver)
        }

        func configure(_ collectionView: NSCollectionView, in scrollView: NSScrollView) {
            self.collectionView = collectionView
            self.scrollView = scrollView
            lastPaginationVerticalOffset = scrollView.contentView.bounds.minY

            collectionView.register(
                EPGProgramItem.self,
                forItemWithIdentifier: EPGProgramItem.identifier
            )

            scrollState.update(visibleLeadingOffset: scrollView.contentView.bounds.minX)

            dataSource = NSCollectionViewDiffableDataSource(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, itemID in
                let item = collectionView.makeItem(
                    withIdentifier: EPGProgramItem.identifier,
                    for: indexPath
                )

                if let item = item as? EPGProgramItem {
                    self?.configure(item, for: itemID)
                }

                return item
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.postsFrameChangedNotifications = true

            observations = [
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.scrollViewDidScroll()
                    }
                },
                // The grid has no size on its first update, so it can only be
                // centered on the current time once it has been laid out.
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: scrollView,
                    queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.registerWithProxy()
                    }
                },
            ]
        }

        func update() {
            guard let representable, let collectionView else { return }

            let accentColorDidChange = accentColor != representable.theme.accentColor
            accentColor = representable.theme.accentColor

            let viewModel = representable.viewModel
            let layout = representable.layout
            let contentSignature = RenderContentSignature(
                channelIDs: viewModel.channels.map(\.itemID),
                programsRevision: viewModel.programsRevision,
                startDate: viewModel.startDate,
                layout: layout
            )
            let sections: [RenderSection]

            if contentSignature != renderContentSignature {
                if let renderContentSignature,
                   renderContentSignature.startDate != contentSignature.startDate {
                    representable.proxy.reset()
                }

                sections = makeSections(viewModel: viewModel, layout: layout)
                renderItems = sections.reduce(into: [:]) { lookup, section in
                    for item in section.items {
                        lookup[item.id] = item
                    }
                }
                renderContentSignature = contentSignature
            } else {
                sections = renderState?.sections ?? []
            }

            let nowOffset = layout.width(from: viewModel.startDate, to: viewModel.now)
            let nextRenderState = RenderState(
                sections: sections,
                contentWidth: max(1, layout.width(from: viewModel.startDate, to: viewModel.endDate)),
                nowOffset: viewModel.now >= viewModel.startDate ? nowOffset : nil,
                now: viewModel.now,
                programsRevision: viewModel.programsRevision,
                rowHeight: layout.rowHeight
            )

            let sectionsDidChange = renderState?.sections != nextRenderState.sections
            let layoutDidChange = accentColorDidChange || sectionsDidChange ||
                renderState?.contentWidth != nextRenderState.contentWidth ||
                renderState?.nowOffset != nextRenderState.nowOffset ||
                renderState?.rowHeight != nextRenderState.rowHeight
            let cellsDidChange = accentColorDidChange || renderState?.now != nextRenderState.now ||
                renderState?.programsRevision != nextRenderState.programsRevision

            gridLayout.rowHeight = nextRenderState.rowHeight
            gridLayout.contentWidth = nextRenderState.contentWidth
            gridLayout.nowOffset = nextRenderState.nowOffset
            gridLayout.nowColor = NSColor(accentColor)

            if sectionsDidChange {
                gridLayout.sectionFrames = nextRenderState.sections.map { section in
                    section.items.map(\.frame)
                }
                didRequestNextPage = false
                applySnapshot(nextRenderState, to: collectionView)
            } else if layoutDidChange {
                gridLayout.invalidateLayout()
            }

            renderState = nextRenderState

            if cellsDidChange {
                refreshVisibleItems()
            }

            if wasLoadingNextPage, !viewModel.background.is(.gettingNextPage) {
                didRequestNextPage = false
            }
            wasLoadingNextPage = viewModel.background.is(.gettingNextPage)

            registerWithProxy()
        }

        private func registerWithProxy() {
            guard let representable, let scrollView else { return }

            representable.proxy.registerContent(scrollView, centeringOn: gridLayout.nowOffset)
            representable.proxy.registerVertical(scrollView)
        }

        private func makeSections(
            viewModel: EPGViewModel,
            layout: EPGLayout
        ) -> [RenderSection] {
            viewModel.channels.enumerated().compactMap { section, channel -> RenderSection? in
                let channelID = channel.itemID

                var occurrences: [ProgramBlock.ID: Int] = [:]
                let items = (viewModel.programs[channelID] ?? []).map { block in
                    let duplicateIndex = occurrences[block.id, default: 0]
                    occurrences[block.id] = duplicateIndex + 1
                    let id = ItemID(
                        channelID: channelID,
                        blockID: block.id,
                        duplicateIndex: duplicateIndex
                    )
                    let leadingOffset = layout.width(from: viewModel.startDate, to: block.start)

                    return RenderItem(
                        id: id,
                        block: block,
                        frame: CGRect(
                            x: leadingOffset,
                            y: CGFloat(section) * layout.rowHeight,
                            width: layout.width(from: block.start, to: block.end),
                            height: layout.rowHeight
                        )
                    )
                }

                return RenderSection(id: channelID, items: items)
            }
        }

        private func applySnapshot(_ renderState: RenderState, to collectionView: NSCollectionView) {
            var snapshot = NSDiffableDataSourceSnapshot<String, ItemID>()
            snapshot.appendSections(renderState.sections.map(\.id))

            for section in renderState.sections {
                snapshot.appendItems(section.items.map(\.id), toSection: section.id)
            }

            dataSource?.apply(snapshot, animatingDifferences: false)
            gridLayout.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
        }

        private func configure(_ item: EPGProgramItem, for itemID: ItemID) {
            guard let representable,
                  let renderItem = renderItems[itemID]
            else { return }

            let block = renderItem.block

            let action = { [weak self] in
                guard let self else { return }

                select(itemID)
            }

            item.setContent(
                EPGProgramCell(
                    scrollState: scrollState,
                    block: block,
                    leadingOffset: renderItem.frame.minX,
                    isCurrent: block.isAiring(at: representable.viewModel.now),
                    isFocused: false,
                    accentColor: accentColor,
                    action: action
                )
                // Items are reused, and the cell seeds its sticky title
                // offset from where it is first shown.
                .id(itemID)
                .ignoresSafeArea()
            )
        }

        private func select(_ itemID: ItemID) {
            guard let representable,
                  let block = renderItems[itemID]?.block
            else { return }

            if block.isGroup {
                representable.onSelectGroup(block)
            } else if let program = block.programs.first {
                representable.onSelect(program)
            }
        }

        private func refreshVisibleItems() {
            guard let collectionView, let dataSource else { return }

            for item in collectionView.visibleItems() {
                guard let item = item as? EPGProgramItem,
                      let indexPath = collectionView.indexPath(for: item),
                      let itemID = dataSource.itemIdentifier(for: indexPath)
                else { continue }

                configure(item, for: itemID)
            }
        }

        private func scrollViewDidScroll() {
            guard let representable, let scrollView else { return }

            let bounds = scrollView.contentView.bounds

            scrollState.update(visibleLeadingOffset: bounds.minX)

            let verticalOffset = bounds.minY
            let didScrollVertically = lastPaginationVerticalOffset.map {
                abs($0 - verticalOffset) > 0.5
            } ?? true
            lastPaginationVerticalOffset = verticalOffset

            guard didScrollVertically else { return }

            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let remaining = contentHeight - bounds.minY - bounds.height

            guard remaining < 300 else {
                didRequestNextPage = false
                return
            }
            guard !didRequestNextPage,
                  !representable.viewModel.background.is(.gettingNextPage)
            else { return }

            didRequestNextPage = true
            representable.onReachedBottom()
        }
    }
}

private final class EPGProgramItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("EPGProgramItem")

    private var hostingView: NSHostingView<AnyView>?

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        self.view = view
    }

    func setContent(_ content: some View) {
        if let hostingView {
            hostingView.rootView = AnyView(content)
        } else {
            let hostingView = NSHostingView(rootView: AnyView(content))
            // The layout dictates the size of every program
            hostingView.sizingOptions = []
            hostingView.frame = view.bounds
            hostingView.autoresizingMask = [.width, .height]
            view.addSubview(hostingView)
            self.hostingView = hostingView
        }
    }
}
