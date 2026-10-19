import SwiftUI

/// Mash: shows Mash's icon in the About window.
///
/// Upstream called this `CyclingIconView` and rotated through Ghostty's icon
/// variants every three seconds. Mash's icon is a single image, the header
/// art, so this view draws that instead. `AppIconImage` holds Mash's art
/// because Mash's build replaces the Ghostty artwork in that imageset.
struct MashIconView: View {
    var body: some View {
        Image("AppIconImage")
            .resizable()
            .scaledToFit()
            .frame(height: 128)
            .accessibilityLabel("Mash Application Icon")
    }
}

struct MashIconView_Previews: PreviewProvider {
    static var previews: some View {
        MashIconView()
    }
}
