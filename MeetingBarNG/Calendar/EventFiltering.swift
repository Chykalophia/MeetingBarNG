//
//  EventFilterPolicy.swift
//  MeetingBar
//

import Foundation

enum EventFilterAllDayMode {
    case show
    case showWithMeetingLinkOnly
    case hide
}

enum EventFilterNonAllDayMode {
    case show
    case hideWithoutMeetingLink
}

struct EventFilterSettings {
    let filterEventRegexes: [String]
    let allDayEvents: EventFilterAllDayMode
    let nonAllDayEvents: EventFilterNonAllDayMode
    let hidesPendingEvents: Bool
    let hidesTentativeEvents: Bool
    let hidesDeclinedEvents: Bool
}

struct EventFilterEvent: Equatable {
    enum ParticipationStatus {
        case active
        case pending
        case tentative
        case declined
    }

    let sourceIndex: Int
    let id: String
    let title: String
    let isAllDay: Bool
    let hasMeetingLink: Bool
    let participationStatus: ParticipationStatus
}

enum EventFiltering {
    /// Whether any of the user's title patterns hides a meeting with this title.
    ///
    /// Extracted so the Filters pane's "Try a title" tester runs the SAME code
    /// as the filter itself — a tester that re-implements the rule is a tester
    /// that can disagree with reality.
    static func titleIsFilteredOut(_ title: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(title.startIndex..., in: title)
            if regex.firstMatch(in: title, range: range) != nil {
                return true
            }
        }
        return false
    }

    static func filter(_ events: [EventFilterEvent], settings: EventFilterSettings) -> [EventFilterEvent] {
        var result: [EventFilterEvent] = []
        for event in events {
            if titleIsFilteredOut(event.title, patterns: settings.filterEventRegexes) {
                continue
            }

            if event.isAllDay {
                switch settings.allDayEvents {
                case .show:
                    break
                case .showWithMeetingLinkOnly:
                    if !event.hasMeetingLink {
                        continue
                    }
                case .hide:
                    continue
                }
            } else {
                switch settings.nonAllDayEvents {
                case .show:
                    break
                case .hideWithoutMeetingLink:
                    if !event.hasMeetingLink {
                        continue
                    }
                }
            }

            if settings.hidesPendingEvents, event.participationStatus == .pending {
                continue
            }

            if settings.hidesTentativeEvents, event.participationStatus == .tentative {
                continue
            }

            if settings.hidesDeclinedEvents, event.participationStatus == .declined {
                continue
            }

            result.append(event)
        }
        return result
    }
}
