import SwiftUI

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func onContentHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            let roundedHeight = ceil(height)
            DispatchQueue.main.async {
                action(roundedHeight)
            }
        }
    }
}
