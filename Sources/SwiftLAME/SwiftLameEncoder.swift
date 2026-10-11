
import AVFAudio
import LAME


public struct SwiftLameEncoder: Sendable {
    
    // MARK: Private
    
    private let configuration: LameConfiguration
    private let destinationUrl: URL
    private let frameCount: AVAudioFrameCount = 1024 * 8
    private let progress: Progress
    private let sourceUrl: URL
    private let timeRange: ClosedRange<TimeInterval>?
    
    // MARK: Lifecycle
    
    /// - Parameter timeRange: The part of the source to encode, in seconds. Encodes all of it if nil.
    public init(
        sourceUrl: URL,
        configuration: LameConfiguration,
        destinationUrl: URL,
        timeRange: ClosedRange<TimeInterval>? = nil,
        progress: Progress = Progress()
    ) throws {
        _ = try AVAudioFile(forReading: sourceUrl)
        self.sourceUrl = sourceUrl
        self.configuration = configuration
        self.destinationUrl = destinationUrl
        self.timeRange = timeRange
        self.progress = progress
    }
    
    // MARK: Encoding
    
    public func encode(priority: TaskPriority = .medium) async throws {
        try await Task(priority: priority) { [self] in
            try _encode()
        }.value
    }
    
    private func _encode() throws {
        let sourceAudioFile = try AVAudioFile(forReading: sourceUrl)
        let audioFormat = sourceAudioFile.processingFormat
        
        guard let sourceAudioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw SwiftLameError.couldNotCreateAudioPCMBuffer
        }
        guard let outputStream = OutputStream(url: destinationUrl, append: true) else {
            throw SwiftLameError.couldNotCreateOutputStreamTo(url: destinationUrl)
        }
        
        let lame = Lame(for: sourceAudioFile, configuration: configuration)
        let mBytesPerFrame = sourceAudioFile.processingFormat.streamDescription.pointee.mBytesPerFrame
        let bufferCapacity = Int(frameCount * mBytesPerFrame)
        var tmpEncodingBuffer = Data(count: bufferCapacity)
        
        let (startFrame, endFrame) = frameRange(in: sourceAudioFile)
        sourceAudioFile.framePosition = startFrame
        progress.totalUnitCount = max(endFrame - startFrame, 0)
        
        outputStream.open()
        var position = startFrame
        
        while position < endFrame {
            if progress.isCancelled {
                break
            }
            
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(frameCount), endFrame - position))
            try sourceAudioFile.read(into: sourceAudioBuffer, frameCount: framesToRead)
            // For compressed files, `length` can be an estimate, so the file may end before `endFrame`.
            guard sourceAudioBuffer.frameLength > 0 else { break }
            
            position += AVAudioFramePosition(sourceAudioBuffer.frameLength)
            try encodeFrame(with: lame, from: sourceAudioBuffer, to: outputStream, using: &tmpEncodingBuffer)
            
            progress.completedUnitCount = position - startFrame
        }
        
        if !progress.isCancelled {
            try finalizeEncoding(with: lame, to: outputStream, using: &tmpEncodingBuffer)
            progress.completedUnitCount = progress.totalUnitCount
        }
        
        outputStream.close()
        
        if progress.isCancelled {
            try? FileManager.default.removeItem(at: destinationUrl)
        }
    }
    
    /// The frames to encode: `timeRange`, rounded to frames and clamped to the file.
    private func frameRange(in audioFile: AVAudioFile) -> (start: AVAudioFramePosition, end: AVAudioFramePosition) {
        guard let timeRange else { return (0, audioFile.length) }
        let sampleRate = audioFile.processingFormat.sampleRate
        let start = AVAudioFramePosition((timeRange.lowerBound * sampleRate).rounded())
        let end = AVAudioFramePosition((timeRange.upperBound * sampleRate).rounded())
        return (start.clamped(to: 0...audioFile.length), end.clamped(to: 0...audioFile.length))
    }
    
    private func encodeFrame(
        with lame: Lame,
        from sourceAudioBuffer: AVAudioPCMBuffer,
        to outputStream: OutputStream,
        using tmpEncodingBuffer: inout Data
    ) throws {
        let sourceChannelData = try sourceAudioBuffer.getChannelData()
        let frameCount = sourceAudioBuffer.frameLength
        let bufferCapacity = tmpEncodingBuffer.count
        
        try tmpEncodingBuffer.withUnsafeMutableBytes { (bufferPointer: UnsafeMutableRawBufferPointer) in
            let memoryBoundBuffer = bufferPointer.bindMemory(to: UInt8.self)
            guard let bufferAddress = memoryBoundBuffer.baseAddress else {
                throw SwiftLameError.couldNotGetRawOutputBufferPointerBaseAddress
            }
            
            let encodeLength = encodeChannelData(
                sourceChannelData,
                with: lame,
                frameCount: frameCount,
                usingBufferAt: bufferAddress,
                capacity: bufferCapacity
            )
            
            outputStream.write(bufferAddress, maxLength: encodeLength)
        }
    }
    
    /// Writes the frames LAME still holds back.
    private func finalizeEncoding(with lame: Lame, to outputStream: OutputStream, using tmpEncodingBuffer: inout Data) throws {
        let bufferCapacity = tmpEncodingBuffer.count
        try tmpEncodingBuffer.withUnsafeMutableBytes { (bufferPointer: UnsafeMutableRawBufferPointer) in
            guard let bufferAddress = bufferPointer.bindMemory(to: UInt8.self).baseAddress else {
                throw SwiftLameError.couldNotGetRawOutputBufferPointerBaseAddress
            }
            let finalEncodeLength = lame.finalizeEncoding(usingBufferAt: bufferAddress, with: bufferCapacity)
            outputStream.write(bufferAddress, maxLength: finalEncodeLength)
        }
    }
    
    private func encodeChannelData(
        _ channelData: AVAudioChannelData,
        with lame: Lame,
        frameCount: AVAudioFrameCount,
        usingBufferAt bufferAddress: UnsafeMutablePointer<UInt8>,
        capacity: Int
    ) -> Int {
        switch channelData {
        case .float(let data):
            return lame.encodeIEEEFloatData(data, frameCount: frameCount, fillingBufferAt: bufferAddress, with: capacity)
        case .int16(let data):
            return lame.encodeInt16Data(data, frameCount: frameCount, fillingBufferAt: bufferAddress, with: capacity)
        case .int32(let data):
            return lame.encodeInt32Data(data, frameCount: frameCount, fillingBufferAt: bufferAddress, with: capacity)
        }
    }
}


private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
