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
            Spacer()
            OnboardingFooter(
                primaryTitle: "onboarding_continue".loco(),
                // Option A ships the macOS Calendar provider only (it already
                // surfaces Google/iCloud/Exchange accounts synced on this Mac),
                // so there's no source to pick — go straight to granting access.
                primaryAction: { router.selectProvider(.macOSEventKit) }
            )
        }
    }
}
