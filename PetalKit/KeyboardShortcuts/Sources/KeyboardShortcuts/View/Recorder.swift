#if os(macOS)

import SwiftUI

extension KeyboardShortcuts {
	public struct Recorder: View {
		private let name: Name
		private let onChange: ((Shortcut?) -> Void)?
		@Namespace private var namespace

		@State private var isActive = false
		@State private var mode: RecorderMode = .ready
		@State private var symbolName: String = "xmark.circle.fill"
		@State private var delayedResetTask: Task<Void, Never>?

		public init(for name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil) {
			self.name = name
			self.onChange = onChange
		}

		public var body: some View {
			ZStack {
				_Recorder(
					name: name,
					isActive: isActive,
					modeChange: { mode in
						let oldMode = self.mode
						guard mode != self.mode else { return }
						self.mode = mode
						if !mode.isActive {
							isActive = false
						}
						if case .set = mode, case .recording = oldMode {
							withAnimation(.default) {
								symbolName = "checkmark.circle.fill"
							}
							delayedResetTask = Task {
								try? await Task.sleep(nanoseconds: 1_500_000_000)
								guard !Task.isCancelled else { return }
								withAnimation(.default) {
									symbolName = "xmark.circle.fill"
								}
							}
						} else {
							delayedResetTask?.cancel()
							symbolName = "xmark.circle.fill"
						}
					},
					onChange: onChange
				)
				.frame(width: 0, height: 0)
			.allowsHitTesting(false)
				HStack {
					ZStack {
						switch mode {
						case .ready:
							Text("RECORD")
								.commandStyle()
								.transition(.asymmetric(
									insertion: .move(edge: .trailing).combined(with: .opacity),
									removal: .move(edge: .trailing).combined(with: .opacity)
								))
						case .preRecording:
							HStack {
								BlinkingLight()
								Text("REC")
									.commandStyle()
									.foregroundStyle(Color.secondary)
									.fixedSize(horizontal: true, vertical: false)
							}
							.padding(.horizontal, 8)
							.transition(.asymmetric(
								insertion: .move(edge: .leading).combined(with: .opacity),
								removal: .move(edge: .leading).combined(with: .opacity)
							))

						case .recording(let shortcut), .set(let shortcut):
							let shortcutArray = shortcut.map { String($0) }
							HStack(spacing: 2) {
								ForEach(shortcutArray, id: \.self) { symbol in
									ShortcutSymbol(symbol: symbol)
										.matchedGeometryEffect(id: GeometryID.symbol(symbol), in: namespace)
										.transition(
											.move(edge: .leading)
											.combined(with: .opacity)
										)
								}
							}
							.id(GeometryID.shortcut)
							.transition(
								.offset(x: -30)
								.combined(with: .opacity)
							)
							.matchedGeometryEffect(id: GeometryID.shortcut, in: namespace)
						}
					}
					.padding(.horizontal, mode.thereIsNoKeys ? 8 : 2)
					.frame(height: 26)
					.visualEffect(.adaptive(.windowBackground))
					.clipShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
					.overlay(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous).stroke(.secondary, lineWidth: 0.5).opacity(0.3))
					.contentShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
					.onTapGesture {
						if !mode.isActive {
							isActive = true
						}
					}
					.matchedGeometryEffect(id: GeometryID.pill, in: namespace)

					if mode != .ready {
						Button(
							action: {
								if mode.isActive {
									isActive = false
								} else if case .set = mode {
									KeyboardShortcuts.setShortcut(nil, for: name)
									onChange?(nil)
								}
							},
							label: {
								Image(systemName: symbolName)
									.fontWeight(.bold)
									.imageScale(.large)
									.foregroundColor(Color.secondary)
							}
						)
						.buttonStyle(.plain)
						.matchedGeometryEffect(id: GeometryID.cancel, in: namespace)
						.transition(.scale.combined(with: .opacity).combined(with: .offset(x: -30)))

					}
				}
			}
			.animation(.spring(duration: 0.4), value: mode)
			.help(tooltip)
		}

		var tooltip: String {
			switch mode {
			case .ready, .set:
				return "record_shortcut".localized
			case .preRecording, .recording:
				return "press_shortcut".localized
			}
		}

	}

	enum GeometryID: Hashable {
		case pill
		case cancel
		case symbol(String)
		case shortcut
	}
}

extension View {
	func commandStyle() -> some View {
		self
			.font(.system(size: 11))
			.fontWeight(.medium)
			.kerning(1)
			.foregroundStyle(Color.secondary)
	}
}

#if DEBUG
#Preview {
	KeyboardShortcuts.Recorder(
		for: .init("test")
	)
	.padding(50)
}
#endif

#endif
