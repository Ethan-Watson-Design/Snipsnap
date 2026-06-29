//
//  AnnotatedVideoExporter.swift
//  Snipsnap
//

import AppKit
@preconcurrency import AVFoundation
import CoreImage

enum AnnotatedVideoExporter {

    enum ExportError: LocalizedError {
        case noVideoTrack
        case readerSetupFailed
        case writerSetupFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "The recording has no video track."
            case .readerSetupFailed: return "Could not read the recording."
            case .writerSetupFailed: return "Could not create the annotated video."
            case .exportFailed(let detail): return detail
            }
        }
    }

    private static func runAsync<T>(_ work: @escaping () async throws -> T) throws -> T {
        var outcome: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                outcome = .success(try await work())
            } catch {
                outcome = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try outcome!.get()
    }

    static func export(
        sourceURL: URL,
        canvas: AnnotationCanvasView,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            let canvasSize = canvas.bounds.size
            let hasAnnotations = !canvas.annotations.isEmpty

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outputURL = try exportSynchronously(
                        sourceURL: sourceURL,
                        canvas: canvas,
                        canvasSize: canvasSize,
                        hasAnnotations: hasAnnotations
                    )
                    DispatchQueue.main.async { completion(.success(outputURL)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private static func exportSynchronously(
        sourceURL: URL,
        canvas: AnnotationCanvasView,
        canvasSize: CGSize,
        hasAnnotations: Bool
    ) throws -> URL {
        if !hasAnnotations {
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try runAsync { try await asset.loadTracks(withMediaType: .video) }
        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let naturalSize = try runAsync { try await videoTrack.load(.naturalSize) }
        let transform = try runAsync { try await videoTrack.load(.preferredTransform) }
        let transformed = naturalSize.applying(transform)
        let pixelWidth = Int(abs(transformed.width).rounded())
        let pixelHeight = Int(abs(transformed.height).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw ExportError.readerSetupFailed
        }

        let outputSize = CGSize(width: pixelWidth, height: pixelHeight)
        let duration = try runAsync { try await asset.load(.duration) }
        let audioTracks = try runAsync { try await asset.loadTracks(withMediaType: .audio) }
        let hasAudio = !audioTracks.isEmpty

        let outputDirectory = sourceURL.deletingLastPathComponent()
        let annotatedStem = "\(sourceURL.deletingPathExtension().lastPathComponent) (annotated)"
        let preferredFilename = "\(annotatedStem).mp4"
        let finalURL = CaptureNaming.uniqueURL(in: outputDirectory, preferredFilename: preferredFilename)
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        defer {
            try? FileManager.default.removeItem(at: tempVideoURL)
        }

        try renderAnnotatedVideo(
            asset: asset,
            videoTrack: videoTrack,
            transform: transform,
            outputSize: outputSize,
            canvas: canvas,
            canvasSize: canvasSize,
            to: tempVideoURL
        )

        if hasAudio {
            try muxAudio(from: sourceURL, videoURL: tempVideoURL, outputURL: finalURL, duration: duration)
        } else {
            try FileManager.default.copyItem(at: tempVideoURL, to: finalURL)
        }

        return finalURL
    }

    private static func renderAnnotatedVideo(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        transform: CGAffineTransform,
        outputSize: CGSize,
        canvas: AnnotationCanvasView,
        canvasSize: CGSize,
        to outputURL: URL
    ) throws {
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ExportError.readerSetupFailed }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(writerInput) else { throw ExportError.writerSetupFailed }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ExportError.readerSetupFailed
        }
        guard writer.startWriting() else {
            throw ExportError.writerSetupFailed
        }

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        var sessionStarted = false

        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { break }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !sessionStarted {
                writer.startSession(atSourceTime: presentationTime)
                sessionStarted = true
            }

            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            var ciImage = CIImage(cvPixelBuffer: sourceBuffer)
            if transform != .identity {
                ciImage = ciImage.transformed(by: transform)
                let extent = ciImage.extent
                if extent.origin.x != 0 || extent.origin.y != 0 {
                    ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
                }
            }

            guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(origin: .zero, size: outputSize)) else {
                continue
            }

            let frame = NSImage(cgImage: cgImage, size: outputSize)
            let time = CMTimeGetSeconds(presentationTime)
            let composited: NSImage = DispatchQueue.main.sync {
                canvas.flattenedImage(
                    background: frame,
                    at: time,
                    outputSize: outputSize,
                    mapFromCanvasSize: canvasSize
                )
            }

            guard let pool = adaptor.pixelBufferPool,
                  let pixelBuffer = makePixelBuffer(from: composited, size: outputSize, pool: pool) else {
                continue
            }

            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting {
            group.leave()
        }
        group.wait()

        guard writer.status == .completed else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Video export failed.")
        }
    }

    private static func muxAudio(
        from sourceURL: URL,
        videoURL: URL,
        outputURL: URL,
        duration: CMTime
    ) throws {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let videoAsset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        let sourceVideoTracks = try runAsync { try await videoAsset.loadTracks(withMediaType: .video) }
        guard let sourceVideoTrack = sourceVideoTracks.first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.exportFailed("Could not combine audio and video.")
        }

        let videoDuration = try runAsync { try await videoAsset.load(.duration) }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )

        let sourceAudioTracks = try runAsync { try await sourceAsset.loadTracks(withMediaType: .audio) }
        if let sourceAudioTrack = sourceAudioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let sourceDuration = try runAsync { try await sourceAsset.load(.duration) }
            let audioDuration = min(sourceDuration, duration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not finalize the annotated video.")
        }

        try runAsync {
            try await exportSession.export(to: outputURL, as: .mp4)
        }
    }

    private static func makePixelBuffer(
        from image: NSImage,
        size: CGSize,
        pool: CVPixelBufferPool
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.clear(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
