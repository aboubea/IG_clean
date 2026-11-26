import SwiftUI

struct ListsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var list: UserList = .fans
    @State private var query = ""

    var body: some View {
        let users = filteredUsers
        NavigationStack {
            List {
                Section {
                    Picker("Liste", selection: $list) {
                        ForEach(UserList.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                }
                Section("\(users.count) compte\(users.count > 1 ? "s" : "")") {
                    ForEach(users) { user in
                        if let url = URL(string: "https://www.instagram.com/\(user.username)/") {
                            Link(destination: url) {
                                HStack {
                                    UserLabel(user: user)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            UserLabel(user: user)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Rechercher")
            .navigationTitle("Listes")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var filteredUsers: [IGUser] {
        let all = model.state.users(in: list)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.username.lowercased().contains(needle) || $0.fullName.lowercased().contains(needle) }
    }
}
