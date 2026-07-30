// FloatingTranscriptView.swift
// LiveTranscribe
//
// Compact SwiftUI view shown in the always-on-top NSPanel.
// Displays the most recent N transcript segments in real time.

import SwiftUI

struct FloatingTranscriptView: View {

    @EnvironmentObject var vm: TranscriptionViewModel

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ── Background ────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(vm.settings.floatingWindowOpacity))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Title bar ─────────────────────────────────────────────
                titleBar

                // ── Transcript segments ───────────────────────────────────
                if vm.recentSegments.isEmpty {
                    emptyState
                } else {
                    segmentList
                }
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(vm.isCapturing
                      ? (vm.isPaused ? Color.orange : Color.green)
                      : Color.gray)
                .frame(width: 8, height: 8)
                .shadow(color: vm.isCapturing && !vm.isPaused ? .green : .clear,
                        radius: 4)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: vm.isCapturing)

            Text("LiveTranscribe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            // Audio level mini-bar
            if vm.isCapturing {
                AudioLevelBar(level: vm.audioLevel)
                    .frame(width: 50, height: 3)
                    .opacity(0.8)
            }

            Text(vm.statusMessage)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Segment list

    private var segmentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.recentSegments.enumerated()), id: \.element.id) { idx, seg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(seg.formattedStartTime)
                                .font(.system(size: vm.settings.fontSize - 3, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 60, alignment: .leading)

                            Text(seg.text)
                                .font(.system(size: vm.settings.fontSize))
                                .foregroundStyle(
                                    idx == vm.recentSegments.count - 1
                                    ? Color.white
                                    : Color.white.opacity(0.55)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                        .id(seg.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: vm.recentSegments.count) { _ in
                if let last = vm.recentSegments.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 8) {
            if vm.isModelLoading {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading model… (\(vm.formattedLoadingTime))")
            } else {
                Image(systemName: vm.isCapturing ? "waveform" : "mic.slash")
                Text(vm.isCapturing ? "Listening…" : "Not recording")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
