import Combine
import Foundation

/// A subject used to send status events
public typealias STTStatusSubject = PassthroughSubject<STTStatus, Never>
/// A subject used to send errors occured
public typealias STTErrorSubject = PassthroughSubject<Error, Never>
/// A subject used to send recognition results
public typealias STTRecognitionSubject = PassthroughSubject<STTResult, Never>

/// A publisher used to recieve status change
public typealias STTStatusPublisher = AnyPublisher<STTStatus, Never>
/// A publisher used to recieve errors
public typealias STTErrorPublisher = AnyPublisher<Error, Never>
/// A publisher used to recieve recognizer results
public typealias STTRecognitionPublisher = AnyPublisher<STTResult, Never>

/// A representation of the results generated by the STTService implementation
public struct STTResult: Identifiable, Equatable {
    /// Equatable function, comapres the id of the STTResults only
    /// - Returns: true if id's are the same, otherwise false
    public static func == (lhs: STTResult, rhs: STTResult) -> Bool {
        lhs.id == rhs.id
    }
    /// Represents a segment of the recognized speech
    public struct Segment {
        /// The recognized speech string
        public let string:String
        /// The accuracy of the recognition
        public let confidence:Double
        /// Initializes a new segment
        /// - Parameters:
        ///   - string: The recognized speech string
        ///   - confidence: The accuracy of the recognition
        public init(string:String,confidence:Double) {
            self.string = string
            self.confidence = confidence
        }
    }
    /// The id of the result, default value is `UUID().uuidString`
    public var id = UUID().uuidString
    /// The entire recognized string
    public let string:String
    /// The accumulated accuracy of the recognition
    public let confidence:Double
    /// Each segment describes the confidence of a specific string
    public let segments:[Segment]
    /// Indicates whether or not the result is final
    public let isFinal:Bool
    /// The locale in which the recognized string was processed
    public let locale:Locale
    /// Initializes a new STTResult
    /// - Parameters:
    ///   - string: The entire recognized string
    ///   - confidence: The accumulated accuracy of the recognition
    ///   - locale: The locale in which the recognized string was processed
    ///   - isFinal: Indicates whether or not the result is final
    public init(_ string:String, confidence:Double, locale:Locale, isFinal:Bool = false) {
        self.string = string
        self.confidence = confidence
        self.isFinal = isFinal
        self.locale = locale
        self.segments = []
    }
    /// Initializes a new STTResult
    /// - Parameters:
    ///   - string: The entire recognized string
    ///   - segments: Each segment describes the confidence of a specific string. The segments are used to sumarize the `confidence`.
    ///   - locale: The locale in which the recognized string was processed
    ///   - isFinal: Indicates whether or not the result is final
    public init(_ string:String, segments:[Segment], locale:Locale, isFinal:Bool = false) {
        self.segments = segments
        self.string = string
        self.confidence = segments.compactMap({ $0.confidence }).reduce(0, +) / Double(segments.count)
        self.isFinal = isFinal
        self.locale = locale
    }
    /// Initializes a new STTResult
    /// - Parameters:
    ///   - segments: Each segment describes the confidence of a specific string. The segments are used to sumarize the `confidence` and concatenate each segment into the `string` property
    ///   - locale: The locale in which the recognized string was processed
    ///   - isFinal: Indicates whether or not the result is final
    public init(_ segments:[Segment], locale:Locale, isFinal:Bool = false) {
        self.segments = segments
        self.string = segments.compactMap({ $0.string }).joined(separator: " ")
        self.confidence = segments.compactMap({ $0.confidence }).reduce(0, +) / Double(segments.count)
        self.isFinal = isFinal
        self.locale = locale
    }
}

/// Used to decribe the current status of the STTService
public enum STTStatus {
    /// Indicates whether or not the service is unavailable, could be due to network issues, microphone permissions etc.
    case unavailable
    /// Indicates that the service is idle and not in use
    case idle
    /// Indicates that the service is preparing to recognize speech
    case preparing
    /// Indicates that the service has stopped recording but is still processing the result
    case processing
    /// Indicates that the service is recording speech from the microphone. Intermittent resutls can be publsihed depending on the `STTService` implementation
    case recording
}

/// Used to describe the service mode. The mode can vary depending on the `STTService` implementation
public enum STTMode {
    /// Should indicate that the user sais a few words and then stops speaking. The recognizer should stop automatically
    case task
    /// Should indicate that the user sais a few words and then stops speaking. The recognizer should stop automatically
    case search
    /// Should indicate that the user is continuously dictating text. The user can use words like "period" and "comma" in order in insert a comma.
    /// The recognizer wont stop automatically unless the user is quite for some duration. Once stopped it should restart and wait for furher user input until `stop()` or `done()` is called
    case dictation
    /// Should resembel dictation with continuous listening. Continues until `stop()` or `done()` is called.
    case unspecified
}

