// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if !canImport(Combine)
/// Minimal stubs so Services compiles on Linux CI without Apple Combine.
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
