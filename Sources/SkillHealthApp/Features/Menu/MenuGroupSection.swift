import SwiftUI
import SkillHealthCore

/// One group of the menu: its header, and its items. A header states a fact; items are what
/// there is to do about it.
struct MenuGroupSection: View {
    let group: MenuModel.Group
    let perform: (MenuModel.Item.Action) -> Void

    var body: some View {
        if let header = group.header {
            Section(header) { MenuItemList(items: group.items, perform: perform) }
        } else {
            Section { MenuItemList(items: group.items, perform: perform) }
        }
    }
}
