//
//  KeyPathBinder.swift
//
//  Created by Darren Ford on 13/3/22
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import os

/// A binder for key path values
///
/// Simple example :-
///
/// ```swift
/// class ViewController: NSViewController {
///    // A dynamic value. Could be bound to a UI control via IB (for example)
///    @objc dynamic var dynamicValue: Double = 0
///    // The binder object
///    lazy var binder = try! KeyPathBinder(self, keyPath: \.dynamicValue) { newValue in
///       Swift.print("> new value is \(newValue)")
///    }
///    ...
///    // Update the dynamicValue via the binder
///    binder.wrappedValue = -9876.54
///    // Update the binder via the dynamicValue
///    dynamicValue = 1024.56
/// }
/// ```
///
/// generates the output:
/// ```
/// > new value is Optional(-9876.54)
/// > new value is Optional(1024.56)
/// ```
public class KeyPathBinder<ClassType: NSObject, ValueType: Any>: ValueBinder<ValueType?> {
	/// Create a key path binding object
	/// - Parameters:
	///   - object: The object containing the key path to observe
	///   - keyPath: The key path to observe
	///   - identifier: Binder identifier
	///   - callback: An optional block that is called when the value of the binder changes
	///   Throws `ValueBinderErrors.invalidKeyPath` if the object.keyPath is invalid
	public init(
		_ object: ClassType,
		keyPath: KeyPath<ClassType, ValueType>,
		_ identifier: String = "",
		_ callback: ((ValueType?) -> Void)? = nil
	) throws {
		self.callback = callback
		self.object = object

		let stringKeyPath = NSExpression(forKeyPath: keyPath).keyPath
		guard !stringKeyPath.isEmpty else {
			throw ValueBinderErrors.invalidKeyPath
		}
		self.stringPath = stringKeyPath

		// Grab out the initial value from the bound keypath
		let initialValue = object.value(forKeyPath: stringKeyPath) as? ValueType

		super.init(initialValue, identifier)

		self.kvoObservation = object.observe(keyPath, options: [.new]) { [weak self] obj, value in
			self?.kvoUpdate(value)
		}
	}

	/// Type erase the keypathbinder
	@inlinable public var asValueBinder: ValueBinder<ValueType?> {
		self as ValueBinder<ValueType?>
	}

	deinit {
		self.kvoObservation = nil
	}

	private weak var object: ClassType?
	private var kvoObservation: NSKeyValueObservation?
	private let stringPath: String
	private let lock = NSLock()
	private let callback: ((ValueType?) -> Void)?

	// MARK: - Change handling

	private func kvoUpdate(_ value: NSKeyValueObservedChange<ValueType>) {
		self.lock.tryLock {
			os_log(
				"%@ [%@] kvo binding did update value to '%@'",
				log: .default,
				type: .debug,
				"\(type(of: self))",
				"\(self.identifier)",
				"\(String(describing: value.newValue))"
			)

			// The bound keypath has changed (and it's not from us). Update the value
			self.wrappedValue = value.newValue
			self.callback?(value.newValue)
		}
	}

	override public func valueDidChange() {
		super.valueDidChange()

		self.lock.tryLock {
			os_log(
				"%@ [%@] did update value to '%@'",
				log: .default,
				type: .debug,
				"\(type(of: self))",
				"\(self.identifier)",
				"\(String(describing: self.wrappedValue))"
			)

			// Push the new value through to the bound keypath
			object?.setValue(self.wrappedValue, forKey: stringPath)
			self.callback?(self.wrappedValue)
		}
	}
}
