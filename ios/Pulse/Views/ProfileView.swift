import SwiftUI

/** Profil : réseaux, media kit, parrainage, abonnement et compte. */
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var slug = ""
    @State private var referral = ""
    @State private var referralMessage: String?
    @State private var server = AppConfig.serverURL
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mes réseaux") {
                    ConnectNetworksList().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                if let user = model.user {
                    Section("Mon profil") {
                        TextField("Mon nom", text: $displayName)
                            .onSubmit { Task { _ = await model.updateProfile(["displayName": displayName]) } }
                        Picker("Je suis", selection: Binding(
                            get: { user.profileType },
                            set: { value in Task { _ = await model.updateProfile(["profileType": value.rawValue]) } }
                        )) {
                            ForEach(ProfileType.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Mon objectif", selection: Binding(
                            get: { user.goal },
                            set: { value in Task { _ = await model.updateProfile(["goal": value.rawValue]) } }
                        )) {
                            ForEach(Goal.allCases) { Text($0.label).tag($0) }
                        }
                    }

                    Section {
                        HStack {
                            Text("pulse/@").foregroundStyle(Theme.muted)
                            TextField("ton-nom", text: $slug)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { Task { _ = await model.updateProfile(["publicSlug": slug]) } }
                        }
                        Toggle("Media kit public", isOn: Binding(
                            get: { user.mediaKitPublic },
                            set: { value in
                                Task {
                                    var fields: [String: Any] = ["mediaKitPublic": value]
                                    if !slug.isEmpty && slug != user.publicSlug { fields["publicSlug"] = slug }
                                    _ = await model.updateProfile(fields)
                                }
                            }
                        ))
                        if user.mediaKitPublic, let link = user.mediaKitUrl.flatMap(URL.init(string:)) {
                            ShareLink(item: link) { Label("Partager mon media kit", systemImage: "square.and.arrow.up") }
                            Link(destination: link) { Label("Voir ma page", systemImage: "safari") }
                        }
                        NavigationLink {
                            InquiriesView()
                        } label: {
                            HStack {
                                Label("Propositions des marques", systemImage: "envelope")
                                Spacer()
                                if let count = model.mediaKit?.newInquiries, count > 0 {
                                    Text("\(count)").font(.caption).fontWeight(.bold)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Theme.lime, in: Capsule()).foregroundStyle(Theme.background)
                                }
                            }
                        }
                    } header: {
                        Text("Media kit")
                    } footer: {
                        Text("Une page publique avec tes chiffres, à envoyer aux marques. Elles peuvent t’y proposer une collaboration.")
                    }

                    Section {
                        LabeledContent("Mon code", value: user.referralCode)
                        ShareLink(item: Invite.text(code: user.referralCode)) { Label("Inviter un ami", systemImage: "gift") }
                        if !user.referred {
                            HStack {
                                TextField("Code d’un ami", text: $referral).textInputAutocapitalization(.characters)
                                Button("Valider") {
                                    Task { referralMessage = await model.redeemReferral(referral) }
                                }
                                .disabled(referral.count < 4)
                            }
                        }
                        if let referralMessage { Text(referralMessage).font(.footnote).foregroundStyle(Theme.muted) }
                    } header: {
                        Text("Parrainage")
                    } footer: {
                        Text("Chaque ami qui s’inscrit avec ton code vous offre un mois de Premium à tous les deux.")
                    }

                    Section("Abonnement") {
                        if user.premium {
                            Label(user.premiumUntil.map { "Premium jusqu’au \($0.formatted(date: .long, time: .omitted))" } ?? "Premium", systemImage: "sparkles")
                                .foregroundStyle(Theme.lime)
                        } else {
                            Text("Version gratuite. L’abonnement Premium arrive bientôt ; le parrainage en offre déjà un mois.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }

                Section {
                    TextField("Adresse du serveur", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { AppConfig.serverURL = server }
                } header: {
                    Text("Avancé")
                } footer: {
                    Text("Pour tester sur un iPhone, indique l’adresse du Mac qui fait tourner le serveur (ex. http://192.168.1.20:8787).")
                }

                Section {
                    Button("Supprimer mon compte et mes données", role: .destructive) { confirmDelete = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } }
            }
            .confirmationDialog("Supprimer ton compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Tout supprimer", role: .destructive) {
                    Task {
                        await model.deleteAccount()
                        dismiss()
                    }
                }
            } message: {
                Text("Tes statistiques, ton historique et ton media kit seront définitivement effacés. Tes comptes sur les réseaux ne sont pas touchés.")
            }
            .onAppear {
                displayName = model.user?.displayName ?? ""
                slug = model.user?.publicSlug ?? ""
            }
        }
    }
}

struct InquiriesView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Inquiry]?

    var body: some View {
        Group {
            if let items, items.isEmpty {
                ContentUnavailableView("Aucune proposition", systemImage: "envelope.open", description: Text("Partage ton media kit : les marques pourront te contacter depuis ta page."))
            } else if let items {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.brand).font(.headline)
                            Spacer()
                            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        if let budget = item.budget { Text("Budget : \(budget)").font(.caption).foregroundStyle(Theme.lime) }
                        Text(item.message).font(.subheadline)
                        if let mail = URL(string: "mailto:\(item.email)") {
                            Link(item.email, destination: mail).font(.caption)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .scrollContentBackground(.hidden)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Propositions")
        .task { items = await model.inquiries() }
    }
}
