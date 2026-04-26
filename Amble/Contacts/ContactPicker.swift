import SwiftUI
import ContactsUI

/// Original SwiftUI-wrapped contact picker. Still used by onboarding's
/// Contact step where it works fine — that sheet is presented at the
/// root, with no other sheet above it.
///
/// **Do not use this from inside another `.sheet`** (e.g. the Settings
/// edit-contact sheet). When `CNContactPickerViewController` auto-
/// dismisses on selection, that dismissal cascades up the SwiftUI
/// presentation chain and closes the parent sheet too — the user sees
/// the entire edit modal disappear without their pick being applied.
/// For that case, use `ContactPickerPresenter.present(from:onPick:)`
/// below, which presents directly via UIKit and bypasses SwiftUI's
/// sheet stack entirely.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (String, String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        init(_ parent: ContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            parent.onPick(name, phone)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let contact = contactProperty.contact as CNContact? else {
                parent.onCancel()
                return
            }
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue
                ?? contact.phoneNumbers.first?.value.stringValue
                ?? ""
            parent.onPick(name, phone)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }
    }
}

/// UIKit-direct contact picker presenter. Use from inside a SwiftUI
/// sheet that you don't want to be torn down by `CNContactPickerViewController`'s
/// own dismiss cascade. Presents the picker on top of whatever view
/// controller is currently visible, completely outside SwiftUI's
/// sheet hierarchy — so when the picker dismisses, only the picker
/// dismisses; the outer sheet stays put.
@MainActor
enum ContactPickerPresenter {
    /// Show the iOS contact picker. `onPick` fires with `(name, phone)`
    /// once the user makes a selection. Cancellation is handled
    /// silently — no callback needed because nothing has to roll back.
    static func present(onPick: @escaping (String, String) -> Void) {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")

        // The delegate has to outlive the call — `present` returns
        // immediately, but the user takes time to choose a contact.
        // Attach the delegate to the picker via objc associated
        // objects so it lives as long as the picker view controller
        // and gets cleaned up when the picker is deallocated.
        let delegate = ContactPickerDelegate(onPick: onPick)
        objc_setAssociatedObject(
            picker,
            ContactPickerDelegate.associationKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        picker.delegate = delegate

        guard let host = topMostViewController() else { return }
        host.present(picker, animated: true)
    }

    /// Walks the active scene's window hierarchy to find the
    /// view controller currently presenting modals — usually a
    /// SwiftUI sheet's hosting controller — so the picker presents
    /// on top of it rather than getting lost behind it.
    private static func topMostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        let keyWindow = scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Standalone delegate retained alongside the picker via
/// `objc_setAssociatedObject`. Keeps the contact-picker lifetime
/// self-contained — no reference cycles, no SwiftUI state to babysit.
private final class ContactPickerDelegate: NSObject, CNContactPickerDelegate {
    fileprivate static let associationKey = malloc(1)!

    let onPick: (String, String) -> Void

    init(onPick: @escaping (String, String) -> Void) {
        self.onPick = onPick
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let name = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        onPick(name, phone)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        guard let contact = contactProperty.contact as CNContact? else { return }
        let name = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue
            ?? contact.phoneNumbers.first?.value.stringValue
            ?? ""
        onPick(name, phone)
    }

    // No-op — we don't need to propagate cancellations because nothing
    // in the calling SwiftUI view depends on a "cancel happened"
    // signal. The picker dismisses itself; the outer view's state is
    // already correct.
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
}

enum PhoneFormatter {
    /// Keep digits, `+`, `,`, `;`, `*`, `#`, `(`, `)` for tel:// — UIApplication handles most forms.
    static func sanitized(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "0123456789+*#,;()")
        return String(s.unicodeScalars.filter { allowed.contains($0) })
    }

    /// Returns a tel:// URL or nil if empty
    static func telURL(_ s: String) -> URL? {
        let cleaned = sanitized(s)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel://\(cleaned)")
    }

    /// Builds an `sms:` URL per RFC 5724. The first query parameter uses
    /// `?`, not `&` — an earlier version had `&body=` which made iOS treat
    /// the body as part of the phone number and silently drop the prefill.
    static func smsURL(_ s: String, body: String? = nil) -> URL? {
        let cleaned = sanitized(s)
        guard !cleaned.isEmpty else { return nil }
        var str = "sms:\(cleaned)"
        if let body,
           let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            str += "?body=\(encoded)"
        }
        return URL(string: str)
    }
}
