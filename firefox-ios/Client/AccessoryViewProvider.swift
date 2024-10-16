// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import Shared

enum AccessoryType {
    case standard, creditCard, address, login
}

class AccessoryViewProvider: UIView, Themeable {
    // MARK: - Constants
    private struct UX {
        static let toolbarHeight: CGFloat = 50
        static let fixedSpacerWidth: CGFloat = 10
        static let fixedSpacerHeight: CGFloat = 30
        static let fixedLeadingSpacerWidth: CGFloat = 2
        static let fixedTrailingSpacerWidth: CGFloat = 3
        static let doneButtonFontSize: CGFloat = 17
    }

    // MARK: - Properties
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?
    var notificationCenter: NotificationProtocol
    private var currentAccessoryView: AutofillAccessoryViewButtonItem?

    // Stub closures - these closures will be given as selectors in a future task
    var previousClosure: (() -> Void)?
    var nextClosure: (() -> Void)?
    var doneClosure: (() -> Void)?
    var savedCardsClosure: (() -> Void)?
    var savedAddressesClosure: (() -> Void)?
    var savedLoginsClosure: (() -> Void)?

    // MARK: - UI Elements
    private let toolbar: UIToolbar = .build {
        $0.sizeToFit()
    }

    private lazy var previousButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(named: StandardImageIdentifiers.Large.chevronUp),
                                     style: .plain,
                                     target: self,
                                     action: #selector(tappedPreviousButton))
        button.accessibilityIdentifier = AccessibilityIdentifiers.Browser.KeyboardAccessory.previousButton
        button.accessibilityLabel = .KeyboardAccessory.PreviousButtonA11yLabel
        return button
    }()

    private lazy var nextButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(named: StandardImageIdentifiers.Large.chevronDown),
                                     style: .plain,
                                     target: self,
                                     action: #selector(tappedNextButton))
        button.accessibilityIdentifier = AccessibilityIdentifiers.Browser.KeyboardAccessory.nextButton
        button.accessibilityLabel = .KeyboardAccessory.NextButtonA11yLabel
        return button
    }()

    private lazy var doneButton: UIBarButtonItem = {
        let button = UIButton(type: .system)
        button.setTitle(.CreditCard.Settings.Done, for: .normal)
        button.addTarget(self, action: #selector(self.tappedDoneButton), for: .touchUpInside)
        button.titleLabel?.font = DefaultDynamicFontHelper.preferredFont(
            withTextStyle: .body,
            size: UX.doneButtonFontSize,
            weight: .semibold
        )
        let barButton = UIBarButtonItem(customView: button)
        barButton.accessibilityIdentifier = AccessibilityIdentifiers.Browser.KeyboardAccessory.doneButton
        return barButton
    }()

    private lazy var fixedSpacer: UIBarButtonItem = {
        let fixedSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace,
                                          target: nil,
                                          action: nil)
        fixedSpacer.width = CGFloat(UX.fixedSpacerWidth)
        return fixedSpacer
    }()

    private let flexibleSpacer = UIBarButtonItem(systemItem: .flexibleSpace)
    private let leadingFixedSpacer: UIView = .build()
    private let trailingFixedSpacer: UIView = .build()

    private lazy var creditCardAutofillView: AutofillAccessoryViewButtonItem = {
        let accessoryView = AutofillAccessoryViewButtonItem(
            image: UIImage(named: StandardImageIdentifiers.Large.creditCard),
            labelText: .CreditCard.Settings.UseSavedCardFromKeyboard,
            tappedAction: { [weak self] in
                self?.tappedCreditCardButton()
            })
        accessoryView.accessibilityTraits = .button
        accessoryView.accessibilityLabel = .CreditCard.Settings.UseSavedCardFromKeyboard
        accessoryView.accessibilityIdentifier =
            AccessibilityIdentifiers.Browser.KeyboardAccessory.creditCardAutofillButton
        accessoryView.isAccessibilityElement = true
        return accessoryView
    }()

    private lazy var addressAutofillView: AutofillAccessoryViewButtonItem = {
        let accessoryView = AutofillAccessoryViewButtonItem(
            image: UIImage(named: StandardImageIdentifiers.Large.location),
            labelText: .Addresses.Settings.UseSavedAddressFromKeyboard,
            tappedAction: { [weak self] in
                self?.tappedAddressCardButton()
            })
        accessoryView.accessibilityTraits = .button
        accessoryView.accessibilityLabel = .Addresses.Settings.UseSavedAddressFromKeyboard
        accessoryView.accessibilityIdentifier =
            AccessibilityIdentifiers.Browser.KeyboardAccessory.addressAutofillButton
        accessoryView.isAccessibilityElement = true
        return accessoryView
    }()

    private lazy var loginAutofillView: AutofillAccessoryViewButtonItem = {
        let accessoryView = AutofillAccessoryViewButtonItem(
            image: UIImage(named: StandardImageIdentifiers.Large.login),
            labelText: .PasswordAutofill.UseSavedPasswordFromKeyboard,
            tappedAction: { [weak self] in
                self?.tappedLoginsButton()
            })
        accessoryView.accessibilityTraits = .button
        accessoryView.accessibilityLabel = .PasswordAutofill.UseSavedPasswordFromKeyboard
        return accessoryView
    }()

    // MARK: - Initialization
    init(themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationCenter = NotificationCenter.default) {
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter

        super.init(frame: CGRect(width: UIScreen.main.bounds.width,
                                 height: UX.toolbarHeight))

        listenForThemeChange(self)
        setupLayout()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        // Reset showing of credit card when dismissing the view
        // This is required otherwise it will always show credit card view
        // even if the input isn't of type credit card
        currentAccessoryView = nil
        setupLayout()
    }

    // MARK: - Theme and Layout

    func reloadViewFor(_ accessoryType: AccessoryType) {
        switch accessoryType {
        case .standard:
            currentAccessoryView = nil
        case .creditCard:
            currentAccessoryView = creditCardAutofillView
            sendCreditCardAutofillPromptShownTelemetry()
        case .address:
            currentAccessoryView = addressAutofillView
        case .login:
            currentAccessoryView = loginAutofillView
        }

        setNeedsLayout()
        setupLayout()
        layoutIfNeeded()
    }

    private func setupSpacer(_ spacer: UIView, width: CGFloat) {
        NSLayoutConstraint.activate([
            spacer.widthAnchor.constraint(equalToConstant: width),
            spacer.heightAnchor.constraint(equalToConstant: UX.fixedSpacerHeight)
        ])
        spacer.accessibilityElementsHidden = true
    }

    private func setupLayout() {
        setupSpacer(leadingFixedSpacer, width: UX.fixedLeadingSpacerWidth)
        setupSpacer(trailingFixedSpacer, width: UX.fixedTrailingSpacerWidth)

        toolbar.items = [
            currentAccessoryView,
            flexibleSpacer,
            previousButton,
            nextButton,
            fixedSpacer,
            doneButton
        ].compactMap { $0 }

        toolbar.accessibilityElements = [
            currentAccessoryView?.customView,
            previousButton,
            nextButton,
            doneButton
        ].compactMap { $0 }

        addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func applyTheme() {
        let theme = themeManager.currentTheme

        backgroundColor = theme.colors.layer5
        [previousButton, nextButton, doneButton].forEach {
            $0.tintColor = theme.colors.iconAccentBlue
            $0.customView?.tintColor = theme.colors.iconAccentBlue
        }

        [creditCardAutofillView, addressAutofillView, loginAutofillView].forEach {
            $0.accessoryImageViewTintColor = theme.colors.iconPrimary
            $0.backgroundColor = theme.colors.layer5Hover
        }
    }

    // MARK: - Actions

    @objc
    private func tappedPreviousButton() {
        previousClosure?()
    }

    @objc
    private func tappedNextButton() {
        nextClosure?()
    }

    @objc
    private func tappedDoneButton() {
        doneClosure?()
    }

    @objc
    private func tappedCreditCardButton() {
        savedCardsClosure?()
    }

    @objc
    private func tappedAddressCardButton() {
        savedAddressesClosure?()
    }

    @objc
    private func tappedLoginsButton() {
        savedLoginsClosure?()
    }

    // MARK: - Telemetry
    fileprivate func sendCreditCardAutofillPromptShownTelemetry() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .view,
                                     object: .creditCardAutofillPromptShown)
    }
}
