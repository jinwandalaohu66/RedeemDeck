import SwiftUI

extension View {
    func appFeedbackPresenter() -> some View {
        overlay(alignment: .top) {
            AppFeedbackOverlay()
        }
    }

    @ViewBuilder
    func codeVaultScrollEdgeStyle() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func codeVaultFormPresentation() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func codeVaultGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func codeVaultPrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(Color("PrimaryActionTint"))
                .foregroundStyle(Color("PrimaryActionForeground"))
        } else {
            buttonStyle(.borderedProminent)
                .tint(Color("PrimaryActionTint"))
                .foregroundStyle(Color("PrimaryActionForeground"))
        }
    }

    @ViewBuilder
    func codeVaultBottomAction<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: .bottom) {
                content()
                    .padding(.horizontal)
            }
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                content()
                    .padding()
                    .background(.bar)
            }
        }
    }
}
