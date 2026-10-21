import SwiftUI

/// The packaged PNG and ICNS come from one checked-in brand master.
struct HyCodeBrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image("HyCode", bundle: .main)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
