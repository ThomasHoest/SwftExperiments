import WidgetKit
import SwiftUI

@main
struct VoxioWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoxioPlayerWidget()
        VoxioWidgetControl()
    }
}
