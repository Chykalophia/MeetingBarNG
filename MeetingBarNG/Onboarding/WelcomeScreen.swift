//
//  WelcomeScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct WelcomeScreen: View {
    @ObservedObject var router: OnboardingRouter

    /// macOS Calendar is the default: it needs no setup and works for everyone,
    /// so it is the right answer for anyone without a specific reason to choose
    /// otherwise.
    @State private var selectedProvider: EventStoreProvider = .macOSEventKit

    private var sources: [CalendarSourcePresentation] { CalendarSourcePresentation.all }

    private var selectedSource: CalendarSourcePresentation {
        CalendarSourcePresentation.make(for: selectedProvider)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text("onboarding_welcome_title".loco())
                .font(.largeTitle)
                .bold()
            Text("onboarding_welcome_description".loco())
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            // A source picker only when there is genuinely a choice. A build
            // without Google OAuth credentials cannot offer that provider, and a
            // one-option picker is a decision the user cannot make — so it goes
            // straight through to granting access, exactly as before.
            if sources.count > 1 {
                Picker("onboarding_source_picker_label".loco(), selection: $selectedProvider) {
                    ForEach(sources) { source in
                        Text(source.titleKey.loco()).tag(source.provider)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Text(selectedSource.descriptionKey.loco())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            Spacer()
            OnboardingFooter(
                primaryTitle: "onboarding_continue".loco(),
                primaryAction: { router.selectProvider(selectedProvider) }
            )
        }
    }
}
