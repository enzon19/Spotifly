//
//  QueueBootstrapTests.swift
//  SpotiflyTests
//
//  What the Web API bootstrap is allowed to conclude from a response.
//

import Foundation
@testable import Spotifly
import Testing

/// A Web API bootstrap that finds no playback must leave the queue alone.
///
/// Spotify answers `/me/player` and `/me/player/queue` with 204 while no device is active,
/// which decodes to exactly the same values as "nothing is queued". Reading that as an
/// empty queue is what emptied the queue on every wake from sleep — see
/// `plans/wake-from-sleep-loses-queue-and-resume.md`.
@MainActor
struct QueueBootstrapTests {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func playbackState(_ json: String) throws -> SpotifyAPI.PlaybackStateResponse {
        try decode(json)
    }

    private func queueResponse(_ json: String) throws -> SpotifyAPI.QueueResponse {
        try decode(json)
    }

    private static let track = """
    {"id": "t1", "name": "Track", "uri": "spotify:track:t1", "duration_ms": 1000}
    """

    @Test func `a pair of 204s carries no playback`() throws {
        // What `fetchPlaybackState` and `fetchQueue` produce from 204 No Content.
        let empty = try queueResponse(#"{"currently_playing": null, "queue": []}"#)

        #expect(!QueueService.responseCarriesPlayback(playbackState: nil, queueResponse: empty))
    }

    @Test func `a playback state alone carries playback`() throws {
        // /me/player answered while /me/player/queue happened to come back empty.
        let state = try playbackState(#"{"is_playing": false}"#)
        let empty = try queueResponse(#"{"currently_playing": null, "queue": []}"#)

        #expect(QueueService.responseCarriesPlayback(playbackState: state, queueResponse: empty))
    }

    @Test func `a currently playing track alone carries playback`() throws {
        let queue = try queueResponse(#"{"currently_playing": \#(Self.track), "queue": []}"#)

        #expect(QueueService.responseCarriesPlayback(playbackState: nil, queueResponse: queue))
    }

    @Test func `pending tracks alone carry playback`() throws {
        // Nothing is playing but Spotify still knows what is queued — that is an answer,
        // not the absence of one, so it may be applied.
        let queue = try queueResponse(#"{"currently_playing": null, "queue": [\#(Self.track)]}"#)

        #expect(QueueService.responseCarriesPlayback(playbackState: nil, queueResponse: queue))
    }

    @Test func `a paused local queue is exactly what a 204 pair would destroy`() {
        // The state this bug was found in: history, a current track, and pending tracks,
        // none of which the Web API can see once the device goes inactive.
        let store = AppStore()
        store.setQueue(
            previous: [QueueEntry(trackId: "played", provider: .context)],
            current: QueueEntry(trackId: "playing", provider: .context),
            next: [QueueEntry(trackId: "pending", provider: .context)],
        )

        // Applying an empty response keeps the history and drops everything that matters.
        store.setQueue(previous: nil, current: nil, next: [])

        #expect(store.queue.previousTracks.map(\.trackId) == ["played"])
        #expect(store.queue.currentTrack == nil)
        #expect(store.queue.nextTracks.isEmpty)
        // And the pointer is now unrepairable: the track is no longer in the list.
        #expect(!store.reconcileQueueCurrentTrack(with: "playing"))
    }
}
