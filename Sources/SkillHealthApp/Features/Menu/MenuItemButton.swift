import SwiftUI
import SkillHealthCore

/// An item, with its second line when it has one, or a submenu. The second line only adds to the
/// title; VoiceOver reads it after the title.
struct MenuItemButton: View {
    let item: MenuModel.Item
    let perform: (MenuModel.Item.Action) -> Void

    var body: some View {
        if item.action == .submenu {
            Menu(item.title) {
                ForEach(item.children) { MenuItemButton(item: $0, perform: perform) }
            }
        } else if let subtitle = item.subtitle {
            Button {
                perform(item.action)
            } label: {
                Text(item.title)
                Text(subtitle)
            }
        } else {
            Button(item.title) { perform(item.action) }
        }
    }
}
