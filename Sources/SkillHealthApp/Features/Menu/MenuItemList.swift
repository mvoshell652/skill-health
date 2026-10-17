import SwiftUI
import SkillHealthCore

/// The items of one group, in the order the model gave them.
struct MenuItemList: View {
    let items: [MenuModel.Item]
    let perform: (MenuModel.Item.Action) -> Void

    var body: some View {
        ForEach(items) { item in
            MenuItemButton(item: item, perform: perform)
        }
    }
}
