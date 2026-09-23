//
//  OnboardingView.swift
//  Pantry Ping
//

import SwiftUI

// Shown on first launch: welcome → your name → who it's for.
// Everything is saved on this device only; there's no account or password.
struct OnboardingView: View {
    // @AppStorage reads and writes a value in UserDefaults, and redraws when it changes.
    @AppStorage(ProfileKeys.name) private var savedName = ""
    @AppStorage(ProfileKeys.householdType) private var savedHousehold = ""
    @AppStorage(ProfileKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    // An enum for the steps keeps the flow in one obvious order.
    private enum Step {
        case welcome, name, household
    }

    @State private var step = Step.welcome
    @State private var name = ""
    @State private var household: HouseholdType?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome: welcome
            case .name: nameStep
            case .household: householdStep
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.default, value: step)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "refrigerator.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(.tint, in: RoundedRectangle(cornerRadius: 26))
                .accessibilityHidden(true)
            Text("Welcome to Pantry Ping")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Know what food you have, how much is left, and what to use next — before it goes to waste.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Label("Your data stays on this iPhone. No account needed.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            primaryButton("Get Started") { step = .name }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            backButton { step = .welcome }
            Text("What should we call you?")
                .font(.largeTitle.bold())
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .onSubmit { step = .household }
                .focused($isNameFocused)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Text("Used to greet you. You can change it later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            primaryButton(trimmedName.isEmpty ? "Skip" : "Continue") { step = .household }
        }
        .onAppear { isNameFocused = true }
    }

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scrolls on small iPhones or with large text sizes; the button stays pinned below.
            ScrollView {
                householdChoices
            }
            .scrollBounceBehavior(.basedOnSize)
            primaryButton("Start Using Pantry Ping", action: finish)
                .disabled(household == nil)
        }
    }

    private var householdChoices: some View {
        VStack(alignment: .leading, spacing: 16) {
            backButton { step = .name }
            Text("Who's Pantry Ping for?")
                .font(.largeTitle.bold())
            Text("This tailors tips to you. Every feature works for everyone.")
                .foregroundStyle(.secondary)

            ForEach(HouseholdType.allCases) { option in
                householdCard(option)
            }

            if let household {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(household.tips, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Pieces

    private func householdCard(_ option: HouseholdType) -> some View {
        let isSelected = household == option
        return Button {
            withAnimation { household = option }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        // Wrap onto as many lines as needed instead of cutting off with "…".
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button("Back", systemImage: "chevron.left", action: action)
            .labelStyle(.titleAndIcon)
    }

    // MARK: - Saving

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish() {
        guard let household else { return }
        savedName = trimmedName
        savedHousehold = household.rawValue
        // Setting this last closes the onboarding screen.
        hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingView()
}
