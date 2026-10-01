import SwiftUI

// Shown when no one is logged in: welcome, then sign up or log in.
struct AuthFlowView: View {
    private enum Screen: Hashable { case signUp, logIn }
    @State private var path: [Screen] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                Spacer()
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 8)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(AppInfo.name)
                        .font(.largeTitle.bold())
                    Text("Train smarter, track every rep, and let Genie plan your next step.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                VStack(spacing: 12) {
                    NavigationLink(value: Screen.signUp) {
                        Text("Create account")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    NavigationLink(value: Screen.logIn) {
                        Text("I already have an account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .signUp: SignUpView(onSwitch: { path = [.logIn] })
                case .logIn: LogInView(onSwitch: { path = [.signUp] })
                }
            }
        }
    }
}

struct SignUpView: View {
    var onSwitch: () -> Void = {}

    @Environment(AccountManager.self) private var account
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, confirm }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your name." }
        if !AccountValidation.isEmail(trimmedEmail) { return "Enter a valid email address." }
        if password.count < AccountValidation.minimumPasswordLength {
            return "Use at least \(AccountValidation.minimumPasswordLength) characters for your password."
        }
        if password != confirm { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .confirm)
                    .submitLabel(.go)
                    .onSubmit(signUp)
            } footer: {
                Text("At least \(AccountValidation.minimumPasswordLength) characters.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: signUp) {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView().tint(.white) } else { Text("Create account").bold() }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Button("Already have an account? Log in", action: onSwitch)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = .name }
    }

    private func signUp() {
        if let problem {
            errorMessage = problem
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.signUp(name: name.trimmingCharacters(in: .whitespaces),
                                         email: trimmedEmail, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LogInView: View {
    var onSwitch: () -> Void = {}

    @Environment(AccountManager.self) private var account
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingReset = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(logIn)
            } footer: {
                Button("Forgot password?") { showingReset = true }
                    .font(.footnote)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: logIn) {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView().tint(.white) } else { Text("Log in").bold() }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Button("New here? Create an account", action: onSwitch)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = .email }
        .sheet(isPresented: $showingReset) {
            ResetPasswordView(email: trimmedEmail)
        }
    }

    private func logIn() {
        guard AccountValidation.isEmail(trimmedEmail), !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.signIn(email: trimmedEmail, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ResetPasswordView: View {
    @State var email: String

    @Environment(AccountManager.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Check your inbox", systemImage: "envelope.badge.fill")
                            .font(.headline)
                        Text("If there's an account for \(email), we've sent a link to reset the password. It may take a minute, and can land in spam.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("We'll email you a link to choose a new password.")
                    }
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button(action: send) {
                            HStack {
                                Text("Send reset link")
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking || !AccountValidation.isEmail(email.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func send() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await account.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                sent = true
            } catch let error as AccountError where error.message == "Wrong email or password." {
                // Don't reveal whether an account exists.
                sent = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