/// Protocol decribing features a STT service should implement
public protocol STTService : AnyObject {
    /// The current locale
    var locale:Locale { get set }
    /// Used to increase accuracy of the speech recognizer
    var contextualStrings:[String] {get set}
    /// Used to set the mode of the speech recognizer.
    var mode:STTMode {get set}
    /// Publishes complete or intermittently incomplete recognition results
    var resultPublisher: STTRecognitionPublisher { get }
    /// Publishes the current status of the service
    var statusPublisher: STTStatusPublisher { get }
    /// Publishes errors occoring
    var errorPublisher:STTErrorPublisher { get }
    /// Indicates whether or not the service is currently unavailable
    var available:Bool { get }
    /// Start recognizing speech
    func start()
    /// Stop recognizing speech immediately without waiting for a final result
    func stop()
    /// Stop recognizing and wait for a final result
    func done()
    /// Currently available service locales publisher
    /// The locales must be formatted as `language_REGION` or just `language` (don't use hyphens)
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?,Never> { get }
    /// Currently available service locales
    /// The locales must be formatted as `language_REGION` or just `language` (don't use hyphens)
    var availableLocales:Set<Locale>? { get }
}

/// STT provides a common interface for Speech To Text services implementing the `STTService` protocol.
public class STT : ObservableObject {
    /// The currently used STTService
    public var service:STTService? {
        didSet {
            updateServiceProeprties()
        }
    }
    /// Cancellable store
    private var cancellables = Set<AnyCancellable>()
    
    /// Currently available locales publisher subject
    private var availableLocalesSubject = CurrentValueSubject<Set<Locale>?,Never>(nil)
    /// Currently available locales publisher
    public var availableLocalesPublisher: AnyPublisher<Set<Locale>?,Never> {
        return availableLocalesSubject.eraseToAnyPublisher()
    }
    /// Available locales publsiher subscriber
    private var availableLocalesCancellable:AnyCancellable?
    /// Currently available locales
    public private(set) var availableLocales:Set<Locale>? = nil
    
    /// Used to increase the accuracy of the speech recognizer
    @Published public final var contextualStrings:[String] {
        didSet {
            service?.contextualStrings = contextualStrings
        }
    }
    /// Used to set the mode of the speech recognizer. Result may vary on the STTService implementation
    @Published public final var mode:STTMode {
        didSet {
            self.service?.mode = mode
        }
    }
    /// Sets the input language of the speech recognizer
    @Published public final var locale:Locale {
        didSet {
            self.service?.locale = locale
        }
    }
    /// Publishes results from the STT Service
    private final var resultsSubject = STTRecognitionSubject()
    /// Piblishes failures from the STT Service
    private final var failedSubject = STTErrorSubject()
    /// Publishes results from the STT Service
    public final var results: STTRecognitionPublisher
    /// Piblishes failures from the STT Service
    public final var failures: STTErrorPublisher
    /// The current status of the STT
    @Published public var status: STTStatus = .idle
    /// Indicates whether or not the STT is disabled
    @Published public var disabled: Bool = false {
        didSet {
            if disabled {
                service?.stop()
            }
        }
    }
    /// Initialzes 
    /// - Parameter service: service to be used
    public init(service: STTService? = nil, locale:Locale = .current, mode:STTMode = .unspecified) {
        self.service = service
        self.mode = mode
        self.locale = locale
        self.contextualStrings = []
        self.results = resultsSubject.eraseToAnyPublisher()
        self.failures = failedSubject.eraseToAnyPublisher()
        updateServiceProeprties()
    }
    /// Start recognizing speech
    public final func start() {
        guard let service = service else {
            return
        }
        guard service.available == true else {
            return
        }
        if disabled {
            return
        }
        service.start()
    }
    /// Stop recognizing speech immediately without waiting for a final result
    public final func stop() {
        guard let service = service else {
            return
        }
        service.stop()
    }
    /// Stop recognizing and wait for a final result
    public final func done() {
        guard let service = service else {
            return
        }
        service.done()
    }
    /// Updates the STTService properties if on is available
    private func updateServiceProeprties() {
        guard let service = service else {
            cancellables.removeAll()
            availableLocales = nil
            return
        }
        updateAvailableLocales(service.availableLocales)
        cancellables.removeAll()
        service.locale = locale
        service.mode = mode
        service.contextualStrings = contextualStrings
        service.statusPublisher.receive(on: DispatchQueue.main).sink { status in
            self.status = status
        }.store(in: &cancellables)
        service.errorPublisher.receive(on: DispatchQueue.main).sink { error in
            self.failedSubject.send(error)
        }.store(in: &cancellables)
        service.resultPublisher.receive(on: DispatchQueue.main).sink { result in
            self.resultsSubject.send(result)
        }.store(in: &cancellables)
        service.availableLocalesPublisher.receive(on: DispatchQueue.main).sink { [weak self] locales in
            self?.updateAvailableLocales(locales)
        }.store(in: &cancellables)
    }
    /// Updates the currently available locales using a set ot locales
    func updateAvailableLocales(_ locales:Set<Locale>?) {
        if let locales = locales {
            if availableLocales == nil {
                availableLocales = .init(locales)
            } else {
                availableLocales = availableLocales?.union(locales)
            }
        }
        availableLocalesSubject.send(availableLocales)
    }
}
