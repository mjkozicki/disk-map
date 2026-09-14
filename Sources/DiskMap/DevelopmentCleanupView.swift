import SwiftUI
import DiskMapCore

struct DevelopmentCleanupView: View {
    @ObservedObject var model: AppModel
    private var visibleCandidates: [CleanupCandidate] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.cleanupCandidates.filter { query.isEmpty || $0.url.path.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Development Cleanup").font(.title2.weight(.semibold))
            Text(model.index?.rootURL.path ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Find dependencies, caches, and build output you can regenerate. Review folders for local edits and stop builds or development servers before moving them to Trash.")
                .font(.callout).foregroundStyle(.secondary)
            if let report = model.cleanupReport {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Moved \(report.moved.count) \(report.moved.count == 1 ? "folder" : "folders") to Trash. \(report.failures.count) failed.").font(.callout.weight(.medium))
                        Spacer()
                        Button("Dismiss") { model.cleanupReport = nil }
                    }
                    Text("Results are rescanned. Empty Trash in Finder when you are ready to free space.").font(.caption)
                    if !report.failures.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                                    Text(failure.url.path + "\n" + failure.message).font(.caption).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 120)
                    }
                }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.isScanning || model.isFindingCleanup {
                HStack { ProgressView().controlSize(.small); Text("Finding generated folders… Cleanup is available after the scan finishes.").font(.callout) }
                Spacer()
            } else if model.canceled {
                ContentUnavailableView("Finish a scan to clean up", systemImage: "arrow.clockwise", description: Text("Canceled scans have incomplete results. Rescan this location to find generated folders."))
            } else if visibleCandidates.isEmpty {
                ContentUnavailableView("No generated folders found", systemImage: "checkmark.folder", description: Text(model.query.isEmpty ? "Scan a parent folder containing your projects. Recognized dependencies, caches, and build output appear here; packages, skipped folders, and the scan root are excluded." : "Try a different name or path in search."))
            } else {
                HStack {
                    Text("\(visibleCandidates.count) \(visibleCandidates.count == 1 ? "folder" : "folders") · \(model.cleanupSelection.count) selected").font(.callout)
                    Spacer()
                    Button("Select Listed") { model.cleanupSelection.formUnion(visibleCandidates.map(\.id)) }
                    Button("Deselect All") { model.cleanupSelection = [] }.disabled(model.cleanupSelection.isEmpty)
                }
                List(visibleCandidates) { candidate in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle(isOn: Binding(get: { model.cleanupSelection.contains(candidate.id) }, set: { selected in
                            if selected { model.cleanupSelection.insert(candidate.id) } else { model.cleanupSelection.remove(candidate.id) }
                        })) { Text("Select \(candidate.url.path)") }.labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.url.lastPathComponent).font(.headline)
                            Text(candidate.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(candidate.sizeText).monospacedDigit()
                            Button("Reveal") { model.reveal(candidate.id) }.font(.caption)
                        }
                    }.padding(.vertical, 7)
                }.listStyle(.inset)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ByteFormatting.string(model.selectedCleanup.reduce(0) { $0 + $1.allocatedBytes })) measured on disk selected").font(.callout.weight(.medium))
                    Text("Sizes may be partial or shared. Moving to Trash does not immediately free space.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Selected…") { model.reviewCleanup() }.buttonStyle(.borderedProminent).disabled(!model.canReviewCleanup)
            }
        }.padding(20)
    }
}

struct CleanupReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move \(model.cleanupReview.count) \(model.cleanupReview.count == 1 ? "folder" : "folders") to Trash?").font(.title2.bold())
            Text("Everything inside these folders will move with them, including any local edits. Dependencies must be reinstalled and build output regenerated before you use these projects again.")
            List(model.cleanupReview) { candidate in
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.url.path).font(.callout.weight(.medium)).textSelection(.enabled)
                    Text("Folder · \(candidate.sizeText) on disk · \(ByteFormatting.string(candidate.logicalBytes)) logical").font(.caption).foregroundStyle(.secondary)
                    Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }
            Text("You can recover moved folders from Trash. Space is not freed until you empty Trash in Finder. If a folder cannot be moved, it stays in place and the failure is reported.").font(.callout).foregroundStyle(.secondary)
            HStack {
                if model.isCleaning { ProgressView().controlSize(.small); Text("Moving to Trash…") }
                Spacer()
                Button("Cancel", role: .cancel) { model.showCleanupReview = false }.keyboardShortcut(.cancelAction).disabled(model.isCleaning)
                Button("Move to Trash", role: .destructive) { model.confirmCleanup() }.buttonStyle(.borderedProminent).disabled(model.isCleaning)
            }
        }.padding(24).frame(width: 690, height: 510).interactiveDismissDisabled(model.isCleaning)
    }
}
