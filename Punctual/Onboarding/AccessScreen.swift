//
//  AccessScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  removed the calendar-source picker (Option A ships the macOS Calendar
//  provider only); this file now holds just the authorization step.
//

import AppKit
import SwiftUI

struct AuthorizationScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("onboarding_authorization_title".loco())
                .font(.title2)
                .bold()
            Text(authorizationDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch router.authorizationState {
            case .idle, .requesting:
                ProgressView()
                Text("onboarding_authorization_waiting".loco())
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title)
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("onboarding_back".loco()) {
                        router.authorizationState = .idle
                        router.currentStep = .welcome
                    }
                    Button("access_screen_access_denied_system_preferences_button".loco()) {
                        NSWorkspace.shared.open(Links.calendarPreferences)
                    }
                    Button("access_screen_try_again".loco()) {
                        Task { await authorize() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .task(id: router.selectedProvider) {
            if router.authorizationState == .idle {
                await authorize()
            }
        }
    }

    private var authorizationDescription: String {
        guard let provider = router.selectedProvider else {
            return "onboarding_authorization_apple_description".loco()
        }
        return CalendarSourcePresentation.make(for: provider)
            .authorizationDescriptionKey
            .loco()
    }

    private func authorize() async {
        guard let provider = router.selectedProvider else {
            router.currentStep = .welcome
            return
        }
        router.authorizationState = .requesting
        let result = await onboardingHandler.onProviderSelected(provider)

        if result == .success {
            router.currentStep = .calendarSelection
        } else if let state = OnboardingFlowPolicy.authorizationState(for: result) {
            router.authorizationState = state
        }
    }
}
