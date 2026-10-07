import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct GallaxyTTSWidgetView: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel
    @State private var leftDrawerMotionOffset: CGFloat = 0
    @State private var rightDrawerMotionOffset: CGFloat = 0
    @State private var leftDrawerAnimating = false
    @State private var rightDrawerAnimating = false

    private let drawerAnimation = Animation.timingCurve(
        0.22,
        0.86,
        0.24,
        1.0,
        duration: GallaxyTTSWidgetViewModel.drawerAnimationDuration
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = widgetScale(for: geometry.size)

            widgetBody
                .scaleEffect(scale, anchor: .center)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .overlay(WindowResizeOverlay())
        .frame(
            minWidth: viewModel.widgetWidth * GallaxyTTSWidgetViewModel.minimumWidgetScale,
            minHeight: GallaxyTTSWidgetViewModel.widgetHeight * GallaxyTTSWidgetViewModel.minimumWidgetScale
        )
    }

    private var widgetBody: some View {
        let leftDelta = viewModel.leftDrawerExpanded ? GallaxyTTSWidgetViewModel.drawerWidthDelta : 0
        let rightDelta = viewModel.rightDrawerExpanded ? GallaxyTTSWidgetViewModel.drawerWidthDelta : 0
        let mainX = GallaxyTTSWidgetViewModel.sideSpeakerWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
            + leftDelta
        let mainY = (GallaxyTTSWidgetViewModel.widgetHeight - CGFloat(330)) / 2
        let drawerY = (GallaxyTTSWidgetViewModel.widgetHeight - GallaxyTTSWidgetViewModel.drawerPanelHeight) / 2
        let leftSpeakerX = GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let rightSpeakerX = mainX
            + GallaxyTTSWidgetViewModel.mainDeckWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
            + rightDelta
            + GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let leftDrawerX = mainX
            + GallaxyTTSWidgetViewModel.interSectionOverlap
            - GallaxyTTSWidgetViewModel.drawerPanelWidth
        let rightDrawerX = mainX
            + GallaxyTTSWidgetViewModel.mainDeckWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
        let leftSpeakerMinX = leftSpeakerX - GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let rightSpeakerMinX = rightSpeakerX - GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                VoiceProviderPanel()
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: leftDrawerX + (viewModel.leftDrawerExpanded ? 0 : GallaxyTTSWidgetViewModel.drawerWidthDelta),
                        y: drawerY
                    )
                    .allowsHitTesting(viewModel.leftDrawerExpanded && !leftDrawerAnimating)
                    .zIndex(1)

                DrawerSpeakerJoinSeal(side: .left)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.interSectionOverlap + 2,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: leftSpeakerMinX + GallaxyTTSWidgetViewModel.sideSpeakerWidth - GallaxyTTSWidgetViewModel.interSectionOverlap - 1,
                        y: drawerY
                    )
                    .opacity(viewModel.leftDrawerExpanded ? 1 : 0)
                    .zIndex(1.5)

                SideSpeakerRack(
                    side: .left,
                    expanded: viewModel.leftDrawerExpanded,
                    speakerLevel: viewModel.speakerLevel,
                    panelLabel: "Voice Model Panel",
                    toggleAction: toggleLeftDrawer
                )
                .frame(
                    width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                    height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                )
                .position(
                    x: leftSpeakerX,
                    y: drawerY + GallaxyTTSWidgetViewModel.drawerPanelHeight / 2
                )
                .zIndex(2)
            }
            .offset(x: leftDrawerMotionOffset)
            .zIndex(2)

            mainDeck
                .offset(x: mainX, y: mainY)
                .zIndex(3)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .animation(nil, value: viewModel.leftDrawerExpanded)
                .animation(nil, value: viewModel.rightDrawerExpanded)

            ZStack(alignment: .topLeading) {
                SlideoutRackPanel(viewModel: viewModel)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: rightDrawerX - (viewModel.rightDrawerExpanded ? 0 : GallaxyTTSWidgetViewModel.drawerWidthDelta),
                        y: drawerY
                    )
                    .allowsHitTesting(viewModel.rightDrawerExpanded && !rightDrawerAnimating)
                    .zIndex(1)

                DrawerSpeakerJoinSeal(side: .right)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.interSectionOverlap + 2,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: rightSpeakerMinX - 1,
                        y: drawerY
                    )
                    .opacity(viewModel.rightDrawerExpanded ? 1 : 0)
                    .zIndex(1.5)

                SideSpeakerRack(
                    side: .right,
                    expanded: viewModel.rightDrawerExpanded,
                    speakerLevel: viewModel.speakerLevel,
                    panelLabel: "Side Panel",
                    toggleAction: toggleRightDrawer
                )
                .frame(
                    width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                    height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                )
                .position(
                    x: rightSpeakerX,
                    y: drawerY + GallaxyTTSWidgetViewModel.drawerPanelHeight / 2
                )
                .zIndex(2)
            }
            .offset(x: rightDrawerMotionOffset)
            .zIndex(2)
        }
        .frame(width: viewModel.widgetWidth, height: GallaxyTTSWidgetViewModel.widgetHeight, alignment: .leading)
    }

    private func toggleLeftDrawer() {
        guard !leftDrawerAnimating else { return }
        leftDrawerAnimating = true

        if viewModel.leftDrawerExpanded {
            withAnimation(drawerAnimation) {
                leftDrawerMotionOffset = GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    viewModel.setLeftDrawerExpanded(false)
                    leftDrawerMotionOffset = 0
                    leftDrawerAnimating = false
                }
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                viewModel.setLeftDrawerExpanded(true)
                leftDrawerMotionOffset = GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.async {
                withAnimation(drawerAnimation) {
                    leftDrawerMotionOffset = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    leftDrawerAnimating = false
                }
            }
        }
    }

    private func toggleRightDrawer() {
        guard !rightDrawerAnimating else { return }
        rightDrawerAnimating = true

        if viewModel.rightDrawerExpanded {
            withAnimation(drawerAnimation) {
                rightDrawerMotionOffset = -GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    viewModel.setRightDrawerExpanded(false)
                    rightDrawerMotionOffset = 0
                    rightDrawerAnimating = false
                }
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                viewModel.setRightDrawerExpanded(true)
                rightDrawerMotionOffset = -GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.async {
                withAnimation(drawerAnimation) {
                    rightDrawerMotionOffset = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    rightDrawerAnimating = false
                }
            }
        }
    }

    private var mainDeck: some View {
        ZStack {
            RetroShell()

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(GallaxyBrand.pageBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.75), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(viewModel.activityLabel)
                                .font(GallaxyBrand.displayFont(size: 10, weight: .bold))
                                .foregroundStyle(GallaxyBrand.brandMaroonReadable)
                            Spacer()
                        }

                        Group {
                            if !viewModel.caption.isEmpty {
                                SpeechCaptionView(text: viewModel.caption)
                            } else {
                                TerminalConsoleView(
                                    lines: viewModel.consoleLines,
                                    active: viewModel.isSpeaking,
                                    paused: viewModel.isPaused
                                )
                            }
                        }
                        .frame(height: 196)
                    }
                    .padding(10)
                }
                .frame(minWidth: 230, minHeight: 236)

                GallaxyGlassContainer(spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        GallaxyPlayButton(action: viewModel.play)

                        GallaxyStopButton(
                            active: viewModel.isPaused,
                            action: viewModel.stop
                        )

                        GallaxySpeedControl(
                            value: Binding(
                                get: { viewModel.speed },
                                set: { newValue in
                                    viewModel.speed = newValue
                                    viewModel.commitSpeed()
                                }
                            ),
                            range: 0.75...1.6
                        )
                        .frame(minWidth: 124, maxWidth: 190)

                        Text(String(format: "%.2fx", viewModel.speed))
                            .font(GallaxyBrand.displayFont(size: 10, weight: .semibold))
                            .foregroundStyle(GallaxyBrand.textMuted)
                            .frame(width: 44, alignment: .trailing)

                        GallaxyPinButton(
                            active: viewModel.isPinned,
                            action: { viewModel.setPinned(!viewModel.isPinned) }
                        )
                        .help(viewModel.isPinned ? "Unpin widget" : "Pin widget above other windows")
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: GallaxyTTSWidgetViewModel.mainDeckWidth, height: 330)
    }

    private func widgetScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / max(1, viewModel.widgetWidth)
        let heightScale = size.height / GallaxyTTSWidgetViewModel.widgetHeight
        let rawScale = GallaxyTTSWidgetViewModel.clampedWidgetScale(min(widthScale, heightScale))
        let snappedScale = (rawScale * 20).rounded(.toNearestOrAwayFromZero) / 20
        return GallaxyTTSWidgetViewModel.clampedWidgetScale(snappedScale)
    }
}
